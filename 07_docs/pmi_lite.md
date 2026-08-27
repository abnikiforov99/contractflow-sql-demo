# ПМИ-lite — ContractFlow SQL

## Статус документа

Ниже приведён набор AS-IS приёмочных и контрольных тест-кейсов. Кейсы подготовлены для ручного выполнения и последующей автоматизации. Они не считаются выполненными в рамках документационного изменения.

Общий статус всех кейсов: `Planned / manual / not automated`.

## Общие предусловия

- чистая или контролируемая PostgreSQL database `contractflow_demo`;
- SQL-скрипты выполнены в порядке из `run_order.md`;
- seed-справочники, demo users, legal entities и templates доступны;
- настроено Streamlit connection;
- для PDF установлен Microsoft Word; DOCX-проверка может выполняться без PDF-конвертации;
- тестовые данные не содержат реальные персональные или банковские реквизиты.

## TC-LOAD-001 — успешная загрузка валидного ООО

- **Area:** Source / staging / DQ.
- **Preconditions:** ИНН из `Лист1` demo-файла отсутствует в core.
- **Steps:** загрузить demo XLSX; выбрать `Лист1`; записать в staging; запустить validation.
- **Expected result:** один batch; одна raw-строка; batch `VALIDATED`; raw `VALID` либо `VALID_WITH_WARNINGS`; `invalid_rows = 0`.
- **SQL/check:** проверить `stg.load_batches`, `stg.counterparty_requisites_raw`, `stg.validation_errors` по новому `load_batch_id`.
- **Status:** Planned / manual / not automated.

## TC-LOAD-002 — успешная загрузка валидного ИП

- **Area:** Source / staging / DQ.
- **Preconditions:** ИНН из `Лист2` отсутствует в core.
- **Steps:** загрузить demo XLSX; выбрать `Лист2`; записать в staging; запустить validation.
- **Expected result:** `counterparty_type = INDIVIDUAL_ENTREPRENEUR`; ОГРНИП и passport заполнены; нет ERROR; batch `VALIDATED`.
- **SQL/check:** выборка raw и errors по batch; убедиться, что `ogrn` пуст, а `ogrnip` заполнен.
- **Status:** Planned / manual / not automated.

## TC-DQ-001 — пропуск обязательного поля

- **Area:** DQ required fields.
- **Preconditions:** копия demo source с пустым `ИНН`, `full_name` или обязательным полем подписанта.
- **Steps:** загрузить файл; запустить validation.
- **Expected result:** соответствующий `REQUIRED_FIELD_MISSING` или `SIGNATORY_FIELD_MISSING`; raw `INVALID`; batch `INVALID`.
- **SQL/check:** `SELECT field_name, severity, error_code FROM stg.validation_errors WHERE load_batch_id = :id;`.
- **Status:** Planned / manual / not automated.

## TC-DQ-002 — некорректный ИНН/КПП/ОГРН

- **Area:** DQ identifiers.
- **Preconditions:** source ЮЛ с неправильной длиной/символами в идентификаторах.
- **Steps:** загрузить; запустить validation.
- **Expected result:** `INVALID_INN_FORMAT`, `INVALID_KPP_FORMAT` и/или `INVALID_OGRN_FORMAT`; импорт недоступен.
- **SQL/check:** проверить ERROR codes и `load_status = INVALID`.
- **Status:** Planned / manual / not automated.

## TC-DQ-003 — warning-сценарий

- **Area:** DQ warnings.
- **Preconditions:** валидная запись без email либо без `full_name_gen` для ЮЛ; ERROR отсутствуют.
- **Steps:** загрузить; запустить validation.
- **Expected result:** `EMAIL_MISSING` или `SIGNATORY_GENITIVE_MISSING`; raw `VALID_WITH_WARNINGS`; batch `VALIDATED`; импорт разрешён.
- **SQL/check:** убедиться, что warning существует, а ERROR count равен нулю.
- **Status:** Planned / manual / not automated.

## TC-IMP-001 — запрет импорта batch при ERROR

- **Area:** Import blocker.
- **Preconditions:** batch из `TC-DQ-001` или `TC-DQ-002` имеет `INVALID`.
- **Steps:** вызвать `stg.import_counterparty_requisites(:id)`.
- **Expected result:** exception; core-строки для batch не созданы; batch не стал `IMPORTED`.
- **SQL/check:** проверить отсутствие `processed_counterparty_id` и отсутствие нового ИНН в core.
- **Status:** Planned / manual / not automated.

## TC-IMP-002 — успешный импорт валидных данных

- **Area:** Staging → core.
- **Preconditions:** новый batch в `VALIDATED` без ERROR.
- **Steps:** вызвать import через UI.
- **Expected result:** batch `IMPORTED`; raw `IMPORTED`; созданы counterparty, signatory, первый bank account; для ИП также IE details.
- **SQL/check:** JOIN raw по `processed_counterparty_id` с core; проверить ожидаемое количество зависимых строк.
- **Status:** Planned / manual / not automated.

