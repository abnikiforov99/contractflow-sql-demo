-- 001_seed_dictionaries.sql
-- ContractFlow SQL
-- Наполнение базовых справочников

/* =========================
   DELIVERY CHANNELS
   ========================= */

INSERT INTO core.delivery_channels (code, name)
VALUES
    ('INTERNAL', 'Внутреннее действие'),
    ('EDO', 'Электронный документооборот'),
    ('ORIGINAL', 'Бумажный оригинал'),
    ('EMAIL', 'Email'),
    ('OTHER', 'Прочее')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name;


/* =========================
   DOCUMENT STATUSES
   ========================= */

INSERT INTO core.document_statuses (code, name, is_final)
VALUES
    ('GENERATED', 'Сформирован', false),
    ('SENT', 'Отправлен', false),
    ('DELIVERED', 'Доставлен', false),
    ('SIGNED', 'Подписан', true),
    ('REJECTED', 'Отклонён', false),
    ('NEEDS_CORRECTION', 'Требует правок', false),
    ('ARCHIVED', 'Архив', true)
ON CONFLICT (code) DO UPDATE
SET 
    name = EXCLUDED.name,
    is_final = EXCLUDED.is_final;


/* =========================
   DOCUMENT TYPES
   ========================= */

INSERT INTO core.document_types (code, name)
VALUES
    ('CONTRACT', 'Договор'),
    ('NEW_EDITION', 'Новая редакция договора'),
    ('ADDITIONAL_AGREEMENT', 'Дополнительное соглашение'),
    ('PROTOCOL_OF_DISAGREEMENT', 'Протокол разногласий'),
    ('PERSONAL_ADDITIONAL_AGREEMENT', 'Персональное дополнительное соглашение')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name;


/* =========================
   USER ROLES
   ========================= */

INSERT INTO core.user_roles (code, name)
VALUES
    ('ADMIN', 'Администратор'),
    ('OPERATOR', 'Оператор'),
    ('MANAGER', 'Менеджер'),
    ('READONLY', 'Только просмотр'),
    ('SERVICE', 'Сервисный пользователь')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name;


/* =========================
   GENERATION STATUSES
   ========================= */

INSERT INTO core.generation_statuses (code, name)
VALUES
    ('SUCCESS', 'Успешно'),
    ('ERROR', 'Ошибка'),
    ('SKIPPED', 'Пропущено')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name;

--ПРОВЕРКА

SELECT 'delivery_channels' AS table_name, count(*) FROM core.delivery_channels
UNION ALL
SELECT 'document_statuses', count(*) FROM core.document_statuses
UNION ALL
SELECT 'document_types', count(*) FROM core.document_types
UNION ALL
SELECT 'user_roles', count(*) FROM core.user_roles
UNION ALL
SELECT 'generation_statuses', count(*) FROM core.generation_statuses;