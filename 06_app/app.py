import io
import re

import pandas as pd
import streamlit as st
from sqlalchemy import text

from document_generator import generate_document_file


st.set_page_config(
    page_title="ContractFlow SQL",
    page_icon="📄",
    layout="wide"
)

st.title("ContractFlow SQL")
st.caption("Система учёта контрагентов, договорных документов и статусов")

conn = st.connection("contractflow_db", type="sql")


# ============================================================
# DISPLAY SETTINGS
# ============================================================

BATCH_COLUMNS_RU = {
    "load_batch_id": "Номер импорта",
    "source_file_name": "Исходник",
    "load_status": "Статус загрузки",
    "total_rows": "Всего строк",
    "valid_rows": "Валидировано",
    "warning_rows": "Предупреждения",
    "invalid_rows": "Ошибки",
    "uploaded_at": "Загружено",
    "imported_at": "Импортировано",
}

VALIDATION_COLUMNS_RU = {
    "row_number": "Строка",
    "field_name": "Поле",
    "severity": "Тип",
    "error_code": "Код",
    "error_message": "Описание",
    "created_at": "Создано",
}

COUNTERPARTY_COLUMNS_RU = {
    "counterparty_id": "ID",
    "counterparty_type": "Тип",
    "legal_form": "Форма",
    "short_name": "Сокр. наименование",
    "full_name": "Полное наименование",
    "inn": "ИНН",
    "active_signatory_count": "Активных подписантов",
    "bank_account_count": "Банковских счетов",
    "missing_required_fields": "Не хватает",
    "is_ready_for_contract": "Готов к договору",
}

CONTRACT_STATUS_COLUMNS_RU = {
    "document_id": "ID документа",
    "document_number": "Номер документа",
    "document_type_code": "Тип документа",
    "legal_entity_short_name": "Наше юрлицо",
    "counterparty_full_name": "Полное наименование контрагента",
    "counterparty_short_name": "Контрагент",
    "inn": "ИНН",
    "current_status_code": "Текущий статус",
    "delivery_channel_code": "Канал",
    "last_status_date": "Дата статуса",
    "generation_status_code": "Статус генерации",
    "generated_file_name": "Файл",
    "generated_file_path": "Путь",
    "is_generated": "Сгенерирован",
    "requires_action": "Требует действия",
}

GENERATION_QUEUE_COLUMNS_RU = {
    "document_id": "ID документа",
    "document_number": "Номер документа",
    "document_type_code": "Тип документа",
    "legal_entity_short_name": "Наше юрлицо",
    "counterparty_short_name": "Контрагент",
    "template_name": "Шаблон",
    "has_active_template": "Есть активный шаблон",
    "last_generation_status_code": "Последний статус генерации",
    "queue_reason": "Причина очереди",
    "last_generation_error": "Ошибка генерации",
}

LOAD_STATUS_RU = {
    "UPLOADED": "Загружено",
    "VALIDATED": "Проверено",
    "INVALID": "Есть ошибки",
    "IMPORTED": "Импортировано",
    "FAILED": "Ошибка",
}

COUNTERPARTY_TYPE_RU = {
    "LEGAL_ENTITY": "Юрлицо",
    "INDIVIDUAL_ENTREPRENEUR": "ИП",
}


# ============================================================
# COMMON HELPERS
# ============================================================

def run_select(query: str, params: dict | None = None) -> pd.DataFrame:
    """
    Выполняет SELECT-запрос и возвращает результат как DataFrame.
    """
    with conn.session as session:
        result = session.execute(text(query), params or {})
        rows = result.mappings().all()

    return pd.DataFrame([dict(row) for row in rows])


def clear_streamlit_cache() -> None:
    """
    Очищает кэш Streamlit после изменений в БД.
    """
    st.cache_data.clear()

def normalize_search_text(value) -> str:
    """
    Нормализует текст для поиска:
    - нижний регистр
    - ё -> е
    - лишние пробелы убираем
    """
    if value is None or pd.isna(value):
        return ""

    text_value = str(value).lower()
    text_value = text_value.replace("ё", "е")
    text_value = re.sub(r"\s+", " ", text_value).strip()
    return text_value


def filter_dataframe_by_text(
    df: pd.DataFrame,
    search_text: str,
    search_columns: list[str]
) -> pd.DataFrame:
    """
    Ищет по нескольким колонкам сразу.
    Например: full_name + short_name + inn.
    Если введено несколько слов, все они должны встретиться в объединённой строке.
    """
    if df.empty:
        return df

    normalized_query = normalize_search_text(search_text)

    if not normalized_query:
        return df.copy()

    columns_to_use = [col for col in search_columns if col in df.columns]

    if not columns_to_use:
        return df.copy()

    result = df.copy()

    combined_text = (
        result[columns_to_use]
        .fillna("")
        .astype(str)
        .agg(" ".join, axis=1)
        .apply(normalize_search_text)
    )

    search_tokens = normalized_query.split()

    mask = combined_text.apply(
        lambda row_text: all(token in row_text for token in search_tokens)
    )

    return result[mask].copy()

