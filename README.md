# ContractFlow SQL

Инициативный ETL/Data Quality-прототип на PostgreSQL, созданный на основе реального договорного бизнес-процесса.

Проект показывает, как организовать загрузку реквизитов контрагентов из Excel, проверку качества данных, импорт в нормализованную operational-модель, создание договорных документов и reporting views для пользовательского интерфейса.

```text
Excel/source files
  → stg/raw-like layer
  → PL/pgSQL validation
  → normalized operational core
  → reporting marts
  → Streamlit UI / document generation / registry
```

## Project positioning

ContractFlow SQL — локальный MVP с production-like комплектом AS-IS документации, описывающей текущую реализацию договорного ETL/DQ-процесса, архитектуру, модель данных, проверки качества и reporting views.

Технический охват проекта:

- ETL и SQL development;
- PostgreSQL / PL/pgSQL;
- Data Quality;
- source-to-target mapping и data lineage;
- нормализация operational-модели;
- reporting marts;
- интеграция SQL backend с Python/Streamlit.

Проект не заявляется как production-система. В документации отдельно зафиксированы AS-IS реализация, known limitations и planned improvements.

По типу модели это ETL/DQ-прототип с нормализованным operational core и reporting views, а не классический dimensional DWH со star schema, фактами, измерениями и SCD.

## Business problem

Исходный договорный процесс включал ручное копирование реквизитов из Excel в Word, визуальную проверку данных и ручное ведение статусов документов.

MVP решает следующие задачи:

- принимает реквизиты контрагента в привычном Excel-формате;
- снижает риск пропуска обязательных полей и форматных ошибок;
- разделяет критические ошибки и предупреждения;
- хранит контрагентов и документы в нормализованной PostgreSQL-модели;
- фиксирует историю статусов и попытки генерации;
- создаёт DOCX/PDF для документов, по которым настроен активный шаблон; в AS-IS включены два demo-шаблона типа `CONTRACT`;
- предоставляет реестр и operational views через Streamlit.

## Architecture overview

```mermaid
flowchart LR
    A[Excel source] --> B[Streamlit / Python parser]
    B --> C[stg.load_batches]
    B --> D[stg.counterparty_requisites_raw]
    C --> E[PL/pgSQL DQ]
    D --> E
    E --> F[stg.validation_errors]
    E --> G{ERROR?}
    G -- Yes --> H[Import blocked]
    G -- No --> I[Import to normalized core]
    I --> J[Reporting mart views]
    J --> K[Streamlit registry]
    I --> L[Document generation]
    L --> M[Generation log]
    M --> J
```

### Layers

| Layer | AS-IS role |
|---|---|
| Excel/source | Вертикальный шаблон реквизитов; один выбранный лист соответствует одному контрагенту |
| `stg` | Batch metadata, raw-like запись, validation results и processing statuses |
| PL/pgSQL validation | Форматные и бизнес-проверки MVP, разделение `ERROR`/`WARNING` |
| `core` | Нормализованная operational core-модель договорного процесса |
| `mart` | Обычные reporting views для Streamlit и аналитического чтения |
| `audit` | Таблица-заготовка; активный audit trail пока не реализован |
| Streamlit | Ручной запуск и пользовательские сценарии MVP |

Подробное описание: [Architecture AS-IS](07_docs/architecture.md).

## Technology stack

- PostgreSQL;
- SQL / PL/pgSQL;
- Python;
- Streamlit;
- SQLAlchemy / psycopg2;
- Pandas / OpenPyXL;
- docxtpl;
- docx2pdf;
- Microsoft Word для локальной PDF-конвертации;
- DBeaver как один из вариантов ручного запуска SQL.

## Implemented features

### ETL / staging

- чтение вертикального Excel-шаблона;
- поддержка demo-листов для юридического лица и ИП;
- нормализация business labels и строковых идентификаторов;
- batch registration;
- raw-like staging record;
- хранение processing status и связи с созданным counterparty ID;
- повторный запуск validation с пересчётом ошибок.

### Operational core

- справочники ролей, каналов, типов/статусов документов и generation statuses;
- пользователи и наши юридические лица;
- контрагенты, подписанты и банковские счета;
- отдельные паспортные данные ИП;
- договорные связи и документы;
- parent-child документы;
- история статусов;
- шаблоны и generation log.

### Streamlit UI

- проверка подключения;
- выбор demo-пользователя;
- загрузка и preview Excel;
- validation и import;
- просмотр полноты контрагентов;
- создание документа;
- очередь генерации;
- генерация DOCX/PDF;
- изменение статуса;
- реестр и поиск.

### Document generation

- DOCX rendering через `docxtpl`;
- PDF conversion через `docx2pdf` и Microsoft Word;
- регистрация `SUCCESS`/`ERROR`;
- сохранение файлов по структуре:

```text
06_app/generated_documents/<юрлицо>/<тип документа>/<имя файла>
```

В репозитории реализованы два активных demo-шаблона типа `CONTRACT`:

```text
06_app/templates/SSK/SSK_test_template_1.docx
06_app/templates/VD/VD_test_template_1.docx
```

Другие типы документов присутствуют в справочнике и правилах нумерации, но активные templates для их физической генерации в AS-IS не добавлены.

## Data Quality

`stg.validate_counterparty_requisites` содержит 42 ветви DQ-проверок: 36 `ERROR` и 6 `WARNING`.

Проверяются:

- обязательные поля;
- допустимый тип контрагента;
- формат ИНН, КПП, ОГРН и ОГРНИП;
- различия юридического лица и ИП;
- данные подписанта;
- паспортные данные ИП;
- email и телефон;
- обязательность и полнота банковских реквизитов;
- дубли ИНН внутри batch;
- наличие контрагента с тем же ИНН в core.

```text
ERROR   → raw INVALID → batch INVALID → import blocked
WARNING → raw VALID_WITH_WARNINGS → import allowed, если нет ERROR
```

Проверки идентификаторов и счетов являются форматными проверками MVP. Они не включают полные контрольные алгоритмы и внешнюю юридическую сверку.

Полный каталог: [Data Quality rules](07_docs/dq_rules.md).

## ETL flow

1. Пользователь выбирает Excel и лист.
2. Python parser преобразует labels в структурированный словарь.
3. Создаются `stg.load_batches` и `stg.counterparty_requisites_raw`.
4. Пользователь запускает PL/pgSQL validation.
5. Срабатывания записываются в `stg.validation_errors`.
6. Строка получает `VALID`, `VALID_WITH_WARNINGS` или `INVALID`.
7. Любой `ERROR` блокирует import.
8. Валидные новые контрагенты импортируются в normalized core.
9. Reporting views читают committed core-данные.
10. Пользователь работает с процессом через Streamlit.
11. Документ создаётся и генерируется по активному DOCX-template.
12. Результат фиксируется в generation log и отражается в marts.

В AS-IS нет production orchestrator, scheduler, watermark, automatic retry и CI/CD.

Подробное описание: [ETL flow](07_docs/etl_flow.md).

## Data model

В проекте четыре PostgreSQL-схемы:

- `stg` — загрузка и валидация source data;
- `core` — normalized operational model;
- `mart` — reporting views;
- `audit` — заготовка под будущий audit trail.

Core является 3NF-like operational-моделью: банковские счета, подписанты, справочники, документы и события разделены по сущностям и связаны PK/FK.

ERD: [contractflow_sql_ERD.pdf](07_docs/contractflow_sql_ERD.pdf).

В текущей ERD mart views не отображены, а `audit_log` визуально подписан как `core.audit_log`; фактический DDL создаёт `audit.audit_log`. Это зафиксированный documentation gap, а не новая функциональность.

Подробнее:

- [Data model](07_docs/data_model.md);
- [Source-to-Target mapping](07_docs/s2t_mapping.md).

## Reporting marts

### `mart.contract_status`

Grain: один договорный документ. Показывает текущий статус, канал, последнюю попытку генерации, файл и action flags.

### `mart.document_generation_queue`

Grain: один actual/non-archived документ, которому нужна первая генерация или retry после последнего `ERROR`.

### `mart.counterparty_completeness`

Grain: один контрагент. Показывает наличие и формат ключевых реквизитов, количество подписантов/счетов, missing fields и readiness.

Все marts являются обычными views. Отдельного refresh job нет, а `mart_updated_at = now()` означает время запроса.

Подробнее: [Reporting marts](07_docs/marts.md).

## Repository structure

```text
GitHUBdemo/
├── 01_ddl/
├── 02_seed/
├── 03_staging/
├── 04_transform/
├── 05_mart/
├── 06_app/
│   ├── .streamlit/secrets.example.toml
│   ├── app.py
│   ├── document_generator.py
│   ├── requirements.txt
│   ├── templates/SSK/
│   ├── templates/VD/
│   ├── generated_documents/
│   └── temp/
├── 07_docs/
│   ├── architecture.md
│   ├── data_model.md
│   ├── s2t_mapping.md
│   ├── dq_rules.md
│   ├── etl_flow.md
│   ├── marts.md
│   ├── pmi_lite.md
│   ├── limitations_and_roadmap.md
│   ├── run_order.md
│   ├── demo_scenario.md
│   ├── contractflow_sql_ERD.pdf
│   └── screenshots/
├── demo_files/
│   └── demo_counterparty_requisites.xlsx
├── README.md
└── .gitignore
```

## Documentation map

