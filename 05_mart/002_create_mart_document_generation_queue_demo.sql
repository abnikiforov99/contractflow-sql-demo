-- 002_create_mart_document_generation_queue.sql
-- ContractFlow SQL
-- Витрина очереди документов на генерацию

CREATE OR REPLACE VIEW mart.document_generation_queue AS

WITH latest_generation AS (
    SELECT
        gl.generation_id,
        gl.document_id,
        gs.code AS generation_status_code,
        gs.name AS generation_status_name,
        gl.generated_file_name,
        gl.generated_file_path,
        gl.generated_at,
        gl.error_message,
        ROW_NUMBER() OVER (
            PARTITION BY gl.document_id
            ORDER BY gl.generated_at DESC, gl.generation_id DESC
        ) AS rn
    FROM core.document_generation_log gl
    JOIN core.generation_statuses gs
        ON gs.generation_status_id = gl.generation_status_id
),

active_templates AS (
    SELECT
        t.template_id,
        t.legal_entity_id,
        t.document_type_id,
        t.template_name,
        t.template_path,
        t.template_version
    FROM core.document_templates t
    WHERE t.is_active = true
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

    at.template_id,
    at.template_name,
    at.template_path,
    at.template_version,

    lg.generation_status_code AS last_generation_status_code,
    lg.generation_status_name AS last_generation_status_name,
    lg.generated_at AS last_generated_at,
    lg.generated_file_name AS last_generated_file_name,
    lg.generated_file_path AS last_generated_file_path,
    lg.error_message AS last_generation_error,

    CASE
        WHEN lg.generation_id IS NULL THEN 'NOT_GENERATED'
        WHEN lg.generation_status_code = 'ERROR' THEN 'RETRY_REQUIRED'
        ELSE 'CHECK_REQUIRED'
    END AS queue_reason,

    CASE
        WHEN at.template_id IS NULL THEN false
        ELSE true
    END AS has_active_template,

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
LEFT JOIN latest_generation lg
    ON lg.document_id = cd.document_id
   AND lg.rn = 1
LEFT JOIN active_templates at
    ON at.legal_entity_id = le.legal_entity_id
   AND at.document_type_id = cd.document_type_id
WHERE cd.is_actual = true
  AND cd.is_archived = false
  AND (
      lg.generation_id IS NULL
      OR lg.generation_status_code = 'ERROR'
  );


--ПРОВЕРКИ

SELECT *
FROM mart.document_generation_queue
ORDER BY document_id;

SELECT
    document_id,
    document_number,
    document_type_code,
    legal_entity_short_name,
    counterparty_short_name,
    template_name,
    has_active_template,
    last_generation_status_code,
    queue_reason
FROM mart.document_generation_queue
ORDER BY document_id;