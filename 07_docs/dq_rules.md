# Data Quality rules — AS-IS

## Scope

Правила реализованы в `stg.validate_counterparty_requisites(load_batch_id)` и применяются к `stg.counterparty_requisites_raw`.

В функции присутствует 42 ветви проверок: 36 формируют `ERROR`, 6 — `WARNING`. Некоторые ветви используют одинаковый `error_code` для разных полей или типов контрагента.

Regex-проверки являются форматным контролем MVP. Они не выполняют полную юридическую проверку, вычисление контрольных разрядов или сверку с внешними реестрами.

## Severity и результат

| Severity | Processing status | Batch/import result |
|---|---|---|
| Нет срабатываний | `VALID` | Batch может быть импортирован |
| Есть только WARNING | `VALID_WITH_WARNINGS` | Batch может быть импортирован |
| Есть хотя бы один ERROR | `INVALID` | Batch получает `INVALID`; импорт запрещён |

## Обязательные поля и тип контрагента

| Rule ID / error code | Severity | Object / field | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `REQUIRED_FIELD_MISSING` | ERROR | `counterparty_type` | NULL/blank | Ошибка записана | Нельзя определить правила ЮЛ/ИП |
| `INVALID_COUNTERPARTY_TYPE` | ERROR | `counterparty_type` | Значение не `LEGAL_ENTITY` и не `INDIVIDUAL_ENTREPRENEUR` | Ошибка записана | Допускаются только реализованные типы |
| `REQUIRED_FIELD_MISSING` | ERROR | `full_name` | NULL/blank | Ошибка записана | Полное имя обязательно для core |
| `REQUIRED_FIELD_MISSING` | ERROR | `inn` | NULL/blank | Ошибка записана | ИНН является business identifier |

Known gap: `legal_form` имеет `NOT NULL` в core, но отдельного staging DQ-правила на его обязательность нет.

## ИНН, КПП, ОГРН и ОГРНИП

| Rule ID | Severity | Field / applicability | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `INVALID_INN_FORMAT` | ERROR | `inn`, ЮЛ | Не 10 цифр | Строка `INVALID` | Format-only проверка ИНН ЮЛ |
| `INVALID_INN_FORMAT` | ERROR | `inn`, ИП | Не 12 цифр | Строка `INVALID` | Format-only проверка ИНН ИП |
| `KPP_REQUIRED_FOR_LEGAL_ENTITY` | ERROR | `kpp`, ЮЛ | NULL/blank | Строка `INVALID` | КПП обязателен для ЮЛ в MVP |
| `INVALID_KPP_FORMAT` | ERROR | `kpp` | Заполнен, но не 9 цифр | Строка `INVALID` | Формат КПП |
| `KPP_NOT_ALLOWED_FOR_IE` | ERROR | `kpp`, ИП | Поле заполнено | Строка `INVALID` | Для ИП КПП не ожидается |
| `OGRN_REQUIRED` | ERROR | `ogrn`, ЮЛ | NULL/blank | Строка `INVALID` | ОГРН обязателен для ЮЛ |
| `INVALID_OGRN_FORMAT` | ERROR | `ogrn`, ЮЛ | Не 13 цифр | Строка `INVALID` | Format-only проверка ОГРН |
| `OGRNIP_NOT_ALLOWED_FOR_LEGAL_ENTITY` | ERROR | `ogrnip`, ЮЛ | Поле заполнено | Строка `INVALID` | Для ЮЛ используется ОГРН |
| `OGRNIP_REQUIRED` | ERROR | `ogrnip`, ИП | NULL/blank | Строка `INVALID` | ОГРНИП обязателен для ИП |
| `INVALID_OGRNIP_FORMAT` | ERROR | `ogrnip`, ИП | Не 15 цифр | Строка `INVALID` | Format-only проверка ОГРНИП |
| `OGRN_NOT_ALLOWED_FOR_IE` | ERROR | `ogrn`, ИП | Поле заполнено | Строка `INVALID` | Для ИП используется ОГРНИП |

## Подписанты

| Rule ID | Severity | Field | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `SIGNATORY_FIELD_MISSING` | ERROR | `position_nom` | NULL/blank | Строка `INVALID` | Должность нужна для документа |
| `SIGNATORY_FIELD_MISSING` | ERROR | `full_name_nom` | NULL/blank | Строка `INVALID` | ФИО подписанта обязательно |
| `SIGNATORY_GENITIVE_MISSING` | WARNING | `full_name_gen`, ЮЛ | NULL/blank | `VALID_WITH_WARNINGS`, если нет ERROR | Возможна неполная подстановка в шаблон |
| `SIGNATORY_FIELD_MISSING` | ERROR | `initials_lastname` | NULL/blank | Строка `INVALID` | Краткое имя используется в документе |
| `SIGNATORY_FIELD_MISSING` | ERROR | `legal_basis_gen` | NULL/blank | Строка `INVALID` | Основание полномочий обязательно |

## Паспортные данные

| Rule ID | Severity | Field / applicability | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `PASSPORT_REQUIRED_FOR_IE` | ERROR | `passport_data`, ИП | NULL/blank | Строка `INVALID` | Реквизиты ИП требуют паспортных данных |
| `PASSPORT_NOT_EXPECTED_FOR_LEGAL_ENTITY` | WARNING | `passport_data`, ЮЛ | Поле заполнено | Warning, импорт разрешён | Возможное ошибочное заполнение чужой группы полей |

## Контакты