| Document | Purpose |
|---|---|
| [architecture.md](07_docs/architecture.md) | AS-IS layers, flow, boundaries and component roles |
| [data_model.md](07_docs/data_model.md) | Schemas, tables, relationships and model type |
| [s2t_mapping.md](07_docs/s2t_mapping.md) | Excel → Python → staging → core → mart lineage |
| [dq_rules.md](07_docs/dq_rules.md) | Actual DQ rules, severity and import blockers |
| [etl_flow.md](07_docs/etl_flow.md) | End-to-end execution, states and retry limitations |
| [marts.md](07_docs/marts.md) | Grain, sources, logic and limitations of each view |
| [pmi_lite.md](07_docs/pmi_lite.md) | Manual/planned acceptance and data tests |
| [limitations_and_roadmap.md](07_docs/limitations_and_roadmap.md) | Implemented vs limitations vs planned |
| [run_order.md](07_docs/run_order.md) | Manual local deployment order |
| [demo_scenario.md](07_docs/demo_scenario.md) | User-facing demo walkthrough |

## Quick start

### Prerequisites

- PostgreSQL;
- Python with `venv`/`pip`;
- Microsoft Word, только если требуется PDF через `docx2pdf`;
- DBeaver или другой PostgreSQL client для ручного запуска SQL.

### 1. Create database

```sql
CREATE DATABASE contractflow_demo;
```

Подключитесь именно к созданной базе и проверьте:

```sql
SELECT current_database();
```

### 2. Run SQL scripts

Выполните каталоги строго по порядку:

```text
01_ddl
02_seed
03_staging
04_transform
05_mart
```

Точный список и post-deploy checks: [run_order.md](07_docs/run_order.md).

### 3. Configure Streamlit connection

Создайте локальный файл:

```text
06_app/.streamlit/secrets.toml
```

На основе versioned-примера:

```text
06_app/.streamlit/secrets.example.toml
```

```toml
[connections.contractflow_db]
url = "postgresql+psycopg2://postgres:YOUR_PASSWORD@localhost:5432/contractflow_demo"
```

`secrets.toml` исключён из Git.

### 4. Install dependencies

```powershell
cd 06_app
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

### 5. Start Streamlit

```powershell
python -m streamlit run app.py
```

Откройте `http://localhost:8501`.

## Demo scenario

```text
upload Excel
  → validate
  → import to core
  → check completeness
  → create contract document
  → generate DOCX/PDF
  → update status
  → check registry
```

Пошаговая инструкция: [demo_scenario.md](07_docs/demo_scenario.md).

Demo source: `demo_files/demo_counterparty_requisites.xlsx`.

## Screenshots

### Connection and ingestion

![Проверка подключения](07_docs/screenshots/scrn1_connection.png)

![Загрузка реквизитов](07_docs/screenshots/scrn2_import_req.png)

![Валидация и импорт](07_docs/screenshots/scrn3_validation_import_to_core.png)

### Data Quality and document process

![Полнота реквизитов](07_docs/screenshots/scrn4_reqfull.png)

![Создание документа](07_docs/screenshots/scrn5_create_doc.png)

![Очередь генерации](07_docs/screenshots/scrn6_generation_queue.png)

![Генерация документов](07_docs/screenshots/scrn7_doc_generation.png)

### Registry and statuses

![Реестр документов](07_docs/screenshots/scrn8_registry.png)

![Обновление статуса](07_docs/screenshots/scrn9_statuses.png)

![Итоговый реестр](07_docs/screenshots/scrn10_registry_final.png)

## Known limitations

- нет production orchestrator, scheduler, watermark и automatic retry;
- нет автоматических tests, Docker Compose и CI/CD;
- SQL разворачивается вручную, без migration tool;
- mart представлены ordinary views;
- `audit.audit_log` не заполняется автоматически;
- нет полной юридической проверки ИНН/ОГРН/счетов;
- импорт поддерживает только новых контрагентов;
- есть seed/idempotency risks;
- нет индексов для большинства FK/частых фильтров;
- timestamps без timezone;
- document numbering имеет concurrency risk;
- пользователь выбирается без password verification и enforced RBAC;
- PDF conversion зависит от Microsoft Word;
- текущий runtime рассчитан на локальный запуск.

Полный список: [Known limitations and roadmap](07_docs/limitations_and_roadmap.md).

## Next steps

Planned improvements, а не текущие возможности:

1. автоматические SQL/Python tests;
2. исправление seed/idempotency и подтверждённых DQ gaps;
3. Docker Compose и pinned dependencies;
4. CI и migration tool;
5. инкрементальная загрузка и restart/retry design;
6. active audit trail и DQ monitoring;
7. indexes на основе workload profiling;
8. SCD/историзация там, где нужна point-in-time аналитика;
9. materialized marts или scheduled refresh при подтверждённой нагрузке;
10. authentication/RBAC hardening.

До реализации эти пункты должны описываться только как `Planned`.
