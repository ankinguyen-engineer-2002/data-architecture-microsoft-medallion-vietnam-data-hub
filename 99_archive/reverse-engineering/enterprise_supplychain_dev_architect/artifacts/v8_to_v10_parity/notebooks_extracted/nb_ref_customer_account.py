# ─── Cell 0 ───
TARGET_TABLE = "ref_customer_account"
SOURCE_TABLE = "Customers/AccountMaster"

COLUMN_SQL = """
    SELECT
        -- Keys & Identifiers
        TRIM(cmaCustomerNumber)                              AS id_customer,
        TRIM(cmaCustomerName)                                AS name_customer,
        TRIM(cmaDBAName)                                     AS name_dba,

        -- Contact
        TRIM(cmaContact)                                     AS name_contact,
        TRIM(cmaPhone)                                       AS code_phone,
        TRIM(cmaFaxtn)                                       AS code_fax,
        TRIM(cmaEmail)                                       AS code_email,

        -- Territory & Sales
        TRIM(cmaPrimaryTerritory)                             AS code_territory,
        TRIM(cmaCreditTerritoryID)                            AS id_credit_territory,
        TRIM(cmaDeductTerritoryID)                            AS id_deduct_territory,
        TRIM(cmaCustomerChannelID)                            AS code_customer_channel,
        TRIM(cmaCustomerClassCode)                            AS code_customer_class,

        -- Credit & Terms
        CAST(cmaCreditLimitAmount AS DECIMAL(14,2))          AS amt_credit_limit,
        TRIM(cmaTermsCode)                                   AS code_terms,
        CAST(cmaTermsDays AS INT)                            AS num_terms_days,
        CAST(cmaPercentAvailableCredit AS DECIMAL(10,2))     AS pct_available_credit,
        TRIM(cmaCreditAuthorizationCode)                      AS code_credit_authorization,
        TRIM(cmaMinimumFreightCode)                           AS code_minimum_freight,
        CAST(cmaMinPreapprovalAmount AS DECIMAL(14,2))       AS amt_min_preapproval,
        TRIM(cmaCreditAddessCode)                             AS code_credit_address,
        CAST(cmaLateChargePercent AS DECIMAL(10,4))          AS pct_late_charge,

        -- Flags
        CASE WHEN TRIM(cmaCancelBackOrders) = '1' THEN true ELSE false END AS is_cancel_backorders,
        CASE WHEN TRIM(cmaAllowPartialShipment) = '1' THEN true ELSE false END AS is_allow_partial_shipment,
        CASE WHEN TRIM(cmaAllowAllowanceCredits) = '1' THEN true ELSE false END AS is_allow_allowance_credits,
        CASE WHEN TRIM(cmaDocumentationHold) = 'Y' THEN true ELSE false END AS is_documentation_hold,
        CASE WHEN TRIM(cmaPARSByPurchaser) = 'Y' THEN true ELSE false END AS is_pars_by_purchaser,
        CASE WHEN TRIM(cma10DigitScheduleB) = 'Y' THEN true ELSE false END AS is_10_digit_schedule_b,
        CASE WHEN TRIM(cmaInheritBlocking) = '1' THEN true ELSE false END AS is_inherit_blocking,

        -- Codes
        TRIM(cmaLanguageCode)                                AS code_language,
        TRIM(cmaStatementCode)                               AS code_statement,
        TRIM(cmaItemCrossReferenceCode)                      AS code_item_cross_reference,
        TRIM(cmaCurrencyCode)                                AS code_currency,
        TRIM(cmaRFCTaxIdNumber)                              AS code_tax_id,
        TRIM(cmaAppcd)                                       AS code_app,
        TRIM(cmaHomestoreFacingWhse)                          AS code_homestore_facing_warehouse,

        -- Insurance
        TRIM(cmaTypeOfInsurance)                              AS code_insurance_type,
        CASE WHEN CAST(cmaInsExpirationDate AS TIMESTAMP) < TIMESTAMP '1900-01-01T00:00:01' THEN NULL
        ELSE CAST(cmaInsExpirationDate AS TIMESTAMP) END   AS dt_insurance_expiration,
        CAST(cmaInsCoverageRequested AS DECIMAL(14,2))       AS amt_insurance_coverage_requested,
        CAST(cmaInsCoverageApproved AS DECIMAL(14,2))        AS amt_insurance_coverage_approved,
        TRIM(cmaInsuranceStatus)                             AS code_insurance_status,

        -- Status & Record
        TRIM(acrec)                                          AS code_record_status,
        TRIM(cmaBillingAddressID)                             AS id_billing_address,

        -- Memo / Notes
        TRIM(cmaMemo)                                         AS name_memo,

        -- Audit flags
        CAST(cmaChgCustAr AS INT)                            AS num_change_customer_ar,
        CAST(cmaChgCust AS INT)                              AS num_change_customer,
        CAST(cmaChgCustExt AS INT)                           AS num_change_customer_ext,
        CAST(cmaCommAudit AS INT)                            AS num_commission_audit,

        -- Dates
        CASE WHEN CAST(cmaTerritoryChangeDate AS TIMESTAMP) < TIMESTAMP '1900-01-01T00:00:01' THEN NULL
        ELSE CAST(cmaTerritoryChangeDate AS TIMESTAMP) END  AS dt_territory_change,
        CASE WHEN CAST(cmaLastStatusChangeDate AS TIMESTAMP) < TIMESTAMP '1900-01-01T00:00:01' THEN NULL
        ELSE CAST(cmaLastStatusChangeDate AS TIMESTAMP) END AS dt_last_status_change,

        -- Source audit
        TRIM(usra)                                           AS name_created_by,
        CASE WHEN CAST(dtea AS TIMESTAMP) < TIMESTAMP '1900-01-01T00:00:01' THEN NULL
        ELSE CAST(dtea AS TIMESTAMP) END                    AS ts_created,
        TRIM(usrc)                                           AS name_modified_by,
        CASE WHEN CAST(dtec AS TIMESTAMP) < TIMESTAMP '1900-01-01T00:00:01' THEN NULL
        ELSE CAST(dtec AS TIMESTAMP) END                    AS ts_modified

    FROM raw_source
    WHERE cmaCustomerNumber IS NOT NULL
"""

# ─── Cell 1 ───
notebookutils.notebook.run(
    "brz_engine",
    7200,
    {
        "TARGET_TABLE": TARGET_TABLE,
        "SOURCE_TABLE": SOURCE_TABLE,
        "COLUMN_SQL":   COLUMN_SQL
    }
)

