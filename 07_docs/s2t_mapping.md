# Source-to-Target mapping — AS-IS

## Область mapping

Документ фиксирует текущую трассировку данных:

```text
Excel business label
  → parsed Python key
  → stg.counterparty_requisites_raw
  → normalized core tables
  → reporting mart views
```

Mapping отражает только реализованные поля. Planned-поля в таблицы не добавлены.

## Правила чтения источника

- Excel читается без header: колонка A — label, колонка B — value.
- Labels нормализуются: trim, lowercase, `ё → е`, удаление неразрывных/повторных пробелов и завершающего `:`.
- Числовые значения без дробной части преобразуются в строку, чтобы сохранить идентификаторы как text/varchar.
- Один выбранный лист преобразуется в один словарь и одну raw-строку с `row_number = 1`.
- `counterparty_type` вычисляется: `INDIVIDUAL_ENTREPRENEUR`, если `legal_form` или имя листа содержит «ип»; иначе `LEGAL_ENTITY`.

## Metadata mapping

| Source / context | Python / staging target | Core target | Transformation | DQ / control | Business meaning / notes |
|---|---|---|---|---|---|
| Имя загруженного файла | `stg.load_batches.source_file_name` | Нет | Передаётся из Streamlit uploader | NOT NULL в staging | Имя source file; бинарный файл в БД не сохраняется |
| Выбранный пользователь | `stg.load_batches.uploaded_by` | `core.users.user_id` | Lookup по `username` | Загрузка не создаётся, если пользователь не найден | Автор загрузки |
| Имя выбранного листа | `source_sheet_name` → `stg.counterparty_requisites_raw.source_sheet_name` | Нет | Передаётся без бизнес-преобразования | Может участвовать в выводе типа ИП | Source lineage на уровне листа |
| Логическая запись листа | `row_number` | Нет | В текущем UI всегда `1` | CHECK `row_number > 0` | Номер логической raw-записи, не физическая строка Excel |
| Результат обработки | `processing_status` | Нет | `RAW → VALID/VALID_WITH_WARNINGS/INVALID → IMPORTED` | CHECK допустимых значений | Технический статус raw-записи |
| Созданный контрагент | `processed_counterparty_id` | `core.counterparties.counterparty_id` | Заполняется после успешного INSERT | FK | Связь staging с созданной core-записью |

## Контрагент

| Excel label / parsed key | Staging target | Core target | Transformation rule | DQ checks | Business meaning / notes |
|---|---|---|---|---|---|
| `Форма организации`, `Форма организации собственности`, `Организационно-правовая форма` → `legal_form` | `legal_form` | `core.counterparties.legal_form` | `BTRIM`; тип контрагента дополнительно выводится из значения | Явного staging DQ на обязательность `legal_form` нет; core `NOT NULL` | Организационно-правовая форма; известный gap текущей валидации |
| Derived → `counterparty_type` | `counterparty_type` | `core.counterparties.counterparty_type` | ИП по `legal_form`/имени листа, иначе ЮЛ | REQUIRED, allowed values; CHECK в core | Тип контрагента |
| `Юр. наименование`, `Юридическое наименование`, `Полное наименование`, `Юр. наименование организации` → `full_name` | `full_name` | `core.counterparties.full_name` | `BTRIM` | REQUIRED; core `NOT NULL` | Полное наименование |
| `Сокр. Наименование (опционально)`, `Сокр. наименование`, варианты написания → `short_name` | `short_name` | `core.counterparties.short_name` | Blank → NULL | Нет обязательной проверки | Сокращённое отображаемое наименование |
| `ИНН` → `inn` | `inn` | `core.counterparties.inn` | `BTRIM` | REQUIRED; 10 цифр для ЮЛ, 12 для ИП; duplicate checks; UNIQUE/CHECK в core | Идентификатор контрагента; format-only MVP validation |
| `КПП` → `kpp` | `kpp` | `core.counterparties.kpp` | Blank → NULL | Обязателен и 9 цифр для ЮЛ; запрещён для ИП | КПП юридического лица |
| `ОГРН` → `ogrn` | `ogrn` | `core.counterparties.ogrn` для ЮЛ | Blank → NULL | Обязателен и 13 цифр для ЮЛ; запрещён для ИП | ОГРН; format-only MVP validation |
| `ОГРНИП` → `ogrnip` | `ogrnip` | `core.counterparties.ogrn` для ИП | При импорте значение помещается в общее поле `ogrn` | Обязателен и 15 цифр для ИП; запрещён для ЮЛ | В core отдельного `ogrnip` нет |
| `Юр адрес`, `Юридический адрес` → `legal_address` | `legal_address` | `core.counterparties.legal_address` | Blank → NULL | Нет blocking DQ; mart проверяет полноту | Юридический адрес |
| `почтовый адрес`, `Почтовый адрес` → `mailing_address` | `mailing_address` | `core.counterparties.mailing_address` | Blank → NULL | Нет blocking DQ; mart проверяет полноту | Почтовый адрес |
| `номер телефона`, `Номер телефона`, `Телефон` → `phone_number` | `phone_number` | `core.counterparties.phone_number` | Blank → NULL | Нестандартный regex → WARNING | Контактный телефон |
| `e-mail`, `email`, варианты регистра → `email_address` | `email_address` | `core.counterparties.email_address` | Blank → NULL | Отсутствие или невалидный формат → WARNING | Контактный email |

## Подписант контрагента

Все поля группы создают одну активную строку в `core.counterparty_signatories`.

