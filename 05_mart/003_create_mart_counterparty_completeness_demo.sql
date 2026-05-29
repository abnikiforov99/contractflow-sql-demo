-- 003_create_mart_counterparty_completeness.sql
-- ContractFlow SQL
-- Витрина полноты реквизитов контрагентов

CREATE OR REPLACE VIEW mart.counterparty_completeness AS

WITH active_signatories AS (
    SELECT
        counterparty_id,
        COUNT(*) AS active_signatory_count
    FROM core.counterparty_signatories
    WHERE is_active = true
    GROUP BY counterparty_id
),

bank_accounts AS (
    SELECT
        counterparty_id,
        COUNT(*) AS bank_account_count
    FROM core.bank_accounts
    GROUP BY counterparty_id
),

ie_details AS (
    SELECT
        counterparty_id,
        passport_data
    FROM core.individual_entrepreneur_details
)

SELECT
    cp.counterparty_id,
    cp.counterparty_type,
    cp.legal_form,
    cp.full_name,
    cp.short_name,
    cp.inn,
    cp.kpp,
    cp.ogrn,
    cp.legal_address,
    cp.mailing_address,
    cp.phone_number,
    cp.email_address,

    COALESCE(s.active_signatory_count, 0) AS active_signatory_count,
    COALESCE(b.bank_account_count, 0) AS bank_account_count,

    CASE
        WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
            THEN ie.passport_data
        ELSE NULL
    END AS passport_data,

    /* =========================
       FIELD CHECKS
       ========================= */

    CASE
        WHEN NULLIF(BTRIM(cp.full_name), '') IS NOT NULL THEN true
        ELSE false
    END AS has_full_name,

    CASE
        WHEN cp.counterparty_type = 'LEGAL_ENTITY'
             AND cp.inn ~ '^[0-9]{10}$'
            THEN true
        WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
             AND cp.inn ~ '^[0-9]{12}$'
            THEN true
        ELSE false
    END AS has_valid_inn,

    CASE
        WHEN cp.counterparty_type = 'LEGAL_ENTITY'
             AND cp.kpp ~ '^[0-9]{9}$'
            THEN true
        WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
             AND cp.kpp IS NULL
            THEN true
        ELSE false
    END AS has_valid_kpp,

    CASE
        WHEN cp.counterparty_type = 'LEGAL_ENTITY'
             AND cp.ogrn ~ '^[0-9]{13}$'
            THEN true
        WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
             AND cp.ogrn ~ '^[0-9]{15}$'
            THEN true
        ELSE false
    END AS has_valid_ogrn,

    CASE
        WHEN NULLIF(BTRIM(cp.legal_address), '') IS NOT NULL THEN true
        ELSE false
    END AS has_legal_address,

    CASE
        WHEN NULLIF(BTRIM(cp.mailing_address), '') IS NOT NULL THEN true
        ELSE false
    END AS has_mailing_address,

    CASE
        WHEN COALESCE(s.active_signatory_count, 0) > 0 THEN true
        ELSE false
    END AS has_active_signatory,

    CASE
        WHEN COALESCE(b.bank_account_count, 0) > 0 THEN true
        ELSE false
    END AS has_bank_account,

    CASE
        WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
             AND NULLIF(BTRIM(ie.passport_data), '') IS NOT NULL
            THEN true
        WHEN cp.counterparty_type = 'LEGAL_ENTITY'
            THEN true
        ELSE false
    END AS has_required_passport_data,

    CASE
        WHEN NULLIF(BTRIM(cp.email_address), '') IS NOT NULL THEN true
        ELSE false
    END AS has_email,

    CASE
        WHEN NULLIF(BTRIM(cp.phone_number), '') IS NOT NULL THEN true
        ELSE false
    END AS has_phone,

    /* =========================
       RESULT
       ========================= */

    array_remove(ARRAY[
        CASE WHEN NULLIF(BTRIM(cp.full_name), '') IS NULL THEN 'full_name' END,

        CASE
            WHEN cp.counterparty_type = 'LEGAL_ENTITY'
                 AND cp.inn !~ '^[0-9]{10}$'
                THEN 'inn'
            WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
                 AND cp.inn !~ '^[0-9]{12}$'
                THEN 'inn'
        END,

        CASE
            WHEN cp.counterparty_type = 'LEGAL_ENTITY'
                 AND (cp.kpp IS NULL OR cp.kpp !~ '^[0-9]{9}$')
                THEN 'kpp'
        END,

        CASE
            WHEN cp.counterparty_type = 'LEGAL_ENTITY'
                 AND (cp.ogrn IS NULL OR cp.ogrn !~ '^[0-9]{13}$')
                THEN 'ogrn'
            WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
                 AND (cp.ogrn IS NULL OR cp.ogrn !~ '^[0-9]{15}$')
                THEN 'ogrnip'
        END,

        CASE WHEN NULLIF(BTRIM(cp.legal_address), '') IS NULL THEN 'legal_address' END,
        CASE WHEN NULLIF(BTRIM(cp.mailing_address), '') IS NULL THEN 'mailing_address' END,
        CASE WHEN COALESCE(s.active_signatory_count, 0) = 0 THEN 'active_signatory' END,
        CASE WHEN COALESCE(b.bank_account_count, 0) = 0 THEN 'bank_account' END,

        CASE
            WHEN cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
                 AND NULLIF(BTRIM(ie.passport_data), '') IS NULL
                THEN 'passport_data'
        END
    ], NULL) AS missing_required_fields,

    CASE
        WHEN
            NULLIF(BTRIM(cp.full_name), '') IS NOT NULL
            AND (
                (cp.counterparty_type = 'LEGAL_ENTITY' AND cp.inn ~ '^[0-9]{10}$')
                OR
                (cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR' AND cp.inn ~ '^[0-9]{12}$')
            )
            AND (
                (cp.counterparty_type = 'LEGAL_ENTITY' AND cp.kpp ~ '^[0-9]{9}$')
                OR
                (cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR' AND cp.kpp IS NULL)
            )
            AND (
                (cp.counterparty_type = 'LEGAL_ENTITY' AND cp.ogrn ~ '^[0-9]{13}$')
                OR
                (cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR' AND cp.ogrn ~ '^[0-9]{15}$')
            )
            AND NULLIF(BTRIM(cp.legal_address), '') IS NOT NULL
            AND NULLIF(BTRIM(cp.mailing_address), '') IS NOT NULL
            AND COALESCE(s.active_signatory_count, 0) > 0
            AND COALESCE(b.bank_account_count, 0) > 0
            AND (
                cp.counterparty_type = 'LEGAL_ENTITY'
                OR
                (
                    cp.counterparty_type = 'INDIVIDUAL_ENTREPRENEUR'
                    AND NULLIF(BTRIM(ie.passport_data), '') IS NOT NULL
                )
            )
        THEN true
        ELSE false
    END AS is_ready_for_contract,

    now() AS mart_updated_at

FROM core.counterparties cp
LEFT JOIN active_signatories s
    ON s.counterparty_id = cp.counterparty_id
LEFT JOIN bank_accounts b
    ON b.counterparty_id = cp.counterparty_id
LEFT JOIN ie_details ie
    ON ie.counterparty_id = cp.counterparty_id;


--ПРОВЕРКИ

SELECT *
FROM mart.counterparty_completeness
ORDER BY counterparty_id;

SELECT
    counterparty_id,
    counterparty_type,
    short_name,
    inn,
    active_signatory_count,
    bank_account_count,
    missing_required_fields,
    is_ready_for_contract
FROM mart.counterparty_completeness
ORDER BY counterparty_id;