def display_df(df: pd.DataFrame, columns_map: dict | None = None) -> pd.DataFrame:
    """
    Возвращает копию DataFrame с русскими названиями столбцов.
    """
    if df.empty:
        return df

    result = df.copy()

    if "load_status" in result.columns:
        result["load_status"] = result["load_status"].map(LOAD_STATUS_RU).fillna(result["load_status"])

    if "counterparty_type" in result.columns:
        result["counterparty_type"] = result["counterparty_type"].map(COUNTERPARTY_TYPE_RU).fillna(result["counterparty_type"])

    if columns_map:
        result = result.rename(columns=columns_map)

    return result


def get_users() -> pd.DataFrame:
    return run_select("""
        SELECT
            u.user_id,
            u.username,
            u.full_name,
            COALESCE(r.code, '') AS role_code,
            u.is_active
        FROM core.users u
        LEFT JOIN core.user_roles r
            ON r.role_id = u.role_id
        WHERE u.is_active = true
        ORDER BY u.full_name, u.username;
    """)


def get_current_username(users_df: pd.DataFrame) -> str:
    """
    Глобальный выбор пользователя в sidebar.
    Пока без пароля и верификации.
    """
    st.sidebar.subheader("Пользователь")

    if users_df.empty:
        st.sidebar.error("Нет активных пользователей в core.users.")
        return ""

    users_df = users_df.copy()
    users_df["display_name"] = (
        users_df["full_name"].fillna("")
        + " | "
        + users_df["role_code"].fillna("")
        + " | "
        + users_df["username"].fillna("")
    )

    selected_user_display = st.sidebar.selectbox(
        "Текущий пользователь",
        users_df["display_name"].tolist()
    )

    selected_user = users_df[
        users_df["display_name"] == selected_user_display
    ].iloc[0]

    return selected_user["username"]


# ============================================================
# EXCEL PARSING
# ============================================================

def normalize_label(value) -> str:
    """
    Нормализует название поля из Excel.
    Используется только для названий полей, не для значений.
    """
    if pd.isna(value):
        return ""

    label = str(value).strip().lower()
    label = label.replace("ё", "е")
    label = label.replace("\xa0", " ")
    label = re.sub(r"\s+", " ", label)
    label = label.rstrip(":")
    return label


def clean_value(value):
    """
    Превращает значение из Excel в строку или None.
    ИНН/КПП/ОГРН/БИК/счета храним как varchar.
    """
    if pd.isna(value):
        return None

    if isinstance(value, float) and value.is_integer():
        return str(int(value)).strip()

    return str(value).strip()


def get_value(data: dict, aliases: list[str]):
    """
    Возвращает значение поля по одному из возможных названий.
    """
    normalized_aliases = [normalize_label(alias) for alias in aliases]

    for alias in normalized_aliases:
        if alias in data:
            return data[alias]

    return None


def parse_requisites_excel(file_bytes: bytes, sheet_name: str) -> dict:
    """
    Читает вертикальный Excel-шаблон:
    колонка A = название поля
    колонка B = значение
    """
    df = pd.read_excel(
        io.BytesIO(file_bytes),
        sheet_name=sheet_name,
        header=None
    )

    if df.shape[1] < 2:
        raise ValueError("В листе должно быть минимум 2 колонки: поле и значение.")

    df = df.iloc[:, :2]
    df.columns = ["field_name", "field_value"]

    data = {}

    for _, row in df.iterrows():
        key = normalize_label(row["field_name"])
        value = clean_value(row["field_value"])

        if key:
            data[key] = value

    legal_form = get_value(data, [
        "Форма организации",
        "Форма организации собственности",
        "Организационно-правовая форма"
    ])

    if legal_form and "ип" in legal_form.lower():
        counterparty_type = "INDIVIDUAL_ENTREPRENEUR"
    elif "ип" in sheet_name.lower():
        counterparty_type = "INDIVIDUAL_ENTREPRENEUR"
    else:
        counterparty_type = "LEGAL_ENTITY"

    parsed = {
        "source_sheet_name": sheet_name,
        "counterparty_type": counterparty_type,

        "legal_form": legal_form,
        "full_name": get_value(data, [
            "Юр. наименование",
            "Юридическое наименование",
            "Полное наименование",
            "Юр. наименование организации"
        ]),
        "short_name": get_value(data, [
            "Сокр. Наименование (опционально)",
            "Сокр. наименование",
            "Сокращенное наименование",
            "Сокращённое наименование"
        ]),

        "inn": get_value(data, ["ИНН"]),
        "kpp": get_value(data, ["КПП"]),
        "ogrn": get_value(data, ["ОГРН"]),
        "ogrnip": get_value(data, ["ОГРНИП"]),

        "position_nom": get_value(data, [
            "Должность подписанта (именительный падеж)"
        ]),
        "position_gen": get_value(data, [
            "Должность подписанта (родительный падеж)"
        ]),
        "full_name_nom": get_value(data, [
            "ФИО (именительный падеж)"
        ]),
        "full_name_gen": get_value(data, [
            "ФИО (родительный падеж)"
        ]),
        "initials_lastname": get_value(data, [
            "И.О. Фамилия",
            "И. О. Фамилия"
        ]),
        "legal_basis_gen": get_value(data, [
            "Юр основание (родительный падеж)",
            "Юридическое основание (родительный падеж)",
            "Основание полномочий"
        ]),

        "legal_address": get_value(data, [
            "Юр адрес",
            "Юридический адрес"
        ]),
        "mailing_address": get_value(data, [
            "почтовый адрес",
            "Почтовый адрес"
        ]),
        "phone_number": get_value(data, [
            "номер телефона",
            "Номер телефона",
            "Телефон"
        ]),
        "email_address": get_value(data, [
            "e-mail",
            "email",
            "E-mail",
            "Email"
        ]),
        "passport_data": get_value(data, [
            "Паспортные данные",
            "Паспортные данные ИП"
        ]),

        "account_number_1": get_value(data, ["р/с", "Р/с", "Расчетный счет", "Расчётный счет"]),
        "corr_account_1": get_value(data, ["к/с", "К/с", "Корреспондентский счет", "Корреспондентский счёт"]),
        "bik_1": get_value(data, ["БИК банка", "БИК"]),
        "bank_name_1": get_value(data, ["Банк", "Наименование банка"]),

        "account_number_2": get_value(data, ["р/с 2", "Р/с 2", "Расчетный счет 2", "Расчётный счет 2"]),
        "corr_account_2": get_value(data, ["к/с 2", "К/с 2", "Корреспондентский счет 2", "Корреспондентский счёт 2"]),
        "bik_2": get_value(data, ["БИК банка 2", "БИК 2"]),
        "bank_name_2": get_value(data, ["Банк 2", "Наименование банка 2"]),

        "account_number_3": get_value(data, ["р/с 3", "Р/с 3", "Расчетный счет 3", "Расчётный счет 3"]),
        "corr_account_3": get_value(data, ["к/с 3", "К/с 3", "Корреспондентский счет 3", "Корреспондентский счёт 3"]),
        "bik_3": get_value(data, ["БИК банка 3", "БИК 3"]),
        "bank_name_3": get_value(data, ["Банк 3", "Наименование банка 3"]),
    }

    return parsed


