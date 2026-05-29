-- 003_seed_legal_entities.sql
-- ContractFlow SQL
-- Варируемые реквизиты наших юрлиц

INSERT INTO core.legal_entities (full_name, short_name)
VALUES
    ('Северная Сервисная Компания', 'ССК'),
    ('Вектор Документооборот', 'ВД')
ON CONFLICT DO NOTHING;

INSERT INTO core.legal_entity_signatories (
    legal_entity_id,
    position_nom,
    position_gen,
    full_name_nom,
    full_name_gen,
    initials_lastname,
    legal_basis_gen,
    is_active
)
VALUES
    (1, 'Генеральный директор', 'Генерального директора', 'Иванов Иван Иванович', 'Иванова Ивана Ивановича', 'И.И. Иванов', 'Устава', true),
    (2, 'Генеральный директор', 'Генерального директора', 'Петров Пётр Петрович', 'Петрова Петра Петровича', 'П.П. Петров', 'Устава', true)
ON CONFLICT DO NOTHING
;

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_active_signatory_per_legal_entity
ON core.legal_entity_signatories (legal_entity_id)
WHERE is_active = TRUE
;

--ПРОВЕРКА

SELECT 
    les.signatory_id,
    le.short_name AS legal_entity,
    les.position_nom,
    les.full_name_nom,
    les.initials_lastname,
    les.legal_basis_gen,
    les.is_active
FROM core.legal_entity_signatories les
JOIN core.legal_entities le 
    ON le.legal_entity_id = les.legal_entity_id
ORDER BY le.legal_entity_id, les.is_active DESC, les.signatory_id
;
