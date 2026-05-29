-- 004_create_function_create_contract_document.sql
-- ContractFlow SQL
-- Функция создания договорного документа

CREATE OR REPLACE FUNCTION core.create_contract_document(
    p_legal_entity_short_name varchar,
    p_counterparty_inn varchar,
    p_document_type_code varchar,
    p_username varchar,
    p_parent_document_number varchar DEFAULT NULL,
    p_document_date date DEFAULT current_date,
    p_comment text DEFAULT NULL
)
RETURNS TABLE (
    created_document_id integer,
    created_document_number varchar,
    planned_file_name varchar
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_legal_entity_id integer;
    v_counterparty_id integer;
    v_contract_id integer;
    v_document_type_id integer;
    v_document_status_id integer;
    v_delivery_channel_id integer;
    v_user_id integer;

    v_counterparty_signatory_id integer;
    v_legal_entity_signatory_id integer;

    v_parent_document_id integer;
    v_parent_document_number varchar;

    v_date_part varchar;
    v_document_seq integer;
    v_document_number varchar;

    v_file_prefix varchar;
    v_counterparty_short_name varchar;
BEGIN
    /* =========================
       1. Находим наше юрлицо
       ========================= */

    SELECT legal_entity_id
    INTO v_legal_entity_id
    FROM core.legal_entities
    WHERE short_name = p_legal_entity_short_name;

    IF v_legal_entity_id IS NULL THEN
        RAISE EXCEPTION 'Юрлицо с short_name % не найдено', p_legal_entity_short_name;
    END IF;


    /* =========================
       2. Находим контрагента
       ========================= */

    SELECT
        counterparty_id,
        COALESCE(NULLIF(short_name, ''), full_name)
    INTO
        v_counterparty_id,
        v_counterparty_short_name
    FROM core.counterparties
    WHERE inn = p_counterparty_inn;

    IF v_counterparty_id IS NULL THEN
        RAISE EXCEPTION 'Контрагент с ИНН % не найден', p_counterparty_inn;
    END IF;


    /* =========================
       3. Находим тип документа
       ========================= */

    SELECT document_type_id
    INTO v_document_type_id
    FROM core.document_types
    WHERE code = p_document_type_code;

    IF v_document_type_id IS NULL THEN
        RAISE EXCEPTION 'Тип документа % не найден', p_document_type_code;
    END IF;


    /* =========================
       4. Находим пользователя
       ========================= */

    SELECT user_id
    INTO v_user_id
    FROM core.users
    WHERE username = p_username;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Пользователь % не найден', p_username;
    END IF;


    /* =========================
       5. Находим активных подписантов
       ========================= */

    SELECT signatory_id
    INTO v_legal_entity_signatory_id
    FROM core.legal_entity_signatories
    WHERE legal_entity_id = v_legal_entity_id
      AND is_active = true;

    IF v_legal_entity_signatory_id IS NULL THEN
        RAISE EXCEPTION 'Активный подписант юрлица % не найден', p_legal_entity_short_name;
    END IF;

    SELECT signatory_id
    INTO v_counterparty_signatory_id
    FROM core.counterparty_signatories
    WHERE counterparty_id = v_counterparty_id
      AND is_active = true
    ORDER BY signatory_id DESC
    LIMIT 1;

    IF v_counterparty_signatory_id IS NULL THEN
        RAISE EXCEPTION 'Активный подписант контрагента с ИНН % не найден', p_counterparty_inn;
    END IF;


    /* =========================
       6. Создаём или находим договорную связку
       ========================= */

    INSERT INTO core.contracts (
        legal_entity_id,
        counterparty_id,
        is_active
    )
    VALUES (
        v_legal_entity_id,
        v_counterparty_id,
        true
    )
    ON CONFLICT (legal_entity_id, counterparty_id) DO UPDATE
    SET is_active = true
    RETURNING contract_id INTO v_contract_id;


    /* =========================
       7. Проверяем parent_document
       ========================= */

    IF p_document_type_code = 'CONTRACT'
       AND NULLIF(BTRIM(p_parent_document_number), '') IS NOT NULL THEN
        RAISE EXCEPTION 'Для CONTRACT parent_document_number должен быть пустым';
    END IF;

    IF p_document_type_code <> 'CONTRACT'
       AND NULLIF(BTRIM(p_parent_document_number), '') IS NULL THEN
        RAISE EXCEPTION 'Для документа типа % нужно указать parent_document_number',
            p_document_type_code;
    END IF;

    IF NULLIF(BTRIM(p_parent_document_number), '') IS NOT NULL THEN
        SELECT
            document_id,
            document_number
        INTO
            v_parent_document_id,
            v_parent_document_number
        FROM core.contract_documents
        WHERE document_number = p_parent_document_number
          AND contract_id = v_contract_id;

        IF v_parent_document_id IS NULL THEN
            RAISE EXCEPTION 'Родительский документ % не найден в рамках этой договорной связки',
                p_parent_document_number;
        END IF;
    END IF;


    /* =========================
       8. Генерируем номер документа

       CONTRACT                  -> НСЭ-260525-1
       NEW_EDITION               -> НСЭ-260525-1-РЕД
       ADDITIONAL_AGREEMENT      -> НСЭ-260525-1-ДС-1
       PROTOCOL_OF_DISAGREEMENT  -> НСЭ-260525-1-ПР
       PERSONAL_ADDITIONAL...    -> НСЭ-260525-1-ПДС
       ========================= */

    IF p_document_type_code = 'CONTRACT' THEN

        v_date_part := to_char(p_document_date, 'YYMMDD');

        SELECT COUNT(*) + 1
        INTO v_document_seq
        FROM core.contract_documents cd
        JOIN core.contracts c
            ON c.contract_id = cd.contract_id
        WHERE c.legal_entity_id = v_legal_entity_id
          AND cd.document_type_id = v_document_type_id
          AND cd.document_date = p_document_date;

        LOOP
            v_document_number :=
                p_legal_entity_short_name
                || '-'
                || v_date_part
                || '-'
                || v_document_seq::varchar;

            EXIT WHEN NOT EXISTS (
                SELECT 1
                FROM core.contract_documents
                WHERE document_number = v_document_number
            );

            v_document_seq := v_document_seq + 1;
        END LOOP;

    ELSIF p_document_type_code = 'ADDITIONAL_AGREEMENT' THEN

        SELECT COUNT(*) + 1
        INTO v_document_seq
        FROM core.contract_documents
        WHERE parent_document_id = v_parent_document_id
          AND document_type_id = v_document_type_id;

        LOOP
            v_document_number :=
                v_parent_document_number
                || '-ДС-'
                || v_document_seq::varchar;

            EXIT WHEN NOT EXISTS (
                SELECT 1
                FROM core.contract_documents
                WHERE document_number = v_document_number
            );

            v_document_seq := v_document_seq + 1;
        END LOOP;

    ELSIF p_document_type_code = 'NEW_EDITION' THEN

        v_document_number := v_parent_document_number || '-РЕД';

        IF EXISTS (
            SELECT 1
            FROM core.contract_documents
            WHERE document_number = v_document_number
        ) THEN
            RAISE EXCEPTION 'Документ с номером % уже существует', v_document_number;
        END IF;

    ELSIF p_document_type_code = 'PROTOCOL_OF_DISAGREEMENT' THEN

        v_document_number := v_parent_document_number || '-ПР';

        IF EXISTS (
            SELECT 1
            FROM core.contract_documents
            WHERE document_number = v_document_number
        ) THEN
            RAISE EXCEPTION 'Документ с номером % уже существует', v_document_number;
        END IF;

    ELSIF p_document_type_code = 'PERSONAL_ADDITIONAL_AGREEMENT' THEN

        v_document_number := v_parent_document_number || '-ПДС';

        IF EXISTS (
            SELECT 1
            FROM core.contract_documents
            WHERE document_number = v_document_number
        ) THEN
            RAISE EXCEPTION 'Документ с номером % уже существует', v_document_number;
        END IF;

    ELSE
        RAISE EXCEPTION 'Для типа документа % не описано правило генерации номера',
            p_document_type_code;
    END IF;


    /* =========================
       9. Создаём документ
       ========================= */

    INSERT INTO core.contract_documents (
        contract_id,
        document_type_id,
        document_number,
        document_date,
        parent_document_id,
        counterparty_signatory_id,
        legal_entity_signatory_id,
        is_actual,
        is_archived,
        comment
    )
    VALUES (
        v_contract_id,
        v_document_type_id,
        v_document_number,
        p_document_date,
        v_parent_document_id,
        v_counterparty_signatory_id,
        v_legal_entity_signatory_id,
        true,
        false,
        COALESCE(p_comment, 'Документ создан через core.create_contract_document')
    )
    RETURNING document_id INTO created_document_id;

    created_document_number := v_document_number;


    /* =========================
       10. Ставим статус GENERATED
       ========================= */

    SELECT document_status_id
    INTO v_document_status_id
    FROM core.document_statuses
    WHERE code = 'GENERATED';

    IF v_document_status_id IS NULL THEN
        RAISE EXCEPTION 'Статус GENERATED не найден в core.document_statuses';
    END IF;

    SELECT delivery_channel_id
    INTO v_delivery_channel_id
    FROM core.delivery_channels
    WHERE code = 'INTERNAL';

    IF v_delivery_channel_id IS NULL THEN
        RAISE EXCEPTION 'Канал INTERNAL не найден в core.delivery_channels';
    END IF;

    INSERT INTO core.document_status_history (
        document_id,
        document_status_id,
        delivery_channel_id,
        status_date,
        changed_by,
        comment
    )
    VALUES (
        created_document_id,
        v_document_status_id,
        v_delivery_channel_id,
        now(),
        v_user_id,
        'Документ создан в системе'
    );


    /* =========================
       11. Формируем плановое имя файла
       ========================= */

    v_file_prefix :=
        CASE p_document_type_code
            WHEN 'CONTRACT' THEN 'Договор'
            WHEN 'NEW_EDITION' THEN 'Новая редакция'
            WHEN 'ADDITIONAL_AGREEMENT' THEN 'Доп. соглашение'
            WHEN 'PROTOCOL_OF_DISAGREEMENT' THEN 'Протокол разногласий'
            WHEN 'PERSONAL_ADDITIONAL_AGREEMENT' THEN 'Персональное ДС'
            ELSE 'Документ'
        END;

    planned_file_name :=
        v_file_prefix
        || ' '
        || created_document_number
        || ' ('
        || v_counterparty_short_name
        || ').pdf';

    RETURN NEXT;
END;
$$;