| Rule ID | Severity | Field | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `EMAIL_MISSING` | WARNING | `email_address` | NULL/blank | Warning, импорт разрешён | Контактный email желателен |
| `INVALID_EMAIL_FORMAT` | WARNING | `email_address` | Заполнен и не соответствует MVP regex | Warning, импорт разрешён | Базовая форматная проверка email |
| `PHONE_FORMAT_WARNING` | WARNING | `phone_number` | Заполнен и не соответствует MVP regex | Warning, импорт разрешён | Телефон выглядит нестандартно |

## Первый банковский счёт

| Rule ID | Severity | Field | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `BANK_ACCOUNT_REQUIRED` | ERROR | `account_number_1` | NULL/blank | Строка `INVALID` | Требуется хотя бы один расчётный счёт |
| `INVALID_ACCOUNT_NUMBER_FORMAT` | ERROR | `account_number_1` | Не 20 цифр | Строка `INVALID` | Формат расчётного счёта |
| `CORR_ACCOUNT_REQUIRED` | ERROR | `corr_account_1` | NULL/blank | Строка `INVALID` | Корсчёт обязателен |
| `INVALID_CORR_ACCOUNT_FORMAT` | ERROR | `corr_account_1` | Не 20 цифр | Строка `INVALID` | Формат корсчёта |
| `BIK_REQUIRED` | ERROR | `bik_1` | NULL/blank | Строка `INVALID` | БИК обязателен |
| `INVALID_BIK_FORMAT` | ERROR | `bik_1` | Не 9 цифр | Строка `INVALID` | Формат БИК |
| `BANK_NAME_REQUIRED` | ERROR | `bank_name_1` | NULL/blank | Строка `INVALID` | Наименование банка обязательно |

## Второй и третий банковские счета

| Rule ID | Severity | Group / field | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `INCOMPLETE_BANK_ACCOUNT_2` | ERROR | Группа 2 | Заполнена часть из account/corr/BIK/bank name | Строка `INVALID` | Опциональная группа должна быть полной |
| `INVALID_ACCOUNT_NUMBER_2_FORMAT` | ERROR | `account_number_2` | Заполнен и не 20 цифр | Строка `INVALID` | Формат второго счёта |
| `INVALID_CORR_ACCOUNT_2_FORMAT` | ERROR | `corr_account_2` | Заполнен и не 20 цифр | Строка `INVALID` | Формат второго корсчёта |
| `INVALID_BIK_2_FORMAT` | ERROR | `bik_2` | Заполнен и не 9 цифр | Строка `INVALID` | Формат второго БИК |
| `INCOMPLETE_BANK_ACCOUNT_3` | ERROR | Группа 3 | Заполнена часть из account/corr/BIK/bank name | Строка `INVALID` | Опциональная группа должна быть полной |
| `INVALID_ACCOUNT_NUMBER_3_FORMAT` | ERROR | `account_number_3` | Заполнен и не 20 цифр | Строка `INVALID` | Формат третьего счёта |
| `INVALID_CORR_ACCOUNT_3_FORMAT` | ERROR | `corr_account_3` | Заполнен и не 20 цифр | Строка `INVALID` | Формат третьего корсчёта |
| `INVALID_BIK_3_FORMAT` | ERROR | `bik_3` | Заполнен и не 9 цифр | Строка `INVALID` | Формат третьего БИК |

## Дубли

| Rule ID | Severity | Scope | Condition | Expected result | Business meaning |
|---|---|---|---|---|---|
| `COUNTERPARTY_ALREADY_EXISTS` | WARNING | Staging vs core | ИНН уже есть в `core.counterparties` | Warning записан | Пользователь должен проверить актуальность |
| `DUPLICATE_INN_IN_BATCH` | ERROR | Внутри batch | Один непустой ИНН встречается более одного раза | Все строки с ИНН становятся `INVALID` | Запрет неоднозначного импорта |

Несмотря на warning для существующего ИНН, функция импорта в текущем MVP отдельно запрещает batch, содержащий уже существующего контрагента. Update/upsert-сценарий не реализован.

## Import blockers

Следующие контроли реализованы как исключения в `stg.import_counterparty_requisites`, а не как строки `validation_errors`:

| Control ID | Condition | Result |
|---|---|---|
| `IMP-BATCH-NOT-FOUND` | Batch отсутствует | Exception; импорт остановлен |
| `IMP-ALREADY-IMPORTED` | `load_status = IMPORTED` | Exception; повторный импорт запрещён |
| `IMP-NOT-VALIDATED` | Batch не имеет `VALIDATED` | Exception; требуется validation |
| `IMP-HAS-ERROR` | В `validation_errors` есть `ERROR` | Exception; импорт запрещён |
| `IMP-EXISTS-IN-CORE` | ИНН raw-строки уже есть в core | Exception; нужен отдельный update-сценарий |
| `IMP-NO-VALID-ROWS` | Нет `VALID`/`VALID_WITH_WARNINGS` | Exception; нечего импортировать |

## Defense in depth в core

Core дополнительно применяет `NOT NULL`, `UNIQUE`, FK и CHECK. Эти ограничения защищают физическую целостность, но не заменяют staging DQ и не создают удобных пользовательских сообщений.

## Planned / next iteration

- формальная проверка обязательности `legal_form` до импорта;
- контрольные алгоритмы ИНН/ОГРН/ОГРНИП и банковских реквизитов;
- reference checks по доверенным источникам при наличии требований и доступа;
- централизованный каталог DQ rules и версии правил;
- DQ metrics по batch, trend monitoring и alerting;
- автоматические позитивные и негативные SQL tests.

