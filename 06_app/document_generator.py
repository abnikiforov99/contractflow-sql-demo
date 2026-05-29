from pathlib import Path
import re

from docxtpl import DocxTemplate
from docx2pdf import convert
from sqlalchemy import text


APP_DIR = Path(__file__).resolve().parent


DOCUMENT_TYPE_FOLDER = {
    "CONTRACT": "Договоры",
    "NEW_EDITION": "Договоры",
    "ADDITIONAL_AGREEMENT": "Доп. соглашения",
    "PROTOCOL_OF_DISAGREEMENT": "Протоколы разногласий",
    "PERSONAL_ADDITIONAL_AGREEMENT": "Персональные ДС",
}


DOCUMENT_FILE_PREFIX = {
    "CONTRACT": "Договор",
    "NEW_EDITION": "Новая редакция",
    "ADDITIONAL_AGREEMENT": "Доп. соглашение",
    "PROTOCOL_OF_DISAGREEMENT": "Протокол разногласий",
    "PERSONAL_ADDITIONAL_AGREEMENT": "Персональное ДС",
}


def sanitize_path_part(value: str) -> str:
    """
    Убирает символы, запрещённые в именах файлов/папок Windows.
    """
    if value is None:
        return ""

    value = str(value).strip()
    value = re.sub(r'[<>:"/\\|?*]', "_", value)
    value = re.sub(r"\s+", " ", value)
    value = value.strip(" .")

    return value or "Без названия"


def format_date_ru(value) -> str:
    """
    Приводит дату к формату ДД.ММ.ГГГГ.
    """
    if value is None:
        return ""

    try:
        return value.strftime("%d.%m.%Y")
    except AttributeError:
        return str(value)


def resolve_template_path(template_path: str) -> Path:
    """
    Если путь в БД относительный — считаем его от папки 06_app.
    Если абсолютный — используем как есть.
    """
    path = Path(template_path)

    if path.is_absolute():
        return path

    return APP_DIR / path


def resolve_output_base_dir(base_output_dir: str) -> Path:
    """
    Если базовая папка относительная — считаем её от папки 06_app.
    Если абсолютная — используем как есть.
    """
    if not base_output_dir or not str(base_output_dir).strip():
        base_output_dir = "generated_documents"

    path = Path(str(base_output_dir).strip())

    if path.is_absolute():
        return path

    return APP_DIR / path


def path_for_db(path: Path) -> str:
    """
    Для путей внутри 06_app сохраняем относительный путь.
    Для внешних пользовательских папок — полный путь.
    """
    try:
        return str(path.resolve().relative_to(APP_DIR))
    except ValueError:
        return str(path.resolve())


