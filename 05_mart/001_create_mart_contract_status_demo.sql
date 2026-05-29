-- 001_create_mart_contract_status.sql
-- ContractFlow SQL
-- Витрина текущего статуса договорных документов

CREATE OR REPLACE VIEW mart.contract_status AS

WITH latest_status AS (
    SELECT
        dsh.status_history_id,
        dsh.document_id,
        ds.code AS current_status_code,
        ds.name AS current_status_name,
        ds.is_final,
        dc.code AS delivery_channel_code,
        dc.name AS delivery_channel_name,
        dsh.status_date AS last_status_date,
        u.username AS status_changed_by,
        dsh.comment AS status_comment,
        ROW_NUMBER() OVER (
            PARTITION BY dsh.document_id
            ORDER BY dsh.status_date DESC, dsh.status_history_id DESC
        ) AS rn
    FROM core.document_status_history dsh
    JOIN core.document_statuses ds
        ON ds.document_status_id = dsh.document_status_id
    JOIN core.delivery_channels dc
        ON dc.delivery_channel_id = dsh.delivery_channel_id
    LEFT JOIN core.users u
        ON u.user_id = dsh.changed_by
),

latest_generation AS (
    SELECT
        gl.generation_id,
        gl.document_id,
        gs.code AS generation_status_code,
        gs.name AS generation_status_name,
        gl.generated_file_name,
        gl.generated_file_path,
        gl.generated_at,
        u.username AS generated_by,
        ROW_NUMBER() OVER (
            PARTITION BY gl.document_id
            ORDER BY gl.generated_at DESC, gl.generation_id DESC
        ) AS rn
    FROM core.document_generation_log gl
    JOIN core.generation_statuses gs
        ON gs.generation_status_id = gl.generation_status_id
    LEFT JOIN core.users u
        ON u.user_id = gl.generated_by
)

SELECT
    cd.document_id,
    cd.document_number,
    cd.document_date,

    dt.code AS document_type_code,
    dt.name AS document_type_name,

    le.legal_entity_id,
    le.short_name AS legal_entity_short_name,
    le.full_name AS legal_entity_full_name,

    cp.counterparty_id,
    cp.counterparty_type,
    cp.full_name AS counterparty_full_name,
    cp.short_name AS counterparty_short_name,
    cp.inn,
    cp.kpp,
    cp.ogrn,

    cd.is_actual,
    cd.is_archived,

    ls.current_status_code,
    ls.current_status_name,
    ls.is_final AS is_final_status,
    ls.delivery_channel_code,
    ls.delivery_channel_name,
    ls.last_status_date,
    ls.status_changed_by,
    ls.status_comment,

    lg.generation_status_code,
    lg.generation_status_name,
    lg.generated_file_name,
    lg.generated_file_path,
    lg.generated_at,
    lg.generated_by,

    CASE
        WHEN lg.generation_id IS NOT NULL THEN true
        ELSE false
    END AS is_generated,

    CASE
        WHEN ls.current_status_code IN ('GENERATED', 'NEEDS_CORRECTION') THEN true
        ELSE false
    END AS requires_action,

    now() AS mart_updated_at

FROM core.contract_documents cd
JOIN core.contracts c
    ON c.contract_id = cd.contract_id
JOIN core.legal_entities le
    ON le.legal_entity_id = c.legal_entity_id
JOIN core.counterparties cp
    ON cp.counterparty_id = c.counterparty_id
JOIN core.document_types dt
    ON dt.document_type_id = cd.document_type_id
LEFT JOIN latest_status ls
    ON ls.document_id = cd.document_id
   AND ls.rn = 1
LEFT JOIN latest_generation lg
    ON lg.document_id = cd.document_id
   AND lg.rn = 1;


--ПРОВЕРКИ

SELECT *
FROM mart.contract_status
ORDER BY document_id;

SELECT
    document_id,
    document_number,
    document_type_code,
    legal_entity_short_name,
    counterparty_short_name,
    current_status_code,
    delivery_channel_code,
    generated_file_name,
    is_generated,
    requires_action
FROM mart.contract_status
ORDER BY document_id;