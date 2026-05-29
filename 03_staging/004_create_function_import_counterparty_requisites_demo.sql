-- 004_create_function_import_counterparty_requisites.sql
-- ContractFlow SQL
-- Функция импорта валидных реквизитов из staging в core

CREATE OR REPLACE FUNCTION stg.import_counterparty_requisites(
    p_load_batch_id integer
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_counterparty_id integer;
    v_imported_count integer := 0;
    raw_row record;
BEGIN
    /* =========================
       1. Проверяем, что batch существует
       ========================= */

    IF NOT EXISTS (
        SELECT 1
        FROM stg.load_batches
        WHERE load_batch_id = p_load_batch_id
    ) THEN
        RAISE EXCEPTION 'Load batch % не найден', p_load_batch_id;
    END IF;


    /* =========================
       2. Проверяем, что batch не был импортирован ранее
       ========================= */

    IF EXISTS (
        SELECT 1
        FROM stg.load_batches
        WHERE load_batch_id = p_load_batch_id
          AND load_status = 'IMPORTED'
    ) THEN
        RAISE EXCEPTION 'Load batch % уже импортирован', p_load_batch_id;
    END IF;


    /* =========================
       3. Проверяем, что batch прошёл валидацию
       ========================= */

    IF NOT EXISTS (
        SELECT 1
        FROM stg.load_batches
        WHERE load_batch_id = p_load_batch_id
          AND load_status = 'VALIDATED'
    ) THEN
        RAISE EXCEPTION 'Load batch % не готов к импорту. Сначала выполните stg.validate_counterparty_requisites(%)',
            p_load_batch_id,
            p_load_batch_id;
    END IF;


    /* =========================
       4. Проверяем, что нет ERROR
       ========================= */

    IF EXISTS (
        SELECT 1
        FROM stg.validation_errors
        WHERE load_batch_id = p_load_batch_id
          AND severity = 'ERROR'
    ) THEN
        RAISE EXCEPTION 'Load batch % содержит ERROR. Импорт запрещён', p_load_batch_id;
    END IF;


    /* =========================
       5. Для первой версии импортируем только новых контрагентов
       ========================= */

    IF EXISTS (
        SELECT 1
        FROM stg.counterparty_requisites_raw raw_check
        JOIN core.counterparties c 
            ON c.inn = raw_check.inn
        WHERE raw_check.load_batch_id = p_load_batch_id
    ) THEN
        RAISE EXCEPTION 'В load batch % есть контрагент, который уже существует в core. Для обновления реквизитов нужен отдельный сценарий',
            p_load_batch_id;
    END IF;


    /* =========================
       6. Импортируем строки batch
       ========================= */

    FOR raw_row IN
        SELECT *
        FROM stg.counterparty_requisites_raw
        WHERE load_batch_id = p_load_batch_id
          AND processing_status IN ('VALID', 'VALID_WITH_WARNINGS')
        ORDER BY raw_id
    LOOP
        /* Контрагент */

        INSERT INTO core.counterparties (
            full_name,
            short_name,
            legal_form,
            counterparty_type,
            inn,
            kpp,
            ogrn,
            legal_address,
            mailing_address,
            phone_number,
            email_address
        )
        VALUES (
            BTRIM(raw_row.full_name),
            NULLIF(BTRIM(raw_row.short_name), ''),
            BTRIM(raw_row.legal_form),
            BTRIM(raw_row.counterparty_type),
            BTRIM(raw_row.inn),
            NULLIF(BTRIM(raw_row.kpp), ''),
            CASE
                WHEN raw_row.counterparty_type = 'LEGAL_ENTITY'
                    THEN NULLIF(BTRIM(raw_row.ogrn), '')
                WHEN raw_row.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
                    THEN NULLIF(BTRIM(raw_row.ogrnip), '')
            END,
            NULLIF(BTRIM(raw_row.legal_address), ''),
            NULLIF(BTRIM(raw_row.mailing_address), ''),
            NULLIF(BTRIM(raw_row.phone_number), ''),
            NULLIF(BTRIM(raw_row.email_address), '')
        )
        RETURNING counterparty_id INTO v_counterparty_id;


        /* Данные ИП */

        IF raw_row.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR' THEN
            INSERT INTO core.individual_entrepreneur_details (
                counterparty_id,
                passport_data
            )
            VALUES (
                v_counterparty_id,
                BTRIM(raw_row.passport_data)
            );
        END IF;


        /* Подписант контрагента */

        INSERT INTO core.counterparty_signatories (
            counterparty_id,
            position_nom,
            position_gen,
            full_name_nom,
            full_name_gen,
            initials_lastname,
            legal_basis_gen,
            is_active
        )
        VALUES (
            v_counterparty_id,
            BTRIM(raw_row.position_nom),
            NULLIF(BTRIM(raw_row.position_gen), ''),
            BTRIM(raw_row.full_name_nom),
            NULLIF(BTRIM(raw_row.full_name_gen), ''),
            NULLIF(BTRIM(raw_row.initials_lastname), ''),
            BTRIM(raw_row.legal_basis_gen),
            true
        );


        /* Банковский счёт 1 */

        INSERT INTO core.bank_accounts (
            counterparty_id,
            account_number,
            corr_account,
            bik,
            bank_name,
            account_order
        )
        VALUES (
            v_counterparty_id,
            BTRIM(raw_row.account_number_1),
            BTRIM(raw_row.corr_account_1),
            BTRIM(raw_row.bik_1),
            BTRIM(raw_row.bank_name_1),
            1
        );


        /* Банковский счёт 2 */

        IF NULLIF(BTRIM(raw_row.account_number_2), '') IS NOT NULL THEN
            INSERT INTO core.bank_accounts (
                counterparty_id,
                account_number,
                corr_account,
                bik,
                bank_name,
                account_order
            )
            VALUES (
                v_counterparty_id,
                BTRIM(raw_row.account_number_2),
                BTRIM(raw_row.corr_account_2),
                BTRIM(raw_row.bik_2),
                BTRIM(raw_row.bank_name_2),
                2
            );
        END IF;


        /* Банковский счёт 3 */

        IF NULLIF(BTRIM(raw_row.account_number_3), '') IS NOT NULL THEN
            INSERT INTO core.bank_accounts (
                counterparty_id,
                account_number,
                corr_account,
                bik,
                bank_name,
                account_order
            )
            VALUES (
                v_counterparty_id,
                BTRIM(raw_row.account_number_3),
                BTRIM(raw_row.corr_account_3),
                BTRIM(raw_row.bik_3),
                BTRIM(raw_row.bank_name_3),
                3
            );
        END IF;


        /* Отмечаем raw-строку как импортированную */

        UPDATE stg.counterparty_requisites_raw
        SET
            processing_status = 'IMPORTED',
            processed_counterparty_id = v_counterparty_id
        WHERE raw_id = raw_row.raw_id;

        v_imported_count := v_imported_count + 1;
    END LOOP;


    /* =========================
       7. Если нечего импортировать
       ========================= */

    IF v_imported_count = 0 THEN
        RAISE EXCEPTION 'В load batch % нет строк со статусом VALID или VALID_WITH_WARNINGS', p_load_batch_id;
    END IF;


    /* =========================
       8. Обновляем статус batch
       ========================= */

    UPDATE stg.load_batches
    SET
        load_status = 'IMPORTED',
        imported_at = now()
    WHERE load_batch_id = p_load_batch_id;


    RETURN v_imported_count;
END;
$$;