# ============================================================
# STAGING FUNCTIONS
# ============================================================

def insert_requisites_to_staging(
    source_file_name: str,
    uploaded_by_username: str,
    parsed: dict
) -> int:
    """
    Создаёт stg.load_batches и stg.counterparty_requisites_raw.
    Возвращает load_batch_id.
    """
    with conn.session as session:
        batch_result = session.execute(
            text("""
                INSERT INTO stg.load_batches (
                    source_file_name,
                    uploaded_by,
                    total_rows
                )
                SELECT
                    :source_file_name,
                    user_id,
                    1
                FROM core.users
                WHERE username = :uploaded_by_username
                RETURNING load_batch_id;
            """),
            {
                "source_file_name": source_file_name,
                "uploaded_by_username": uploaded_by_username,
            }
        )

        load_batch_id = batch_result.scalar_one_or_none()

        if load_batch_id is None:
            raise ValueError(
                f"Пользователь {uploaded_by_username} не найден в core.users"
            )

        session.execute(
            text("""
                INSERT INTO stg.counterparty_requisites_raw (
                    load_batch_id,
                    row_number,
                    source_sheet_name,
                    counterparty_type,

                    legal_form,
                    full_name,
                    short_name,

                    inn,
                    kpp,
                    ogrn,
                    ogrnip,

                    position_nom,
                    position_gen,
                    full_name_nom,
                    full_name_gen,
                    initials_lastname,
                    legal_basis_gen,

                    legal_address,
                    mailing_address,
                    phone_number,
                    email_address,
                    passport_data,

                    account_number_1,
                    corr_account_1,
                    bik_1,
                    bank_name_1,

                    account_number_2,
                    corr_account_2,
                    bik_2,
                    bank_name_2,

                    account_number_3,
                    corr_account_3,
                    bik_3,
                    bank_name_3
                )
                VALUES (
                    :load_batch_id,
                    1,
                    :source_sheet_name,
                    :counterparty_type,

                    :legal_form,
                    :full_name,
                    :short_name,

                    :inn,
                    :kpp,
                    :ogrn,
                    :ogrnip,

                    :position_nom,
                    :position_gen,
                    :full_name_nom,
                    :full_name_gen,
                    :initials_lastname,
                    :legal_basis_gen,

                    :legal_address,
                    :mailing_address,
                    :phone_number,
                    :email_address,
                    :passport_data,

                    :account_number_1,
                    :corr_account_1,
                    :bik_1,
                    :bank_name_1,

                    :account_number_2,
                    :corr_account_2,
                    :bik_2,
                    :bank_name_2,

                    :account_number_3,
                    :corr_account_3,
                    :bik_3,
                    :bank_name_3
                );
            """),
            {
                "load_batch_id": load_batch_id,
                **parsed,
            }
        )

        session.commit()

    clear_streamlit_cache()
    return load_batch_id


def validate_batch(load_batch_id: int) -> None:
    """
    Запускает stg.validate_counterparty_requisites.
    """
    with conn.session as session:
        session.execute(
            text("SELECT stg.validate_counterparty_requisites(:load_batch_id);"),
            {"load_batch_id": load_batch_id}
        )
        session.commit()

    clear_streamlit_cache()


def import_batch_to_core(load_batch_id: int) -> int:
    """
    Запускает stg.import_counterparty_requisites.
    Возвращает количество импортированных строк.
    """
    with conn.session as session:
        result = session.execute(
            text("SELECT stg.import_counterparty_requisites(:load_batch_id);"),
            {"load_batch_id": load_batch_id}
        )

        imported_count = result.scalar_one()
        session.commit()

    clear_streamlit_cache()
    return imported_count


