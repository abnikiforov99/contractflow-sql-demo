-- 006_create_function_update_document_status.sql
-- ContractFlow SQL
-- Функция обновления статуса договорного документа

CREATE OR REPLACE FUNCTION core.update_document_status(
    p_document_number varchar,
    p_new_status_code varchar,
    p_delivery_channel_code varchar,
    p_username varchar,
    p_comment text DEFAULT NULL
)
RETURNS TABLE (
    created_status_history_id integer,
    document_number varchar,
    previous_status_code varchar,
    new_status_code varchar,
    delivery_channel_code varchar
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_document_id integer;
    v_document_status_id integer;
    v_delivery_channel_id integer;
    v_user_id integer;
    v_last_status_code varchar;
    v_is_archived boolean;
BEGIN
    /* =========================
       1. Находим документ
       ========================= */

    SELECT
        document_id,
        is_archived
    INTO
        v_document_id,
        v_is_archived
    FROM core.contract_documents
    WHERE core.contract_documents.document_number = p_document_number;

    IF v_document_id IS NULL THEN
        RAISE EXCEPTION 'Документ с номером % не найден', p_document_number;
    END IF;


    /* =========================
       2. Проверяем, не архивный ли документ
       ========================= */

    IF v_is_archived = true
       AND p_new_status_code <> 'ARCHIVED' THEN
        RAISE EXCEPTION 'Документ % уже находится в архиве. Изменение статуса запрещено',
            p_document_number;
    END IF;


    /* =========================
       3. Находим новый статус
       ========================= */

    SELECT document_status_id
    INTO v_document_status_id
    FROM core.document_statuses
    WHERE code = p_new_status_code;

    IF v_document_status_id IS NULL THEN
        RAISE EXCEPTION 'Статус % не найден в core.document_statuses', p_new_status_code;
    END IF;


    /* =========================
       4. Находим канал доставки
       ========================= */

    SELECT delivery_channel_id
    INTO v_delivery_channel_id
    FROM core.delivery_channels
    WHERE code = p_delivery_channel_code;

    IF v_delivery_channel_id IS NULL THEN
        RAISE EXCEPTION 'Канал доставки % не найден в core.delivery_channels', p_delivery_channel_code;
    END IF;


    /* =========================
       5. Находим пользователя
       ========================= */

    SELECT user_id
    INTO v_user_id
    FROM core.users
    WHERE username = p_username;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Пользователь % не найден', p_username;
    END IF;


    /* =========================
       6. Находим последний статус документа
       ========================= */

    SELECT ds.code
    INTO v_last_status_code
    FROM core.document_status_history dsh
    JOIN core.document_statuses ds
        ON ds.document_status_id = dsh.document_status_id
    WHERE dsh.document_id = v_document_id
    ORDER BY dsh.status_date DESC, dsh.status_history_id DESC
    LIMIT 1;


    /* =========================
       7. Защита от дублирования текущего статуса
       ========================= */

    IF v_last_status_code = p_new_status_code THEN
        RAISE EXCEPTION 'Документ % уже находится в статусе %',
            p_document_number,
            p_new_status_code;
    END IF;


    /* =========================
       8. Добавляем новый статус в историю
       ========================= */

    INSERT INTO core.document_status_history (
        document_id,
        document_status_id,
        delivery_channel_id,
        status_date,
        changed_by,
        comment
    )
    VALUES (
        v_document_id,
        v_document_status_id,
        v_delivery_channel_id,
        now(),
        v_user_id,
        p_comment
    )
    RETURNING status_history_id INTO created_status_history_id;


    /* =========================
       9. Если статус ARCHIVED — архивируем документ
       ========================= */

    IF p_new_status_code = 'ARCHIVED' THEN
        UPDATE core.contract_documents
        SET is_archived = true
        WHERE document_id = v_document_id;
    END IF;


    /* =========================
       10. Возвращаем результат
       ========================= */

    document_number := p_document_number;
    previous_status_code := COALESCE(v_last_status_code, 'NO_STATUS');
    new_status_code := p_new_status_code;
    delivery_channel_code := p_delivery_channel_code;

    RETURN NEXT;
END;
$$;