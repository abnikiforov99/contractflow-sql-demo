# Порядок развёртывания ContractFlow Demo

Этот файл описывает порядок запуска demo-версии проекта ContractFlow SQL.

Проект рассчитан на локальный запуск:

* PostgreSQL — база данных;
* DBeaver — запуск SQL-скриптов;
* Streamlit — пользовательский интерфейс;
* Python — генерация документов;
* Microsoft Word — конвертация DOCX в PDF через `docx2pdf`.

---

## 1. Создать demo-базу данных

В DBeaver подключитесь к PostgreSQL и создайте базу:

```sql
CREATE DATABASE contractflow_demo;
```

После создания базы подключитесь именно к `contractflow_demo`.

Перед запуском скриптов проверьте текущую базу:

```sql
SELECT current_database();
```

Ожидаемый результат:

```text
contractflow_demo
```

---

## 2. Запустить DDL-скрипты

Выполните скрипты из папки `01_ddl` строго по порядку:

```text
01_ddl/001_create_schemas_demo.sql
01_ddl/002_create_core_tables_demo.sql
01_ddl/003_create_staging_tables_demo.sql
```

Эти скрипты создают схемы и основные таблицы проекта:

```text
stg
core
audit
mart
```

---

## 3. Запустить seed-скрипты

Выполните скрипты из папки `02_seed` строго по порядку:

```text
02_seed/001_seed_dictionaries_demo.sql
02_seed/002_seed_users_demo.sql
02_seed/003_seed_legal_entities_demo.sql
02_seed/004_seed_document_templates_demo.sql
```

Эти скрипты добавляют demo-данные:

* справочники;
* пользователей;
* demo-юрлица;
* подписантов demo-юрлиц;
* пути к demo-шаблонам документов.

Контрагенты намеренно не добавляются через SQL seed: они загружаются через Streamlit из demo Excel-файла.

---

## 4. Создать staging-функции

Выполните скрипты из папки `03_staging`:

```text
03_staging/003_create_function_validate_counterparty_requisites_demo.sql
03_staging/004_create_function_import_counterparty_requisites_demo.sql
```

Эти функции отвечают за:

* валидацию загруженных реквизитов;
* запись ошибок и предупреждений;
* импорт валидных данных из `stg` в `core`.

---

## 5. Создать transform-функции

Выполните скрипты из папки `04_transform`:

```text
04_transform/004_create_function_create_contract_document_demo.sql
04_transform/005_create_function_register_document_generation_demo.sql
04_transform/006_create_function_update_document_status_demo.sql
```

Эти функции отвечают за:

* создание договорных документов;
* регистрацию генерации файла;
* обновление статусов документов.

---

## 6. Создать mart-витрины

Выполните скрипты из папки `05_mart`:

```text
05_mart/001_create_mart_contract_status_demo.sql
05_mart/002_create_mart_document_generation_queue_demo.sql
05_mart/003_create_mart_counterparty_completeness_demo.sql
```

Витрины используются интерфейсом Streamlit для отображения:

* реестра документов;
* очереди генерации;
* полноты реквизитов контрагентов.

---

## 7. Проверить базу после развёртывания

Проверьте, что таблицы созданы:

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema IN ('stg', 'core', 'audit', 'mart')
ORDER BY table_schema, table_name;
```

Проверьте, что mart-витрины созданы:

```sql
SELECT table_schema, table_name
FROM information_schema.views
WHERE table_schema = 'mart'
ORDER BY table_name;
```

Проверьте demo-пользователей и demo-юрлица:

```sql
SELECT * FROM core.users;
SELECT * FROM core.legal_entities;
SELECT * FROM core.document_templates;
```

Проверьте, что нет нескольких активных шаблонов для одной пары “юрлицо + тип документа”:

```sql
SELECT
    le.short_name,
    dt.code,
    COUNT(*) AS active_template_count
FROM core.document_templates t
JOIN core.legal_entities le
    ON le.legal_entity_id = t.legal_entity_id
JOIN core.document_types dt
    ON dt.document_type_id = t.document_type_id
WHERE t.is_active = true
GROUP BY le.short_name, dt.code
HAVING COUNT(*) > 1;
```

Ожидаемый результат: пустая выборка.

---

## 8. Настроить Streamlit

Перейдите в папку приложения:

```text
06_app
```

Создайте файл:

```text
06_app/.streamlit/secrets.toml
```

На основе примера:

```text
06_app/.streamlit/secrets.example.toml
```

Пример содержимого:

```toml
[connections.contractflow_db]
url = "postgresql+psycopg2://postgres:YOUR_PASSWORD@localhost:5432/contractflow_demo"
```

Файл `secrets.toml` содержит локальный пароль и не должен попадать в GitHub.

---

## 9. Установить Python-зависимости

Из папки `06_app` создайте виртуальное окружение:

```powershell
python -m venv .venv
```

Активируйте окружение.

Для PowerShell:

```powershell
.\.venv\Scripts\Activate.ps1
```

Для cmd:

```cmd
.venv\Scripts\activate.bat
```

Установите зависимости:

```powershell
python -m pip install -r requirements.txt
```

---

## 10. Запустить Streamlit

Из папки `06_app` выполните:

```powershell
python -m streamlit run app.py
```

После запуска откройте локальный адрес:

```text
http://localhost:8501
```

---

## 11. Проверить demo-сценарий

После запуска интерфейса пройдите сценарий из файла:

```text
07_docs/demo_scenario.md
```

Основной поток:

```text
Excel → staging → validation → import to core → create document → generate PDF → update status → registry
```