def get_recent_batches(limit: int = 7) -> pd.DataFrame:
    return run_select("""
        SELECT
            load_batch_id,
            source_file_name,
            load_status,
            total_rows,
            valid_rows,
            warning_rows,
            invalid_rows,
            uploaded_at,
            imported_at
        FROM stg.load_batches
        ORDER BY load_batch_id DESC
        LIMIT :limit;
    """, {"limit": limit})


def get_batch_summary(load_batch_id: int) -> pd.DataFrame:
    return run_select("""
        SELECT
            load_batch_id,
            source_file_name,
            load_status,
            total_rows,
            valid_rows,
            warning_rows,
            invalid_rows,
            uploaded_at,
            imported_at
        FROM stg.load_batches
        WHERE load_batch_id = :load_batch_id;
    """, {"load_batch_id": load_batch_id})


def get_validation_errors(load_batch_id: int) -> pd.DataFrame:
    return run_select("""
        SELECT
            row_number,
            field_name,
            severity,
            error_code,
            error_message,
            created_at
        FROM stg.validation_errors
        WHERE load_batch_id = :load_batch_id
        ORDER BY
            CASE severity
                WHEN 'ERROR' THEN 1
                WHEN 'WARNING' THEN 2
                ELSE 3
            END,
            field_name;
    """, {"load_batch_id": load_batch_id})


# ============================================================
# CORE DOCUMENT FUNCTIONS
# ============================================================

def get_legal_entities() -> pd.DataFrame:
    return run_select("""
        SELECT
            legal_entity_id,
            short_name,
            full_name
        FROM core.legal_entities
        ORDER BY short_name;
    """)


def get_ready_counterparties() -> pd.DataFrame:
    return run_select("""
        SELECT
            counterparty_id,
            counterparty_type,
            short_name,
            full_name,
            inn,
            is_ready_for_contract
        FROM mart.counterparty_completeness
        WHERE is_ready_for_contract = true
        ORDER BY short_name, full_name;
    """)


def get_document_types() -> pd.DataFrame:
    return run_select("""
        SELECT
            document_type_id,
            code,
            name
        FROM core.document_types
        ORDER BY
            CASE code
                WHEN 'CONTRACT' THEN 1
                WHEN 'NEW_EDITION' THEN 2
                WHEN 'ADDITIONAL_AGREEMENT' THEN 3
                WHEN 'PROTOCOL_OF_DISAGREEMENT' THEN 4
                WHEN 'PERSONAL_ADDITIONAL_AGREEMENT' THEN 5
                ELSE 99
            END;
    """)


def get_parent_documents(
    legal_entity_short_name: str,
    counterparty_inn: str
) -> pd.DataFrame:
    return run_select("""
        SELECT
            cd.document_id,
            cd.document_number,
            dt.code AS document_type_code,
            cd.document_date
        FROM core.contract_documents cd
        JOIN core.contracts c
            ON c.contract_id = cd.contract_id
        JOIN core.legal_entities le
            ON le.legal_entity_id = c.legal_entity_id
        JOIN core.counterparties cp
            ON cp.counterparty_id = c.counterparty_id
        JOIN core.document_types dt
            ON dt.document_type_id = cd.document_type_id
        WHERE le.short_name = :legal_entity_short_name
          AND cp.inn = :counterparty_inn
          AND cd.is_archived = false
        ORDER BY cd.document_date DESC, cd.document_id DESC;
    """, {
        "legal_entity_short_name": legal_entity_short_name,
        "counterparty_inn": counterparty_inn,
    })


def create_contract_document(
    legal_entity_short_name: str,
    counterparty_inn: str,
    document_type_code: str,
    username: str,
    parent_document_number,
    document_date,
    comment
) -> dict:
    with conn.session as session:
        result = session.execute(
            text("""
                SELECT *
                FROM core.create_contract_document(
                    :legal_entity_short_name,
                    :counterparty_inn,
                    :document_type_code,
                    :username,
                    :parent_document_number,
                    :document_date,
                    :comment
                );
            """),
            {
                "legal_entity_short_name": legal_entity_short_name,
                "counterparty_inn": counterparty_inn,
                "document_type_code": document_type_code,
                "username": username,
                "parent_document_number": parent_document_number,
                "document_date": document_date,
                "comment": comment,
            }
        )

        row = result.mappings().first()
        session.commit()

    clear_streamlit_cache()

    if row is None:
        raise ValueError("Функция core.create_contract_document не вернула результат.")

    return dict(row)


def get_documents_for_actions() -> pd.DataFrame:
    return run_select("""
        SELECT
            document_id,
            document_number,
            document_type_code,
            legal_entity_short_name,
            counterparty_short_name,
            inn,
            current_status_code,
            generation_status_code,
            generated_file_name
        FROM mart.contract_status
        ORDER BY document_id DESC;
    """)


def register_document_generation(
    document_number: str,
    username: str,
    generation_status_code: str,
    error_message
) -> dict:
    with conn.session as session:
        result = session.execute(
            text("""
                SELECT *
                FROM core.register_document_generation(
                    :document_number,
                    :username,
                    :generation_status_code,
                    :error_message
                );
            """),
            {
                "document_number": document_number,
                "username": username,
                "generation_status_code": generation_status_code,
                "error_message": error_message,
            }
        )

        row = result.mappings().first()
        session.commit()

    clear_streamlit_cache()

    if row is None:
        raise ValueError("Функция core.register_document_generation не вернула результат.")

    return dict(row)