def get_document_data(conn, document_number: str) -> dict:
    """
    Собирает данные документа, контрагента, подписантов, банка и активного шаблона.
    """
    query = text("""
        SELECT
            cd.document_id,
            cd.document_number,
            cd.document_date,

            dt.code AS document_type_code,
            dt.name AS document_type_name,

            le.legal_entity_id,
            le.short_name AS legal_entity_short_name,
            le.full_name AS legal_entity_full_name,

            cp.counterparty_id,
            cp.counterparty_type,
            cp.full_name AS counterparty_full_name,
            cp.short_name AS counterparty_short_name,
            cp.inn AS counterparty_inn,
            cp.kpp AS counterparty_kpp,
            cp.ogrn AS counterparty_ogrn,
            cp.legal_address AS counterparty_legal_address,
            cp.mailing_address AS counterparty_mailing_address,
            cp.phone_number AS counterparty_phone_number,
            cp.email_address AS counterparty_email_address,

            cps.position_nom AS counterparty_signatory_position_nom,
            cps.position_gen AS counterparty_signatory_position_gen,
            cps.full_name_nom AS counterparty_signatory_full_name_nom,
            cps.full_name_gen AS counterparty_signatory_full_name_gen,
            cps.initials_lastname AS counterparty_signatory_initials_lastname,
            cps.legal_basis_gen AS counterparty_signatory_legal_basis_gen,

            les.position_nom AS legal_entity_signatory_position_nom,
            les.position_gen AS legal_entity_signatory_position_gen,
            les.full_name_nom AS legal_entity_signatory_full_name_nom,
            les.full_name_gen AS legal_entity_signatory_full_name_gen,
            les.initials_lastname AS legal_entity_signatory_initials_lastname,
            les.legal_basis_gen AS legal_entity_signatory_legal_basis_gen,

            ba.account_number AS counterparty_account_number_1,
            ba.corr_account AS counterparty_corr_account_1,
            ba.bik AS counterparty_bik_1,
            ba.bank_name AS counterparty_bank_name_1,

            t.template_id,
            t.template_name,
            t.template_path

        FROM core.contract_documents cd
        JOIN core.contracts c
            ON c.contract_id = cd.contract_id
        JOIN core.legal_entities le
            ON le.legal_entity_id = c.legal_entity_id
        JOIN core.counterparties cp
            ON cp.counterparty_id = c.counterparty_id
        JOIN core.document_types dt
            ON dt.document_type_id = cd.document_type_id

        LEFT JOIN core.counterparty_signatories cps
            ON cps.signatory_id = cd.counterparty_signatory_id
        LEFT JOIN core.legal_entity_signatories les
            ON les.signatory_id = cd.legal_entity_signatory_id
        LEFT JOIN core.bank_accounts ba
            ON ba.counterparty_id = cp.counterparty_id
           AND ba.account_order = 1

        JOIN core.document_templates t
            ON t.legal_entity_id = le.legal_entity_id
           AND t.document_type_id = dt.document_type_id
           AND t.is_active = true

        WHERE cd.document_number = :document_number;
    """)

    with conn.session as session:
        result = session.execute(query, {"document_number": document_number})
        row = result.mappings().first()

    if row is None:
        raise ValueError(f"Документ {document_number} или активный шаблон для него не найден.")

    data = dict(row)

    data["document_date_ru"] = format_date_ru(data.get("document_date"))

    # Удобные короткие алиасы для шаблона.
    data["document_number"] = data.get("document_number") or ""
    data["document_date"] = data["document_date_ru"]

    return data


def build_docx_context(data: dict) -> dict:
    """
    Контекст для docxtpl. Все None заменяем на пустую строку,
    чтобы в документ не попадали None.
    """
    context = {}

    for key, value in data.items():
        if value is None:
            context[key] = ""
        else:
            context[key] = value

    return context


def build_output_paths(
    data: dict,
    output_format: str,
    base_output_dir: str
) -> tuple[Path, str]:
    """
    Формирует итоговый путь файла и имя файла.
    """
    document_type_code = data["document_type_code"]
    legal_entity_short_name = sanitize_path_part(data["legal_entity_short_name"])
    counterparty_short_name = sanitize_path_part(
        data.get("counterparty_short_name") or data.get("counterparty_full_name")
    )

    folder_name = DOCUMENT_TYPE_FOLDER.get(document_type_code, "Документы")
    file_prefix = DOCUMENT_FILE_PREFIX.get(document_type_code, "Документ")

    extension = ".pdf" if output_format.upper() == "PDF" else ".docx"

    generated_file_name = sanitize_path_part(
        f"{file_prefix} {data['document_number']} ({counterparty_short_name})"
    ) + extension

    output_base_dir = resolve_output_base_dir(base_output_dir)

    output_dir = (
        output_base_dir
        / legal_entity_short_name
        / folder_name
    )

    output_dir.mkdir(parents=True, exist_ok=True)

    final_path = output_dir / generated_file_name

    return final_path, generated_file_name


def register_generation_success(
    conn,
    document_id: int,
    template_id: int,
    username: str,
    generated_file_name: str,
    generated_file_path: str
) -> int:
    """
    Пишет SUCCESS в core.document_generation_log.
    """
    query = text("""
        INSERT INTO core.document_generation_log (
            document_id,
            template_id,
            generated_by,
            generated_at,
            generation_status_id,
            generated_file_name,
            generated_file_path,
            error_message
        )
        SELECT
            :document_id,
            :template_id,
            u.user_id,
            now(),
            gs.generation_status_id,
            :generated_file_name,
            :generated_file_path,
            NULL
        FROM core.users u
        CROSS JOIN core.generation_statuses gs
        WHERE u.username = :username
          AND gs.code = 'SUCCESS'
        RETURNING generation_id;
    """)

    with conn.session as session:
        result = session.execute(
            query,
            {
                "document_id": document_id,
                "template_id": template_id,
                "username": username,
                "generated_file_name": generated_file_name,
                "generated_file_path": generated_file_path,
            }
        )

        generation_id = result.scalar_one_or_none()

        if generation_id is None:
            session.rollback()
            raise ValueError(
                f"Не удалось записать лог генерации: пользователь {username} "
                "или статус SUCCESS не найден."
            )

        session.commit()

    return generation_id