## TC-DUP-001 — отсутствие дублей ИНН

- **Area:** Duplicate control.
- **Preconditions:** подготовить batch с двумя raw-записями с одинаковым непустым ИНН либо загрузить ИНН, уже существующий в core.
- **Steps:** запустить validation; затем попытаться импортировать соответствующий batch.
- **Expected result:** внутри batch — `DUPLICATE_INN_IN_BATCH` ERROR; для существующего core ИНН — warning на validation и exception на import.
- **SQL/check:** `GROUP BY inn HAVING COUNT(*) > 1` в staging/core; в core дубли отсутствуют благодаря UNIQUE.
- **Status:** Planned / manual / not automated.

## TC-RI-001 — FK и ссылочная целостность

- **Area:** Data model integrity.
- **Preconditions:** core содержит импортированные данные и документы.
- **Steps:** выполнить orphan checks для основных FK.
- **Expected result:** zero orphan rows.
- **SQL/check:** представитель проверки: `SELECT COUNT(*) FROM core.contract_documents cd LEFT JOIN core.contracts c ON c.contract_id = cd.contract_id WHERE c.contract_id IS NULL;` Ожидается `0`. Аналогично проверить status history, generation log, bank accounts и signatories.
- **Status:** Planned / manual / not automated.

## TC-MART-001 — выбор последнего статуса документа

- **Area:** `mart.contract_status`.
- **Preconditions:** документ имеет минимум два status events с различными timestamp/ID.
- **Steps:** добавить следующий статус через `core.update_document_status`; запросить mart.
- **Expected result:** mart возвращает ровно одну строку документа и последний status по `status_date DESC, status_history_id DESC`.
- **SQL/check:** сравнить mart с independent `ROW_NUMBER()`/`ORDER BY ... LIMIT 1` по history.
- **Status:** Planned / manual / not automated.

## TC-MART-002 — очередь генерации

- **Area:** `mart.document_generation_queue`.
- **Preconditions:** документ actual/non-archived; сначала без generation log, затем с `ERROR`, затем с `SUCCESS`.
- **Steps:** запросить view на каждом этапе.
- **Expected result:** без лога — `NOT_GENERATED`; после ERROR — `RETRY_REQUIRED`; после SUCCESS документ отсутствует в очереди.
- **SQL/check:** фильтр view по `document_id`, сверка с последней строкой generation log.
- **Status:** Planned / manual / not automated.

## TC-MART-003 — полнота контрагента

- **Area:** `mart.counterparty_completeness`.
- **Preconditions:** один полностью заполненный и один неполный контрагент.
- **Steps:** запросить view по обоим ID.
- **Expected result:** полный имеет `is_ready_for_contract = true` и пустой массив missing fields; неполный — `false` и ожидаемые labels.
- **SQL/check:** сверить flags с core fields, количеством active signatories/accounts и IE details.
- **Status:** Planned / manual / not automated.

## TC-MART-004 — контроль fanout после JOIN

- **Area:** Mart grain.
- **Preconditions:** контрагент имеет несколько bank accounts; документы имеют несколько status/generation events.
- **Steps:** сравнить row count и distinct grain count во всех views.
- **Expected result:** значения совпадают.
- **SQL/check:** `COUNT(*) = COUNT(DISTINCT document_id)` для двух document views; `COUNT(*) = COUNT(DISTINCT counterparty_id)` для completeness.
- **Status:** Planned / manual / not automated.

## TC-GEN-001 — generation log

- **Area:** Document generation / logging.
- **Preconditions:** существует документ с активным шаблоном и demo-пользователь.
- **Steps:** выполнить DOCX generation; отдельно смоделировать ошибку отсутствующего/недоступного template path.
- **Expected result:** успешный запуск создаёт `SUCCESS` с именем/путём; ошибка создаёт `ERROR` с `error_message`; последний результат отражается в marts.
- **SQL/check:** запросить `core.document_generation_log` по document ID в порядке `generated_at DESC, generation_id DESC`; сверить с `mart.contract_status` и queue.
- **Status:** Planned / manual / not automated.

## TC-SEED-001 — повторный deploy seed

- **Area:** Deployment / idempotency.
- **Preconditions:** SQL уже выполнен один раз.
- **Steps:** повторно запустить seed scripts в тестовой базе.
- **Expected result:** planned target — отсутствие дублей и ошибок; AS-IS может выявить риск дублей `core.legal_entities` из-за отсутствия соответствующего UNIQUE.
- **SQL/check:** `SELECT short_name, COUNT(*) FROM core.legal_entities GROUP BY short_name HAVING COUNT(*) > 1;`.
- **Status:** Planned / manual / not automated; known AS-IS risk.

## Критерий завершения будущей автоматизации

Кейс может получить статус `Automated / passed` только после появления исполняемого test script, воспроизводимой тестовой БД и сохранённого CI result. Наличие шага в demo-сценарии само по себе не считается автоматическим тестом.