def get_document_statuses() -> pd.DataFrame:
    return run_select("""
        SELECT
            code,
            name,
            is_final
        FROM core.document_statuses
        ORDER BY
            CASE code
                WHEN 'GENERATED' THEN 1
                WHEN 'SENT' THEN 2
                WHEN 'DELIVERED' THEN 3
                WHEN 'SIGNED' THEN 4
                WHEN 'REJECTED' THEN 5
                WHEN 'NEEDS_CORRECTION' THEN 6
                WHEN 'ARCHIVED' THEN 7
                ELSE 99
            END;
    """)


def get_delivery_channels() -> pd.DataFrame:
    return run_select("""
        SELECT
            code,
            name
        FROM core.delivery_channels
        ORDER BY
            CASE code
                WHEN 'INTERNAL' THEN 1
                WHEN 'EDO' THEN 2
                WHEN 'ORIGINAL' THEN 3
                WHEN 'EMAIL' THEN 4
                WHEN 'OTHER' THEN 5
                ELSE 99
            END;
    """)


def update_document_status(
    document_number: str,
    new_status_code: str,
    delivery_channel_code: str,
    username: str,
    comment
) -> dict:
    with conn.session as session:
        result = session.execute(
            text("""
                SELECT *
                FROM core.update_document_status(
                    :document_number,
                    :new_status_code,
                    :delivery_channel_code,
                    :username,
                    :comment
                );
            """),
            {
                "document_number": document_number,
                "new_status_code": new_status_code,
                "delivery_channel_code": delivery_channel_code,
                "username": username,
                "comment": comment,
            }
        )

        row = result.mappings().first()
        session.commit()

    clear_streamlit_cache()

    if row is None:
        raise ValueError("Функция core.update_document_status не вернула результат.")

    return dict(row)


# ============================================================
# SIDEBAR
# ============================================================

users_df = get_users()
current_username = get_current_username(users_df)

st.sidebar.title("Навигация")

page = st.sidebar.radio(
    "Раздел",
    [
        "Загрузка реквизитов",
        "Валидация и импорт реквизитов",
        "Полнота контрагентов",
        "Создание документа",
        "Очередь генерации",
        "Генерация документов",
        "Обновление статуса",
        "Реестр документов",
        "Проверка подключения",
    ]
)


# ============================================================
# PAGE: UPLOAD REQUISITES
# ============================================================

if page == "Загрузка реквизитов":
    st.header("Загрузка Excel-реквизитов в staging")

    st.info(
        "Загрузи Excel-файл клиента с вертикальным шаблоном: "
        "в первой колонке название поля, во второй колонке значение. "
        "Если в файле два листа — ООО и ИП — выбери нужный лист."
    )

    st.write(f"Загрузка будет выполнена от пользователя: **{current_username}**")

    uploaded_file = st.file_uploader(
        "Excel-файл реквизитов",
        type=["xlsx", "xlsm", "xls"]
    )

    if uploaded_file is not None:
        file_bytes = uploaded_file.getvalue()

        try:
            excel = pd.ExcelFile(io.BytesIO(file_bytes))
            sheet_names = excel.sheet_names

            selected_sheet = st.selectbox(
                "Лист Excel",
                sheet_names
            )

            parsed = parse_requisites_excel(file_bytes, selected_sheet)

            st.subheader("Предпросмотр распознанных данных")

            preview_df = pd.DataFrame(
                [{"Поле": key, "Значение": value} for key, value in parsed.items()]
            )

            st.dataframe(preview_df, use_container_width=True)

            if st.button("Загрузить в staging"):
                load_batch_id = insert_requisites_to_staging(
                    source_file_name=uploaded_file.name,
                    uploaded_by_username=current_username,
                    parsed=parsed
                )

                st.success(
                    f"Файл загружен в staging. Номер импорта: {load_batch_id}"
                )

        except Exception as e:
            st.error("Ошибка при обработке файла")
            st.exception(e)


# ============================================================
# PAGE: VALIDATE AND IMPORT
# ============================================================

