# Reporting marts — AS-IS

## Общие свойства

Mart-слой содержит три обычных PostgreSQL views. Это не materialized views и не физически загружаемые таблицы.

Следствия:

- данные вычисляются из core при каждом запросе;
- отдельного refresh job нет;
- производительность зависит от объёма core, плана запроса и индексов;
- `mart_updated_at = now()` означает время выполнения текущего запроса, а не время последней ETL-загрузки или refresh.

## `mart.contract_status`

### Business purpose

Единый operational registry договорных документов с текущим статусом и последним результатом генерации.

### Grain

Одна строка на `core.contract_documents.document_id`.

### Main sources

- `core.contract_documents`;
- `core.contracts`;
- `core.legal_entities`;
- `core.counterparties`;
- `core.document_types`;
- `core.document_status_history` и справочники статуса/канала;
- `core.document_generation_log` и `core.generation_statuses`;
- `core.users`.

### Key columns

- document: ID, number, date, type;
- parties: наше юрлицо и контрагент, ИНН/КПП/ОГРН;
- lifecycle: `is_actual`, `is_archived`;
- current status: code/name, final flag, delivery channel, last status date/user/comment;
- latest generation: status, file name/path, timestamp/user;
- derived: `is_generated`, `requires_action`, `mart_updated_at`.

### Logic summary

Latest status и latest generation выбираются через `ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY timestamp DESC, surrogate_id DESC)`.

`requires_action = true`, если текущий статус `GENERATED` или `NEEDS_CORRECTION`.

`is_generated = true`, если существует последняя строка generation log независимо от её `generation_status_code`. Поэтому при последнем `ERROR` поле также может быть `true`; для определения успеха нужно использовать `generation_status_code`.

### Consumers / use cases

- Streamlit registry;
- поиск документа и контрагента;
- выбор документа для изменения статуса;
- operational контроль текущего состояния.

### Refresh semantics

View отражает committed core-данные на момент SELECT. `mart_updated_at` — query time.

### Limitations

- нет исторического snapshot mart;
- нет SLA/age metrics;
- семантика `is_generated` означает наличие попытки, а не обязательно успех;
- при росте данных понадобятся индексы и/или materialization по результатам профилирования.

## `mart.document_generation_queue`

### Business purpose

Очередь документов, которым нужна первая генерация файла или повторная попытка после ошибки.

### Grain

Одна строка на актуальный неархивный документ, удовлетворяющий queue filter.

### Main sources

- `core.contract_documents` и `core.contracts`;
- `core.legal_entities`, `core.counterparties`, `core.document_types`;
- `core.document_generation_log` и `core.generation_statuses`;
- активные `core.document_templates`.

### Key columns

- document and party identifiers;
- template ID/name/path/version;
- last generation status/time/file/error;
- `queue_reason`;
- `has_active_template`;
- `mart_updated_at`.

### Logic summary

View включает только документы:

- `is_actual = true`;
- `is_archived = false`;
- generation log отсутствует или последний generation status равен `ERROR`.

`queue_reason`:

- `NOT_GENERATED` — попыток нет;
- `RETRY_REQUIRED` — последняя попытка завершилась `ERROR`;
- ветка `CHECK_REQUIRED` присутствует в CASE, но недостижима в AS-IS definition из-за текущего WHERE.

### Consumers / use cases

- экран очереди Streamlit;
- поиск документов для генерации;
- ручной retry после ошибки;
- контроль наличия активного шаблона.

### Refresh semantics

Очередь пересчитывается при SELECT. После записи нового generation log документ появляется или исчезает по текущей логике view.

### Limitations

- это reporting view, а не durable message/job queue;
- нет locking/claiming задачи worker-ом;
- нет retry count, next retry timestamp, priority и backoff;
- корректный grain зависит от ограничения «один активный шаблон на юрлицо и тип документа».

## `mart.counterparty_completeness`

### Business purpose

Контроль достаточности реквизитов контрагента для договорного процесса.

### Grain

Одна строка на `core.counterparties.counterparty_id`.

### Main sources

- `core.counterparties`;
- агрегат активных `core.counterparty_signatories`;
- агрегат `core.bank_accounts`;
- `core.individual_entrepreneur_details`.

### Key columns

- master data контрагента;
- количество активных подписантов и банковских счетов;
- паспортные данные для ИП;
- boolean flags `has_*`;
- `missing_required_fields`;
- `is_ready_for_contract`;
- `mart_updated_at`.

### Logic summary

До JOIN подписанты и банковские счета агрегируются по `counterparty_id`, что предотвращает fanout между двумя one-to-many источниками.

Готовность требует:

- полного имени;
- format-valid ИНН/КПП/ОГРН или ОГРНИП согласно типу;
- юридического и почтового адреса;
- хотя бы одного активного подписанта;
- хотя бы одного банковского счёта;
- паспортных данных для ИП.

Email и phone отражаются отдельными flags, но не входят в `is_ready_for_contract`.

### Consumers / use cases

- экран полноты контрагентов;
- поиск missing business attributes;
- отбор контрагентов для договорного процесса;
- оперативный DQ-контроль core.

### Refresh semantics

Показатели рассчитываются на текущих committed core-данных при SELECT.

### Limitations

- readiness logic частично повторяет staging DQ и может эволюционировать отдельно;
- это current-state view без истории изменения полноты;
- наличие банковского счёта проверяется количеством строк; повторная полная проверка всех его полей в mart не выполняется;
- email/phone не влияют на readiness;
- нет business owner, SLA и порогов качества за пределами SQL definition.

## Контроль grain и fanout

Для каждой view рекомендуется автоматизировать инвариант:

```sql
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT document_id) AS distinct_grain_count
FROM mart.contract_status;
```

Для `document_generation_queue` используется `document_id`, для `counterparty_completeness` — `counterparty_id`. Значения должны совпадать. Проверки описаны в `pmi_lite.md`, но пока не автоматизированы.

## Planned / next iteration

- формальные data contracts и owners;
- query performance baseline;
- индексы после анализа планов;
- materialized views или scheduled physical marts при подтверждённой необходимости;
- snapshot/history marts для динамики статусов и DQ;
- метрики свежести, SLA и alerting.
