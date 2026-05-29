-- 001_create_schemas.sql
-- ContractFlow SQL
-- Создание рабочих схем проекта

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS stg;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS mart;

-- Запрещаем случайное создание объектов в стандартной схеме public
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

--Проверка
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('core', 'stg', 'audit', 'mart', 'public')
ORDER BY schema_name
;