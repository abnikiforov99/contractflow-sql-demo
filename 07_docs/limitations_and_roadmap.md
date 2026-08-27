# Implemented, known limitations and roadmap

## Принцип документа

Документ разделяет фактически работающую AS-IS реализацию и возможные следующие итерации. Planned-пункты не являются текущими возможностями или обязательством по срокам.

## Implemented

### ETL / Data Quality

- чтение вертикального Excel source через Streamlit/Pandas;
- нормализация source labels и преобразование одного листа в одну business record;
- batch metadata в `stg.load_batches`;
- raw-like staging record;
- PL/pgSQL-валидация с `ERROR` и `WARNING`;
- сохранение всех срабатываний в `stg.validation_errors`;
- блокировка импорта при ERROR;
- импорт новых валидных контрагентов в normalized core;
- связь raw-строки с созданным counterparty ID.

### Operational core

- нормализованные контрагенты, подписанты и банковские счета;
- отдельные реквизиты ИП;
- наши юридические лица и подписанты;
- договорная связь и иерархия документов;
- справочники типов, статусов, каналов и generation statuses;
- статусные события добавляются через прикладную функцию, а текущий статус не хранится в отдельном перезаписываемом поле; запрет `UPDATE`/`DELETE` истории на уровне БД в AS-IS не реализован;
- generation log.

### Reporting / UI

- три reporting views;
- current document registry;
- generation queue;
- counterparty completeness;
- Streamlit screens для основного demo-flow;
- DOCX generation и PDF conversion через Microsoft Word;
- demo data, templates, ERD, screenshots и run instructions.

## Known limitations

### Orchestration and operations

- нет ETL-оркестатора;
- нет production scheduler, watermark/high-water mark и инкрементальной стратегии;
- нет автоматического retry/backoff и checkpoint/restart;
- запуск загрузки, validation, import и generation выполняется вручную через Streamlit;
- нет SLA monitoring, alerting и operational dashboard;
- `FAILED` разрешён для batch, но стандартизированный flow его установки не реализован.

### Testing and delivery

- нет автоматических SQL/Python-тестов;
- ПМИ-lite пока имеет статус manual/planned;
- нет Docker/Docker Compose;
- нет CI/CD;
- зависимости Python не закреплены версиями;
- нет migration tool; `CREATE ... IF NOT EXISTS` не обновляет существующую схему;
- SQL deploy не обёрнут в единый versioned migration process.

### Data Quality

- ИНН, ОГРН, ОГРНИП, БИК и счета проверяются по формату/длине, без полной юридической проверки и контрольных алгоритмов;
- нет внешней сверки с государственными или банковскими реестрами;
- `legal_form` обязателен в core, но отдельное staging DQ-правило отсутствует;
- readiness rules в mart и ingestion DQ находятся в разных SQL-объектах и могут расходиться;
- нет versioned DQ catalog, метрик качества и trend monitoring.

### Data model and performance

- mart — обычные views, не materialized tables;
- `mart_updated_at = now()` означает query time, а не refresh timestamp;
- audit table — заготовка без triggers и активного audit trail;
- нет SCD/истории изменений атрибутов контрагента;
- импорт поддерживает только новых контрагентов; update/upsert по ИНН отсутствует;
- ОГРН и ОГРНИП хранятся в одном core-поле `ogrn`;
- отдельной immutable raw/landing zone нет;
- нет индексов для большинства FK и частых фильтров;
- timestamps определены без timezone;
- FK не задают явную delete policy;
- numbering через `COUNT(*) + 1` имеет concurrency risk.

### Seed and consistency risks

- `core.legal_entities` не имеет UNIQUE по `short_name`/`full_name`; повторный seed может создать дубли;
- seed подписантов использует жёсткие `legal_entity_id = 1/2`;
- SQL-функция `core.register_document_generation` и Python generation logging являются параллельными реализациями;
- текущий ERD не показывает mart и неверно подписывает схему `audit_log`;
- README до текущего документационного обновления содержал устаревший путь `templates/demo`.

### Security and runtime

- пользователь выбирается без password verification;
- роли хранятся, но не обеспечивают ограничения действий;
- secrets управляются локальным Streamlit-файлом;
- PDF conversion зависит от Windows/Microsoft Word;
- проект ориентирован на локальный runtime, а не серверное deployment environment.

## Planned improvements

### Priority 1 — correctness and reproducibility

- добавить automated SQL tests для DDL, DQ, import, constraints и marts;
- добавить Python tests для parser и document generator;
- исправить seed/idempotency и убрать hardcoded FK IDs;
- формализовать migration tool и versioned migrations;
- добавить Docker Compose для PostgreSQL и приложения;
- закрепить dependency versions;
- настроить CI для static checks, deploy и tests.

### Priority 2 — ETL resilience and lineage

- определить инкрементальную загрузку и business key strategy;
- добавить watermark при появлении потокового/регулярного источника;
- определить restart/retry policy и error states;
- сохранять source checksum и/или immutable source metadata;
- усилить lineage от source/batch к core;
- реализовать orchestrated execution только при появлении schedule requirements.

### Priority 3 — DQ and audit

- добавить полные контрольные алгоритмы там, где они требуются бизнесом;
- создать versioned DQ rule catalog;
- добавить DQ monitoring, trends и alert thresholds;
- активировать audit trail с контролируемыми triggers/functions;
- определить retention и доступ к audit data.

### Priority 4 — model and reporting evolution

- добавить SCD/историзацию изменяемых атрибутов там, где нужна point-in-time аналитика;
- определить update/upsert-сценарий контрагента;
- добавить индексы по результатам `EXPLAIN ANALYZE` и workload profiling;
- рассмотреть `timestamptz` и единую timezone policy;
- рассмотреть materialized marts или scheduled refresh при подтверждённой нагрузке;
- добавить исторические/snapshot marts для динамики статусов и DQ.

### Priority 5 — security hardening

- password/SSO authentication;
- enforced role-based access control;
- least-privilege PostgreSQL roles;
- server-side secrets management;
- журналирование пользовательских действий.

## Не следует заявлять до реализации

- production-ready или production deployment;
- автоматический ETL pipeline;
- полноценный audit trail;
- юридически достоверную проверку реквизитов;
- гарантированную exactly-once обработку;
- real-time marts;
- SCD, incremental load, Docker, CI/CD или RBAC enforcement.
