-- 002_seed_users.sql
-- ContractFlow SQL
-- Тестовые пользователи системы

INSERT INTO core.users (
    username,
    full_name,
    role_id,
    email,
    is_active
)
SELECT
    'dwhadm',
    'DWH Administrator',
    role_id,
    'dwhadministrator@mail.ru',
    true
FROM core.user_roles
WHERE code = 'ADMIN'
ON CONFLICT (username) DO UPDATE
SET
    full_name = EXCLUDED.full_name,
    role_id = EXCLUDED.role_id,
    email = EXCLUDED.email,
    is_active = EXCLUDED.is_active;

INSERT INTO core.users (
    username,
    full_name,
    role_id,
    email,
    is_active
)
SELECT
    'dwhman',
    'DWH Manager',
    role_id,
    'dwhmanager@mail.ru',
    true
FROM core.user_roles
WHERE code = 'MANAGER'
ON CONFLICT (username) DO UPDATE
SET
    full_name = EXCLUDED.full_name,
    role_id = EXCLUDED.role_id,
    email = EXCLUDED.email,
    is_active = EXCLUDED.is_active;

--ПРОВЕРКА 

SELECT 
    u.user_id,
    u.username,
    u.full_name,
    r.code AS role_code,
    r.name AS role_name,
    u.email,
    u.is_active
FROM core.users u
JOIN core.user_roles r ON r.role_id = u.role_id;