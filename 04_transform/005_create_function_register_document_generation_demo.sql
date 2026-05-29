-- 005_create_function_register_document_generation.sql
-- ContractFlow SQL
-- Функция регистрации генерации договорного документа

CREATE OR REPLACE FUNCTION core.register_document_generation(
    p_document_number varchar,
    p_username varchar,
    p_generation_status_code varchar DEFAULT 'SUCCESS',
    p_error_message text DEFAULT NULL
)
RETURNS TABLE (
    created_generation_id integer,
    generated_file_name varchar,
    generated_file_path text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_document_id integer;
    v_template_id integer;
    v_user_id integer;
    v_generation_status_id integer;

    v_legal_entity_short_name varchar;
    v_counterparty_short_name varchar;
    v_document_type_code varchar;

    v_file_prefix varchar;
BEGIN
    /* =========================
       1. Находим документ
       ========================= */

    SELECT
        cd.document_id,
        le.short_name,
        COALESCE(NULLIF(cp.short_name, ''), cp.full_name),
        dt.code
    INTO
        v_document_id,
        v_legal_entity_short_name,
        v_counterparty_short_name,
        v_document_type_code
    FROM core.contract_documents cd
    JOIN core.contracts c
        ON c.contract_id = cd.contract_id
    JOIN core.legal_entities le
        ON le.legal_entity_id = c.legal_entity_id
    JOIN core.counterparties cp
        ON cp.counterparty_id = c.counterparty_id
    JOIN core.document_types dt
        ON dt.document_type_id = cd.document_type_id
    WHERE cd.document_number = p_document_number;

    IF v_document_id IS NULL THEN
        RAISE EXCEPTION 'Документ с номером % не найден', p_document_number;
    END IF;


    /* =========================
       2. Находим активный шаблон
       ========================= */

    SELECT t.template_id
    INTO v_template_id
    FROM core.document_templates t
    JOIN core.legal_entities le
        ON le.legal_entity_id = t.legal_entity_id
    JOIN core.document_types dt
        ON dt.document_type_id = t.document_type_id
    WHERE le.short_name = v_legal_entity_short_name
      AND dt.code = v_document_type_code
      AND t.is_active = true;

    IF v_template_id IS NULL THEN
        RAISE EXCEPTION 'Активный шаблон для юрлица % и типа документа % не найден',
            v_legal_entity_short_name,
            v_document_type_code;
    END IF;


    /* =========================
       3. Находим пользователя
       ========================= */

    SELECT user_id
    INTO v_user_id
    FROM core.users
    WHERE username = p_username;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Пользователь % не найден', p_username;
    END IF;


    /* =========================
       4. Находим статус генерации
       ========================= */

    SELECT generation_status_id
    INTO v_generation_status_id
    FROM core.generation_statuses
    WHERE code = p_generation_status_code;

    IF v_generation_status_id IS NULL THEN
        RAISE EXCEPTION 'Статус генерации % не найден', p_generation_status_code;
    END IF;


    /* =========================
       5. Формируем имя файла
       ========================= */

    v_file_prefix :=
        CASE v_document_type_code
            WHEN 'CONTRACT' THEN 'Договор'
            WHEN 'NEW_EDITION' THEN 'Новая редакция'
            WHEN 'ADDITIONAL_AGREEMENT' THEN 'Доп. соглашение'
            WHEN 'PROTOCOL_OF_DISAGREEMENT' THEN 'Протокол разногласий'
            WHEN 'PERSONAL_ADDITIONAL_AGREEMENT' THEN 'Персональное ДС'
            ELSE 'Документ'
        END;

    generated_file_name :=
        v_file_prefix
        || ' '
        || p_document_number
        || ' ('
        || v_counterparty_short_name
        || ').pdf';

    generated_file_path :=
        '06_app/generated_documents/'
        || v_legal_entity_short_name
        || '/'
        || generated_file_name;


    /* =========================
       6. Пишем лог генерации
       ========================= */

    INSERT INTO core.document_generation_log (
        document_id,
        template_id,
        generated_by,
        generated_at,
        generation_status_id,
        generated_file_name,
        generated_file_path,
        error_message
    )
    VALUES (
        v_document_id,
        v_template_id,
        v_user_id,
        now(),
        v_generation_status_id,
        generated_file_name,
        generated_file_path,
        p_error_message
    )
    RETURNING generation_id INTO created_generation_id;

    RETURN NEXT;
END;
$$;