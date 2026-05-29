-- 003_create_function_validate_counterparty_requisites.sql
-- ContractFlow SQL
-- Функция валидации реквизитов контрагента в staging

CREATE OR REPLACE FUNCTION stg.validate_counterparty_requisites(
    p_load_batch_id integer
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    /* =========================
       CHECK LOAD BATCH EXISTS
       ========================= */

    IF NOT EXISTS (
        SELECT 1
        FROM stg.load_batches
        WHERE load_batch_id = p_load_batch_id
    ) THEN
        RAISE EXCEPTION 'Load batch % не найден', p_load_batch_id;
    END IF;


    /* =========================
       RESET PREVIOUS VALIDATION
       ========================= */

    DELETE FROM stg.validation_errors
    WHERE load_batch_id = p_load_batch_id;

    UPDATE stg.counterparty_requisites_raw
    SET processing_status = 'RAW'
    WHERE load_batch_id = p_load_batch_id;


    /* =========================
       REQUIRED FIELDS
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'counterparty_type',
           'ERROR', 'REQUIRED_FIELD_MISSING', 'Не заполнен тип контрагента'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(counterparty_type), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'counterparty_type',
           'ERROR', 'INVALID_COUNTERPARTY_TYPE', 'Тип контрагента должен быть LEGAL_ENTITY или INDIVIDUAL_ENTREPRENEUR'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(counterparty_type), '') IS NOT NULL
      AND counterparty_type NOT IN ('LEGAL_ENTITY', 'INDIVIDUAL_ENTREPRENEUR');

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'full_name',
           'ERROR', 'REQUIRED_FIELD_MISSING', 'Не заполнено полное наименование'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(full_name), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'inn',
           'ERROR', 'REQUIRED_FIELD_MISSING', 'Не заполнен ИНН'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(inn), '') IS NULL;


    /* =========================
       INN / KPP / OGRN / OGRNIP
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'inn',
           'ERROR', 'INVALID_INN_FORMAT', 'ИНН юрлица должен содержать 10 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(inn), '') IS NOT NULL
      AND inn !~ '^[0-9]{10}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'inn',
           'ERROR', 'INVALID_INN_FORMAT', 'ИНН ИП должен содержать 12 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
      AND NULLIF(BTRIM(inn), '') IS NOT NULL
      AND inn !~ '^[0-9]{12}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'kpp',
           'ERROR', 'KPP_REQUIRED_FOR_LEGAL_ENTITY', 'КПП обязателен для юрлица'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(kpp), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'kpp',
           'ERROR', 'INVALID_KPP_FORMAT', 'КПП должен содержать 9 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(kpp), '') IS NOT NULL
      AND kpp !~ '^[0-9]{9}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'kpp',
           'ERROR', 'KPP_NOT_ALLOWED_FOR_IE', 'Для ИП КПП должен быть пустым'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
      AND NULLIF(BTRIM(kpp), '') IS NOT NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'ogrn',
           'ERROR', 'OGRN_REQUIRED', 'ОГРН обязателен для юрлица'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(ogrn), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'ogrn',
           'ERROR', 'INVALID_OGRN_FORMAT', 'ОГРН должен содержать 13 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(ogrn), '') IS NOT NULL
      AND ogrn !~ '^[0-9]{13}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'ogrnip',
           'ERROR', 'OGRNIP_NOT_ALLOWED_FOR_LEGAL_ENTITY', 'Для юрлица поле ОГРНИП должно быть пустым, используйте ОГРН'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(ogrnip), '') IS NOT NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'ogrnip',
           'ERROR', 'OGRNIP_REQUIRED', 'ОГРНИП обязателен для ИП'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
      AND NULLIF(BTRIM(ogrnip), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'ogrnip',
           'ERROR', 'INVALID_OGRNIP_FORMAT', 'ОГРНИП должен содержать 15 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
      AND NULLIF(BTRIM(ogrnip), '') IS NOT NULL
      AND ogrnip !~ '^[0-9]{15}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'ogrn',
           'ERROR', 'OGRN_NOT_ALLOWED_FOR_IE', 'Для ИП поле ОГРН должно быть пустым, используйте ОГРНИП'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
      AND NULLIF(BTRIM(ogrn), '') IS NOT NULL;


    /* =========================
       SIGNATORY
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'position_nom',
           'ERROR', 'SIGNATORY_FIELD_MISSING', 'Не заполнена должность подписанта в именительном падеже'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(position_nom), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'full_name_nom',
           'ERROR', 'SIGNATORY_FIELD_MISSING', 'Не заполнено ФИО подписанта в именительном падеже'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(full_name_nom), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'full_name_gen',
           'WARNING', 'SIGNATORY_GENITIVE_MISSING', 'Не заполнено ФИО подписанта в родительном падеже'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(full_name_gen), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'initials_lastname',
           'ERROR', 'SIGNATORY_FIELD_MISSING', 'Не заполнено поле И.О. Фамилия'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(initials_lastname), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'legal_basis_gen',
           'ERROR', 'SIGNATORY_FIELD_MISSING', 'Не заполнено основание полномочий'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(legal_basis_gen), '') IS NULL;


    /* =========================
       PASSPORT FOR IE
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'passport_data',
           'ERROR', 'PASSPORT_REQUIRED_FOR_IE', 'Паспортные данные обязательны для ИП'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
      AND NULLIF(BTRIM(passport_data), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'passport_data',
           'WARNING', 'PASSPORT_NOT_EXPECTED_FOR_LEGAL_ENTITY', 'Для юрлица паспортные данные обычно не заполняются'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND counterparty_type = 'LEGAL_ENTITY'
      AND NULLIF(BTRIM(passport_data), '') IS NOT NULL;


    /* =========================
       CONTACTS
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'email_address',
           'WARNING', 'EMAIL_MISSING', 'Не заполнен email'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(email_address), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'email_address',
           'WARNING', 'INVALID_EMAIL_FORMAT', 'Email имеет некорректный формат'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(email_address), '') IS NOT NULL
      AND email_address !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'phone_number',
           'WARNING', 'PHONE_FORMAT_WARNING', 'Телефон выглядит нестандартно'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(phone_number), '') IS NOT NULL
      AND phone_number !~ '^[+]?[0-9\-\s()]{7,30}$';


    /* =========================
       BANK ACCOUNT 1
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'account_number_1',
           'ERROR', 'BANK_ACCOUNT_REQUIRED', 'Хотя бы один расчётный счёт обязателен'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(account_number_1), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'account_number_1',
           'ERROR', 'INVALID_ACCOUNT_NUMBER_FORMAT', 'Расчётный счёт должен содержать 20 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(account_number_1), '') IS NOT NULL
      AND account_number_1 !~ '^[0-9]{20}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'corr_account_1',
           'ERROR', 'CORR_ACCOUNT_REQUIRED', 'Корреспондентский счёт обязателен'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(corr_account_1), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'corr_account_1',
           'ERROR', 'INVALID_CORR_ACCOUNT_FORMAT', 'Корреспондентский счёт должен содержать 20 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(corr_account_1), '') IS NOT NULL
      AND corr_account_1 !~ '^[0-9]{20}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bik_1',
           'ERROR', 'BIK_REQUIRED', 'БИК обязателен'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(bik_1), '') IS NULL;

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bik_1',
           'ERROR', 'INVALID_BIK_FORMAT', 'БИК должен содержать 9 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(bik_1), '') IS NOT NULL
      AND bik_1 !~ '^[0-9]{9}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bank_name_1',
           'ERROR', 'BANK_NAME_REQUIRED', 'Не заполнено название банка'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(bank_name_1), '') IS NULL;


    /* =========================
       BANK ACCOUNT 2
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bank_account_2',
           'ERROR', 'INCOMPLETE_BANK_ACCOUNT_2', 'Банковские реквизиты 2 заполнены не полностью'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND (
          NULLIF(BTRIM(account_number_2), '') IS NOT NULL
          OR NULLIF(BTRIM(corr_account_2), '') IS NOT NULL
          OR NULLIF(BTRIM(bik_2), '') IS NOT NULL
          OR NULLIF(BTRIM(bank_name_2), '') IS NOT NULL
      )
      AND (
          NULLIF(BTRIM(account_number_2), '') IS NULL
          OR NULLIF(BTRIM(corr_account_2), '') IS NULL
          OR NULLIF(BTRIM(bik_2), '') IS NULL
          OR NULLIF(BTRIM(bank_name_2), '') IS NULL
      );

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'account_number_2',
           'ERROR', 'INVALID_ACCOUNT_NUMBER_2_FORMAT', 'Расчётный счёт 2 должен содержать 20 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(account_number_2), '') IS NOT NULL
      AND account_number_2 !~ '^[0-9]{20}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'corr_account_2',
           'ERROR', 'INVALID_CORR_ACCOUNT_2_FORMAT', 'Корреспондентский счёт 2 должен содержать 20 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(corr_account_2), '') IS NOT NULL
      AND corr_account_2 !~ '^[0-9]{20}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bik_2',
           'ERROR', 'INVALID_BIK_2_FORMAT', 'БИК 2 должен содержать 9 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(bik_2), '') IS NOT NULL
      AND bik_2 !~ '^[0-9]{9}$';


    /* =========================
       BANK ACCOUNT 3
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bank_account_3',
           'ERROR', 'INCOMPLETE_BANK_ACCOUNT_3', 'Банковские реквизиты 3 заполнены не полностью'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND (
          NULLIF(BTRIM(account_number_3), '') IS NOT NULL
          OR NULLIF(BTRIM(corr_account_3), '') IS NOT NULL
          OR NULLIF(BTRIM(bik_3), '') IS NOT NULL
          OR NULLIF(BTRIM(bank_name_3), '') IS NOT NULL
      )
      AND (
          NULLIF(BTRIM(account_number_3), '') IS NULL
          OR NULLIF(BTRIM(corr_account_3), '') IS NULL
          OR NULLIF(BTRIM(bik_3), '') IS NULL
          OR NULLIF(BTRIM(bank_name_3), '') IS NULL
      );

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'account_number_3',
           'ERROR', 'INVALID_ACCOUNT_NUMBER_3_FORMAT', 'Расчётный счёт 3 должен содержать 20 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(account_number_3), '') IS NOT NULL
      AND account_number_3 !~ '^[0-9]{20}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'corr_account_3',
           'ERROR', 'INVALID_CORR_ACCOUNT_3_FORMAT', 'Корреспондентский счёт 3 должен содержать 20 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(corr_account_3), '') IS NOT NULL
      AND corr_account_3 !~ '^[0-9]{20}$';

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT load_batch_id, raw_id, row_number, 'bik_3',
           'ERROR', 'INVALID_BIK_3_FORMAT', 'БИК 3 должен содержать 9 цифр'
    FROM stg.counterparty_requisites_raw
    WHERE load_batch_id = p_load_batch_id
      AND NULLIF(BTRIM(bik_3), '') IS NOT NULL
      AND bik_3 !~ '^[0-9]{9}$';


    /* =========================
       DUPLICATES
       ========================= */

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT raw_row.load_batch_id, raw_row.raw_id, raw_row.row_number, 'inn',
           'WARNING', 'COUNTERPARTY_ALREADY_EXISTS', 'Контрагент с таким ИНН уже есть в core. Проверьте актуальность реквизитов'
    FROM stg.counterparty_requisites_raw raw_row
    WHERE raw_row.load_batch_id = p_load_batch_id
      AND EXISTS (
          SELECT 1
          FROM core.counterparties c
          WHERE c.inn = raw_row.inn
      );

    INSERT INTO stg.validation_errors (
        load_batch_id, raw_id, row_number, field_name,
        severity, error_code, error_message
    )
    SELECT raw_row.load_batch_id, raw_row.raw_id, raw_row.row_number, 'inn',
           'ERROR', 'DUPLICATE_INN_IN_BATCH', 'Внутри одной загрузки найден дубль ИНН'
    FROM stg.counterparty_requisites_raw raw_row
    WHERE raw_row.load_batch_id = p_load_batch_id
      AND raw_row.inn IN (
          SELECT inn
          FROM stg.counterparty_requisites_raw
          WHERE load_batch_id = p_load_batch_id
            AND NULLIF(BTRIM(inn), '') IS NOT NULL
          GROUP BY inn
          HAVING COUNT(*) > 1
      );


    /* =========================
       UPDATE ROW STATUSES
       ========================= */

    UPDATE stg.counterparty_requisites_raw raw_row
    SET processing_status =
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM stg.validation_errors e
                WHERE e.raw_id = raw_row.raw_id
                  AND e.severity = 'ERROR'
            )
            THEN 'INVALID'

            WHEN EXISTS (
                SELECT 1
                FROM stg.validation_errors e
                WHERE e.raw_id = raw_row.raw_id
                  AND e.severity = 'WARNING'
            )
            THEN 'VALID_WITH_WARNINGS'

            ELSE 'VALID'
        END
    WHERE raw_row.load_batch_id = p_load_batch_id;


    /* =========================
       UPDATE BATCH STATUS
       ========================= */

    UPDATE stg.load_batches b
    SET
        total_rows = (
            SELECT COUNT(*)
            FROM stg.counterparty_requisites_raw raw_row
            WHERE raw_row.load_batch_id = p_load_batch_id
        ),
        valid_rows = (
            SELECT COUNT(*)
            FROM stg.counterparty_requisites_raw raw_row
            WHERE raw_row.load_batch_id = p_load_batch_id
              AND raw_row.processing_status = 'VALID'
        ),
        warning_rows = (
            SELECT COUNT(*)
            FROM stg.counterparty_requisites_raw raw_row
            WHERE raw_row.load_batch_id = p_load_batch_id
              AND raw_row.processing_status = 'VALID_WITH_WARNINGS'
        ),
        invalid_rows = (
            SELECT COUNT(*)
            FROM stg.counterparty_requisites_raw raw_row
            WHERE raw_row.load_batch_id = p_load_batch_id
              AND raw_row.processing_status = 'INVALID'
        ),
        load_status =
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM stg.validation_errors e
                    WHERE e.load_batch_id = p_load_batch_id
                      AND e.severity = 'ERROR'
                )
                THEN 'INVALID'
                ELSE 'VALIDATED'
            END
    WHERE b.load_batch_id = p_load_batch_id;

END;
$$;