elif page == "Валидация и импорт реквизитов":
    st.header("Валидация и импорт реквизитов")

    st.subheader("Последние загрузки")

    limit = st.selectbox(
        "Показать последние",
        [7, 20, 50],
        index=0
    )

    batches_df = get_recent_batches(limit=int(limit))
    st.dataframe(display_df(batches_df, BATCH_COLUMNS_RU), use_container_width=True)

    if batches_df.empty:
        st.info("Пока нет batch-загрузок.")
    else:
        batches_df = batches_df.copy()
        batches_df["display_name"] = (
            "№ "
            + batches_df["load_batch_id"].astype(str)
            + " | "
            + batches_df["source_file_name"].fillna("")
            + " | "
            + batches_df["load_status"].map(LOAD_STATUS_RU).fillna(batches_df["load_status"])
            + " | "
            + batches_df["uploaded_at"].astype(str)
        )

        selected_batch_display = st.selectbox(
            "Номер импорта",
            batches_df["display_name"].tolist()
        )

        selected_batch = batches_df[
            batches_df["display_name"] == selected_batch_display
        ].iloc[0]

        load_batch_id = int(selected_batch["load_batch_id"])

        if st.button("Валидировать выбранный импорт"):
            try:
                validate_batch(load_batch_id)
                st.success(f"Импорт № {load_batch_id} провалидирован.")
            except Exception as e:
                st.error("Ошибка при валидации")
                st.exception(e)

        st.subheader("Статус импорта")

        summary_df = get_batch_summary(load_batch_id)
        st.dataframe(display_df(summary_df, BATCH_COLUMNS_RU), use_container_width=True)

        st.subheader("Ошибки и предупреждения")

        errors_df = get_validation_errors(load_batch_id)

        if errors_df.empty:
            st.success("Ошибок и предупреждений нет.")
        else:
            st.dataframe(display_df(errors_df, VALIDATION_COLUMNS_RU), use_container_width=True)

            error_count = (errors_df["severity"] == "ERROR").sum()
            warning_count = (errors_df["severity"] == "WARNING").sum()

            if error_count > 0:
                st.error(f"Найдено ошибок: {error_count}. Импорт в core запрещён.")
            elif warning_count > 0:
                st.warning(f"Найдено предупреждений: {warning_count}. Импорт разрешён, но данные стоит проверить.")

        st.subheader("Импорт в core")

        if summary_df.empty:
            st.info("Сначала выбери существующий импорт.")
        else:
            current_status = summary_df.iloc[0]["load_status"]

            if current_status == "VALIDATED":
                if st.button("Импортировать реквизиты в core"):
                    try:
                        imported_count = import_batch_to_core(load_batch_id)
                        st.success(
                            f"Импорт № {load_batch_id} перенесён в core. "
                            f"Импортировано строк: {imported_count}"
                        )
                    except Exception as e:
                        st.error("Ошибка при импорте в core")
                        st.exception(e)

            elif current_status == "IMPORTED":
                st.success("Эти реквизиты уже импортированы в core.")

            elif current_status == "INVALID":
                st.error("Есть критические ошибки. Импорт запрещён.")

            else:
                st.info(
                    f"Текущий статус: {LOAD_STATUS_RU.get(current_status, current_status)}. "
                    "Сначала нужно выполнить валидацию."
                )


# ============================================================
# PAGE: COUNTERPARTY COMPLETENESS
# ============================================================

elif page == "Полнота контрагентов":
    st.header("Полнота реквизитов контрагентов")

    df = run_select("""
        SELECT
            counterparty_id,
            counterparty_type,
            legal_form,
            short_name,
            full_name,
            inn,
            active_signatory_count,
            bank_account_count,
            missing_required_fields,
            is_ready_for_contract
        FROM mart.counterparty_completeness
        ORDER BY counterparty_id DESC;
    """)

    st.dataframe(display_df(df, COUNTERPARTY_COLUMNS_RU), use_container_width=True)


# ============================================================
# PAGE: CREATE DOCUMENT
# ============================================================

elif page == "Создание документа":
    st.header("Создание договорного документа")

    st.info(
        "Экран создаёт запись в core.contract_documents "
        "и автоматически ставит первичный статус GENERATED."
    )

    st.write(f"Документ будет создан от пользователя: **{current_username}**")

    legal_entities_df = get_legal_entities()
    counterparties_df = get_ready_counterparties()
    document_types_df = get_document_types()

    if legal_entities_df.empty:
        st.error("Нет юрлиц в core.legal_entities.")
    elif counterparties_df.empty:
        st.warning("Нет контрагентов, готовых к созданию договора.")
    elif document_types_df.empty:
        st.error("Нет типов документов в core.document_types.")
    else:
        selected_legal_entity = st.selectbox(
            "Наше юрлицо",
            legal_entities_df["short_name"].tolist()
        )

        counterparty_search = st.text_input(
            "Поиск контрагента",
            placeholder="Введите ИНН, сокращённое или полное наименование"
        )

        filtered_counterparties_df = filter_dataframe_by_text(
            counterparties_df,
            counterparty_search,
            ["short_name", "full_name", "inn", "legal_form", "counterparty_type"]
        )

        st.caption(f"Найдено контрагентов: {len(filtered_counterparties_df)}")

        if filtered_counterparties_df.empty:
            st.warning("Контрагенты по заданному поиску не найдены.")
            st.stop()

        filtered_counterparties_df = filtered_counterparties_df.copy()
        filtered_counterparties_df["display_name"] = (
            filtered_counterparties_df["short_name"].fillna("")
            + " | "
            + filtered_counterparties_df["full_name"].fillna("")
            + " | ИНН "
            + filtered_counterparties_df["inn"].fillna("")
        )

        selected_counterparty_display = st.selectbox(
            "Контрагент",
            filtered_counterparties_df["display_name"].tolist()
        )

        selected_counterparty = filtered_counterparties_df[
            filtered_counterparties_df["display_name"] == selected_counterparty_display
        ].iloc[0]

        selected_counterparty_inn = selected_counterparty["inn"]

        document_types_df = document_types_df.copy()
        document_types_df["display_name"] = (
            document_types_df["name"].fillna("")
            + " | "
            + document_types_df["code"].fillna("")
        )

        selected_document_type_display = st.selectbox(
            "Тип документа",
            document_types_df["display_name"].tolist()
        )

        selected_document_type = document_types_df[
            document_types_df["display_name"] == selected_document_type_display
        ].iloc[0]["code"]

        parent_document_number = None

        if selected_document_type != "CONTRACT":
            parent_docs_df = get_parent_documents(
                selected_legal_entity,
                selected_counterparty_inn
            )

            if parent_docs_df.empty:
                st.warning(
                    "Для выбранного контрагента и юрлица нет родительских документов. "
                    "Сначала создай договор."
                )
            else:
                parent_docs_df = parent_docs_df.copy()
                parent_docs_df["display_name"] = (
                    parent_docs_df["document_number"]
                    + " | "
                    + parent_docs_df["document_type_code"]
                    + " | "
                    + parent_docs_df["document_date"].astype(str)
                )

                selected_parent_display = st.selectbox(
                    "Родительский документ",
                    parent_docs_df["display_name"].tolist()
                )

                parent_document_number = parent_docs_df[
                    parent_docs_df["display_name"] == selected_parent_display
                ].iloc[0]["document_number"]

        document_date = st.date_input("Дата документа")

        comment = st.text_area(
            "Комментарий",
            value="Документ создан через Streamlit"
        )

        st.subheader("Проверка перед созданием")

        st.write({
            "Наше юрлицо": selected_legal_entity,
            "ИНН контрагента": selected_counterparty_inn,
            "Тип документа": selected_document_type,
            "Родительский документ": parent_document_number,
            "Дата документа": str(document_date),
            "Пользователь": current_username,
        })

        can_create = True

        if selected_document_type != "CONTRACT" and parent_document_number is None:
            can_create = False

        if can_create:
            if st.button("Создать документ"):
                try:
                    created = create_contract_document(
                        legal_entity_short_name=selected_legal_entity,
                        counterparty_inn=selected_counterparty_inn,
                        document_type_code=selected_document_type,
                        username=current_username,
                        parent_document_number=parent_document_number,
                        document_date=document_date,
                        comment=comment,
                    )

                    st.success("Документ создан.")
                    st.dataframe(pd.DataFrame([created]), use_container_width=True)

                except Exception as e:
                    st.error("Ошибка при создании документа")
                    st.exception(e)
        else:
            st.info("Создание документа пока недоступно: нужен родительский документ.")