def register_generation_error(
    conn,
    document_id: int,
    template_id: int,
    username: str,
    generated_file_name: str,
    generated_file_path: str,
    error_message: str
) -> int:
    """
    Пишет ERROR в core.document_generation_log.
    """
    query = text("""
        INSERT INTO core.document_generation_log (
            document_id,
            template_id,
            generated_by,
            generated_at,
            generation_status_id,
            generated_file_name,
            generated_file_path,
            error_message
        )
        SELECT
            :document_id,
            :template_id,
            u.user_id,
            now(),
            gs.generation_status_id,
            :generated_file_name,
            :generated_file_path,
            :error_message
        FROM core.users u
        CROSS JOIN core.generation_statuses gs
        WHERE u.username = :username
          AND gs.code = 'ERROR'
        RETURNING generation_id;
    """)

    with conn.session as session:
        result = session.execute(
            query,
            {
                "document_id": document_id,
                "template_id": template_id,
                "username": username,
                "generated_file_name": generated_file_name,
                "generated_file_path": generated_file_path,
                "error_message": error_message,
            }
        )

        generation_id = result.scalar_one_or_none()

        if generation_id is None:
            session.rollback()
            raise ValueError(
                f"Не удалось записать лог ошибки генерации: пользователь {username} "
                "или статус ERROR не найден."
            )

        session.commit()

    return generation_id


def generate_document_file(
    conn,
    document_number: str,
    username: str,
    output_format: str = "PDF",
    base_output_dir: str = "generated_documents"
) -> dict:
    """
    Генерирует DOCX или PDF по активному шаблону документа.

    PDF-режим:
    - создаём временный DOCX;
    - конвертируем через Microsoft Word / docx2pdf;
    - удаляем временный DOCX после успешной конвертации.
    """
    output_format = output_format.upper()

    if output_format not in {"PDF", "DOCX"}:
        raise ValueError("output_format должен быть PDF или DOCX.")

    data = get_document_data(conn, document_number)

    template_path = resolve_template_path(data["template_path"])

    if not template_path.exists():
        raise FileNotFoundError(f"Шаблон не найден: {template_path}")

    final_path, generated_file_name = build_output_paths(
        data=data,
        output_format=output_format,
        base_output_dir=base_output_dir
    )

    generated_file_path_for_db = path_for_db(final_path)

    temp_dir = APP_DIR / "temp"
    temp_dir.mkdir(parents=True, exist_ok=True)

    temp_docx_path = None

    try:
        doc = DocxTemplate(str(template_path))
        context = build_docx_context(data)
        doc.render(context)

        if output_format == "DOCX":
            doc.save(str(final_path))

        else:
            temp_docx_path = temp_dir / (
                "__temp_"
                + sanitize_path_part(data["document_number"])
                + ".docx"
            )

            doc.save(str(temp_docx_path))

            convert(str(temp_docx_path), str(final_path))

            if not final_path.exists():
                raise FileNotFoundError(
                    f"PDF не был создан после конвертации: {final_path}"
                )

            temp_docx_path.unlink(missing_ok=True)

        generation_id = register_generation_success(
            conn=conn,
            document_id=data["document_id"],
            template_id=data["template_id"],
            username=username,
            generated_file_name=generated_file_name,
            generated_file_path=generated_file_path_for_db
        )

        return {
            "generation_id": generation_id,
            "document_number": data["document_number"],
            "output_format": output_format,
            "generated_file_name": generated_file_name,
            "generated_file_path": generated_file_path_for_db,
            "template_path": path_for_db(template_path),
        }

    except Exception as exc:
        if temp_docx_path is not None and temp_docx_path.exists():
            temp_docx_path.unlink(missing_ok=True)

        try:
            register_generation_error(
                conn=conn,
                document_id=data["document_id"],
                template_id=data["template_id"],
                username=username,
                generated_file_name=generated_file_name,
                generated_file_path=generated_file_path_for_db,
                error_message=str(exc)
            )
        except Exception:
            pass

        raise