| Excel label / parsed key | Staging target | Core target | Transformation | DQ checks | Business meaning |
|---|---|---|---|---|---|
| `Должность подписанта (именительный падеж)` → `position_nom` | `position_nom` | `position_nom` | `BTRIM` | ERROR при отсутствии | Должность в именительном падеже |
| `Должность подписанта (родительный падеж)` → `position_gen` | `position_gen` | `position_gen` | Blank → NULL | Отдельного правила нет | Должность в родительном падеже |
| `ФИО (именительный падеж)` → `full_name_nom` | `full_name_nom` | `full_name_nom` | `BTRIM` | ERROR при отсутствии | ФИО подписанта |
| `ФИО (родительный падеж)` → `full_name_gen` | `full_name_gen` | `full_name_gen` | Blank → NULL | WARNING при отсутствии для ЮЛ | ФИО для текста договора |
| `И.О. Фамилия`, `И. О. Фамилия` → `initials_lastname` | `initials_lastname` | `initials_lastname` | Blank → NULL | ERROR при отсутствии | Краткое представление имени |
| `Юр основание (родительный падеж)`, варианты → `legal_basis_gen` | `legal_basis_gen` | `legal_basis_gen` | `BTRIM` | ERROR при отсутствии | Основание полномочий |

## Паспортные данные ИП

| Excel label / parsed key | Staging target | Core target | Transformation | DQ checks | Business meaning / notes |
|---|---|---|---|---|---|
| `Паспортные данные`, `Паспортные данные ИП` → `passport_data` | `passport_data` | `core.individual_entrepreneur_details.passport_data` | Таблица создаётся только для ИП | ERROR при отсутствии для ИП; WARNING при заполнении для ЮЛ | Паспортные данные ИП; отдельная core-запись 1:1 |

## Банковские реквизиты

Повторяющиеся группы staging нормализуются в строки `core.bank_accounts`. `account_order` присваивается как 1, 2 или 3.

| Excel labels / parsed keys | Staging target | Core target | Transformation | DQ checks | Notes |
|---|---|---|---|---|---|
| `р/с`, варианты → `account_number_1` | `account_number_1` | `bank_accounts.account_number`, `account_order=1` | `BTRIM` | Обязателен; ровно 20 цифр | Первый счёт всегда импортируется |
| `к/с`, варианты → `corr_account_1` | `corr_account_1` | `bank_accounts.corr_account` | `BTRIM` | Обязателен; ровно 20 цифр | Первый счёт |
| `БИК банка`, `БИК` → `bik_1` | `bik_1` | `bank_accounts.bik` | `BTRIM` | Обязателен; ровно 9 цифр | Первый счёт |
| `Банк`, `Наименование банка` → `bank_name_1` | `bank_name_1` | `bank_accounts.bank_name` | `BTRIM` | Обязателен | Первый счёт |
| `р/с 2`, варианты → `account_number_2` | `account_number_2` | `bank_accounts.account_number`, `account_order=2` | Строка создаётся, если account number заполнен | Группа 2 должна быть полной; 20 цифр | Второй счёт опционален |
| `к/с 2`, варианты → `corr_account_2` | `corr_account_2` | `bank_accounts.corr_account` | `BTRIM` при создании строки второго счёта | Группа 2 должна быть полной; 20 цифр | Второй корсчёт |
| `БИК банка 2`, `БИК 2` → `bik_2` | `bik_2` | `bank_accounts.bik` | `BTRIM` при создании строки второго счёта | Группа 2 должна быть полной; 9 цифр | Второй БИК |
| `Банк 2`, `Наименование банка 2` → `bank_name_2` | `bank_name_2` | `bank_accounts.bank_name` | `BTRIM` при создании строки второго счёта | Группа 2 должна быть полной | Второй банк |
| `р/с 3`, варианты → `account_number_3` | `account_number_3` | `bank_accounts.account_number`, `account_order=3` | Строка создаётся, если account number заполнен | Группа 3 должна быть полной; 20 цифр | Третий счёт опционален |
| `к/с 3`, варианты → `corr_account_3` | `corr_account_3` | `bank_accounts.corr_account` | `BTRIM` при создании строки третьего счёта | Группа 3 должна быть полной; 20 цифр | Третий корсчёт |
| `БИК банка 3`, `БИК 3` → `bik_3` | `bik_3` | `bank_accounts.bik` | `BTRIM` при создании строки третьего счёта | Группа 3 должна быть полной; 9 цифр | Третий БИК |
| `Банк 3`, `Наименование банка 3` → `bank_name_3` | `bank_name_3` | `bank_accounts.bank_name` | `BTRIM` при создании строки третьего счёта | Группа 3 должна быть полной | Третий банк |

Форматные проверки не подтверждают контрольные разряды, соответствие БИК/корсчёта или реальное существование банка.

## Core → mart mapping

| Core source | Mart target | Rule / business use |
|---|---|---|
| `contract_documents` + `contracts` + справочники и контрагенты | `mart.contract_status` | Одна строка на документ; latest status и latest generation через `ROW_NUMBER()` |
| `contract_documents` + latest generation + active templates | `mart.document_generation_queue` | Только actual, non-archived документы без генерации или с последним `ERROR` |
| `counterparties` + aggregated signatories/accounts + IE details | `mart.counterparty_completeness` | Одна строка на контрагента; признаки наличия/формата и missing fields |

## Не реализовано в AS-IS

- отдельное source-to-raw архивирование исходного файла;
- обновление существующего контрагента по ИНН;
- SCD/history для изменения реквизитов контрагента;
- отдельное поле `ogrnip` в core;
- автоматическое technical lineage поле от каждой core-строки к batch;
- контрольные алгоритмы юридических идентификаторов и банковских счетов.

Эти пункты могут рассматриваться только как `Planned / next iteration` после определения требований.