# ============================================================
# PAGE: GENERATION QUEUE
# ============================================================

elif page == "Очередь генерации":
    st.header("Очередь генерации документов")

    df = run_select("""
        SELECT
            document_id,
            document_number,
            document_type_code,
            legal_entity_short_name,
            counterparty_short_name,
            template_name,
            has_active_template,
            last_generation_status_code,
            queue_reason,
            last_generation_error
        FROM mart.document_generation_queue
        ORDER BY document_id DESC;
    """)
    search_text = st.text_input(
        "Поиск по очереди генерации",
        placeholder="Введите номер документа, контрагента, шаблон или причину"
    )

    df = filter_dataframe_by_text(
        df,
        search_text,
        [
            "document_number",
            "document_type_code",
            "legal_entity_short_name",
            "counterparty_short_name",
            "template_name",
            "last_generation_status_code",
            "queue_reason",
            "last_generation_error",
        ]
    )

    st.caption(f"Найдено документов: {len(df)}")
    st.dataframe(display_df(df, GENERATION_QUEUE_COLUMNS_RU), use_container_width=True)


# ============================================================
# PAGE: GENERATE DOCUMENTS
# ============================================================

elif page == "Генерация документов":
    st.header("Генерация документов")

    st.info(
        "Экран создаёт реальный файл по активному DOCX-шаблону. "
        "По умолчанию формируется PDF. Для PDF сначала создаётся временный DOCX, "
        "затем он конвертируется через Microsoft Word/docx2pdf и удаляется."
    )

    st.write(f"Генерация будет выполнена от пользователя: **{current_username}**")

    docs_df = get_documents_for_actions()

    if docs_df.empty:
        st.info("Документов пока нет.")
    else:
        document_search = st.text_input(
            "Поиск документа",
            placeholder="Введите номер документа, контрагента, ИНН или тип документа"
        )

        docs_df = filter_dataframe_by_text(
            docs_df,
            document_search,
            [
                "document_number",
                "document_type_code",
                "counterparty_short_name",
                "inn",
                "current_status_code",
                "generation_status_code",
                "generated_file_name",
            ]
        )

        st.caption(f"Найдено документов: {len(docs_df)}")

        if docs_df.empty:
            st.warning("Документы по заданному поиску не найдены.")
            st.stop()

        docs_df = docs_df.copy()
        docs_df["display_name"] = (
            docs_df["document_number"]
            + " | "
            + docs_df["document_type_code"]
            + " | "
            + docs_df["counterparty_short_name"].fillna("")
        )

        selected_doc_display = st.selectbox(
            "Документ",
            docs_df["display_name"].tolist()
        )

        selected_doc = docs_df[
            docs_df["display_name"] == selected_doc_display
        ].iloc[0]

        output_format = st.radio(
            "Формат результата",
            ["PDF", "DOCX"],
            index=0,
            horizontal=True
        )

        base_output_dir = st.text_input(
            "Базовая папка для сохранения",
            value="generated_documents",
            help=(
                "Можно оставить generated_documents или указать полный путь, "
                "например C:\\Users\\YourUser\\Documents\\ContractFlow"
            )
        )

        st.caption(
            "Файл будет сохранён в структуру: "
            "<базовая папка>/<юрлицо>/<тип документа>/<имя файла>"
        )

        if st.button("Сгенерировать файл"):
            try:
                result = generate_document_file(
                    conn=conn,
                    document_number=selected_doc["document_number"],
                    username=current_username,
                    output_format=output_format,
                    base_output_dir=base_output_dir
                )

                st.success("Файл успешно сгенерирован.")
                st.dataframe(pd.DataFrame([result]), use_container_width=True)

            except Exception as e:
                st.error("Ошибка при генерации файла")
                st.exception(e)


