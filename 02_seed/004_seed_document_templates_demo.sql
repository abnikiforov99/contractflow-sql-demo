-- 004_seed_document_templates.sql
-- ContractFlow SQL
-- Шаблоны документов из папок с word файлами


/* ==============================
   ЗАЩИТА ОТ ДУБЛЕЙ ПО ПУТИ ФАЙЛА
   ============================== */

CREATE UNIQUE INDEX IF NOT EXISTS uq_document_templates_path
ON core.document_templates (template_path)
;


/* ============================================
   ЗАЩИТА ОТ ДВУХ АКТИВНЫХ ШАБЛОНОВ ОДНОГО ТИПА
   ============================================ */

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_active_template_per_legal_entity_doc_type
ON core.document_templates (legal_entity_id, document_type_id)
WHERE is_active = TRUE
;

/* ====
   SSK
   ==== */

INSERT INTO core.document_templates (
    legal_entity_id,
    document_type_id,
    template_name,
    template_path,
    template_version,
    is_active,
    comment
)
SELECT
    le.legal_entity_id,
    dt.document_type_id,
    'ССК основной договор тест',
    '06_app/templates/SSK/SSK_test_template_1.docx',
    '2025-03-03',
    true,
    'Актуальная проформа договора ССК'
FROM core.legal_entities le
JOIN core.document_types dt ON dt.code = 'CONTRACT'
WHERE le.short_name = 'ССК'
ON CONFLICT (template_path) DO UPDATE
SET
    legal_entity_id = EXCLUDED.legal_entity_id,
    document_type_id = EXCLUDED.document_type_id,
    template_name = EXCLUDED.template_name,
    template_version = EXCLUDED.template_version,
    is_active = EXCLUDED.is_active,
    comment = EXCLUDED.comment
;

/* ===
   VD
   === */

INSERT INTO core.document_templates (
    legal_entity_id,
    document_type_id,
    template_name,
    template_path,
    template_version,
    is_active,
    comment
)
SELECT
    le.legal_entity_id,
    dt.document_type_id,
    'ВД основной договор тест',
    '06_app/templates/VD/VD_test_template_1.docx',
    '2025-03-03',
    true,
    'Актуальная проформа договора ВД'
FROM core.legal_entities le
JOIN core.document_types dt ON dt.code = 'CONTRACT'
WHERE le.short_name = 'ВД'
ON CONFLICT (template_path) DO UPDATE
SET
    legal_entity_id = EXCLUDED.legal_entity_id,
    document_type_id = EXCLUDED.document_type_id,
    template_name = EXCLUDED.template_name,
    template_version = EXCLUDED.template_version,
    is_active = EXCLUDED.is_active,
    comment = EXCLUDED.comment
;

-- ПРОВЕРКА

SELECT 
    t.template_id,
    le.short_name AS legal_entity,
    dt.code AS document_type,
    t.template_name,
    t.template_path,
    t.template_version,
    t.is_active
FROM core.document_templates t
JOIN core.legal_entities le 
    ON le.legal_entity_id = t.legal_entity_id
JOIN core.document_types dt 
    ON dt.document_type_id = t.document_type_id
ORDER BY le.short_name, dt.code, t.template_version
;