# ============================================================
# PAGE: UPDATE STATUS
# ============================================================

elif page == "Обновление статуса":
    st.header("Обновление статуса документа")

    st.info(
        "Статусы не перезаписываются. "
        "Каждое изменение добавляется новой строкой в core.document_status_history."
    )

    st.write(f"Статус будет обновлён от пользователя: **{current_username}**")

    docs_df = get_documents_for_actions()
    statuses_df = get_document_statuses()
    channels_df = get_delivery_channels()

    if docs_df.empty:
        st.info("Документов пока нет.")
    elif statuses_df.empty:
        st.error("Нет статусов в core.document_statuses.")
    elif channels_df.empty:
        st.error("Нет каналов доставки в core.delivery_channels.")
    else:
        document_search = st.text_input(
            "Поиск документа",
            placeholder="Введите номер документа, контрагента, ИНН или текущий статус"
        )

        docs_df = filter_dataframe_by_text(
            docs_df,
            document_search,
            [
                "document_number",
                "document_type_code",
                "counterparty_short_name",
                "inn",
                "current_status_code",
                "generation_status_code",
                "generated_file_name",
            ]
        )

        st.caption(f"Найдено документов: {len(docs_df)}")

        if docs_df.empty:
            st.warning("Документы по заданному поиску не найдены.")
            st.stop()
        docs_df = docs_df.copy()
        docs_df["display_name"] = (
            docs_df["document_number"]
            + " | текущий статус: "
            + docs_df["current_status_code"].fillna("NO_STATUS")
            + " | "
            + docs_df["counterparty_short_name"].fillna("")
        )

        selected_doc_display = st.selectbox(
            "Документ",
            docs_df["display_name"].tolist()
        )

        selected_doc = docs_df[
            docs_df["display_name"] == selected_doc_display
        ].iloc[0]

        statuses_df = statuses_df.copy()
        statuses_df["display_name"] = (
            statuses_df["name"].fillna("")
            + " | "
            + statuses_df["code"].fillna("")
        )

        selected_status_display = st.selectbox(
            "Новый статус",
            statuses_df["display_name"].tolist()
        )

        new_status_code = statuses_df[
            statuses_df["display_name"] == selected_status_display
        ].iloc[0]["code"]

        channels_df = channels_df.copy()
        channels_df["display_name"] = (
            channels_df["name"].fillna("")
            + " | "
            + channels_df["code"].fillna("")
        )

        selected_channel_display = st.selectbox(
            "Канал доставки",
            channels_df["display_name"].tolist()
        )

        delivery_channel_code = channels_df[
            channels_df["display_name"] == selected_channel_display
        ].iloc[0]["code"]

        comment = st.text_area(
            "Комментарий",
            value="Статус обновлён через Streamlit"
        )

        if st.button("Обновить статус"):
            try:
                result = update_document_status(
                    document_number=selected_doc["document_number"],
                    new_status_code=new_status_code,
                    delivery_channel_code=delivery_channel_code,
                    username=current_username,
                    comment=comment
                )

                st.success("Статус обновлён.")
                st.dataframe(pd.DataFrame([result]), use_container_width=True)

            except Exception as e:
                st.error("Ошибка при обновлении статуса")
                st.exception(e)


# ============================================================
# PAGE: CONTRACT STATUS
# ============================================================

elif page == "Реестр документов":
    st.header("Реестр документов")

    df = run_select("""
        SELECT
            document_id,
            document_number,
            document_type_code,
            legal_entity_short_name,
            counterparty_short_name,
            counterparty_full_name,
            inn,
            current_status_code,
            delivery_channel_code,
            last_status_date,
            generation_status_code,
            generated_file_name,
            generated_file_path,
            is_generated,
            requires_action
        FROM mart.contract_status
        ORDER BY document_id DESC;
    """)

    search_text = st.text_input(
        "Поиск по реестру",
        placeholder="Введите номер документа, контрагента, ИНН, тип или статус"
    )

    df = filter_dataframe_by_text(
        df,
        search_text,
        [
            "document_number",
            "document_type_code",
            "legal_entity_short_name",
            "counterparty_short_name",
            "counterparty_full_name",
            "inn",
            "current_status_code",
            "delivery_channel_code",
            "generation_status_code",
            "generated_file_name",
            "generated_file_path",
        ]
    )

    st.caption(f"Найдено документов: {len(df)}")

    st.dataframe(display_df(df, CONTRACT_STATUS_COLUMNS_RU), use_container_width=True)


# ============================================================
# PAGE: CONNECTION CHECK
# ============================================================

elif page == "Проверка подключения":
    st.header("Проверка подключения к PostgreSQL")

    df = run_select("""
        SELECT
            current_database() AS database_name,
            current_schema() AS current_schema,
            now() AS checked_at;
    """)

    st.dataframe(df, use_container_width=True)

    if not df.empty:
        st.success(f"Подключение выполнено. База: {df.loc[0, 'database_name']}")