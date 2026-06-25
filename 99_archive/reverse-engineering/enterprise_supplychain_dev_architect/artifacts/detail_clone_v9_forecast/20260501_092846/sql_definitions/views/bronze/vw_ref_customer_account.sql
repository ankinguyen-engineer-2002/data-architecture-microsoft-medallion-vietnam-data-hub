-- Source: SupplyChain_Warehouse.bronze.vw_ref_customer_account
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW bronze.vw_ref_customer_account AS
SELECT
    TRIM(cmaCustomerNumber)                              AS id_customer,
    TRIM(cmaCustomerName)                                AS name_customer,
    TRIM(cmaDBAName)                                     AS name_dba,
    TRIM(cmaContact)                                     AS name_contact,
    TRIM(cmaPhone)                                       AS code_phone,
    TRIM(cmaFaxtn)                                       AS code_fax,
    TRIM(cmaEmail)                                       AS code_email,
    TRIM(cmaPrimaryTerritory)                             AS code_territory,
    CAST(cmaCreditTerritoryID AS VARCHAR(200))            AS id_credit_territory,
    CAST(cmaDeductTerritoryID AS VARCHAR(200))            AS id_deduct_territory,
    TRIM(cmaCustomerChannelID)                            AS code_customer_channel,
    TRIM(cmaCustomerClassCode)                            AS code_customer_class,
    CAST(cmaCreditLimitAmount AS DECIMAL(14,2))          AS amt_credit_limit,
    TRIM(cmaTermsCode)                                   AS code_terms,
    CAST(cmaTermsDays AS INT)                            AS num_terms_days,
    CAST(cmaPercentAvailableCredit AS DECIMAL(10,2))     AS pct_available_credit,
    TRIM(cmaCreditAuthorizationCode)                      AS code_credit_authorization,
    TRIM(cmaMinimumFreightCode)                           AS code_minimum_freight,
    CAST(cmaMinPreapprovalAmount AS DECIMAL(14,2))       AS amt_min_preapproval,
    TRIM(cmaCreditAddessCode)                             AS code_credit_address,
    CAST(cmaLateChargePercent AS DECIMAL(10,4))          AS pct_late_charge,
    CASE WHEN cmaCancelBackOrders = 1 THEN 1 ELSE 0 END AS is_cancel_backorders,
    CASE WHEN cmaAllowPartialShipment = 1 THEN 1 ELSE 0 END AS is_allow_partial_shipment,
    CASE WHEN cmaAllowAllowanceCredits = 1 THEN 1 ELSE 0 END AS is_allow_allowance_credits,
    CASE WHEN TRIM(cmaDocumentationHold) = 'Y' THEN 1 ELSE 0 END AS is_documentation_hold,
    CASE WHEN TRIM(cmaPARSByPurchaser) = 'Y' THEN 1 ELSE 0 END AS is_pars_by_purchaser,
    CASE WHEN TRIM(cma10DigitScheduleB) = 'Y' THEN 1 ELSE 0 END AS is_10_digit_schedule_b,
    CASE WHEN cmaInheritBlocking = 1 THEN 1 ELSE 0 END AS is_inherit_blocking,
    TRIM(cmaLanguageCode)                                AS code_language,
    CAST(cmaStatementCode AS INT)                        AS code_statement,
    TRIM(cmaItemCrossReferenceCode)                      AS code_item_cross_reference,
    TRIM(cmaCurrencyCode)                                AS code_currency,
    TRIM(cmaRFCTaxIdNumber)                              AS code_tax_id,
    CAST(cmaAppcd AS INT)                                AS code_app,
    TRIM(cmaHomestoreFacingWhse)                          AS code_homestore_facing_warehouse,
    TRIM(cmaTypeOfInsurance)                              AS code_insurance_type,
    CASE WHEN cmaInsExpirationDate < CAST('1900-01-01' AS DATETIME2(6)) THEN NULL
        ELSE CAST(cmaInsExpirationDate AS DATETIME2(6)) END AS dt_insurance_expiration,
    CAST(cmaInsCoverageRequested AS DECIMAL(14,2))       AS amt_insurance_coverage_requested,
    CAST(cmaInsCoverageApproved AS DECIMAL(14,2))        AS amt_insurance_coverage_approved,
    TRIM(cmaInsuranceStatus)                             AS code_insurance_status,
    TRIM(acrec)                                          AS code_record_status,
    CAST(cmaBillingAddressID AS INT)                      AS id_billing_address,
    TRIM(cmaMemo)                                         AS name_memo,
    CAST(cmaChgCustAr AS INT)                            AS num_change_customer_ar,
    CAST(cmaChgCust AS INT)                              AS num_change_customer,
    CAST(cmaChgCustExt AS INT)                           AS num_change_customer_ext,
    CAST(cmaCommAudit AS INT)                            AS num_commission_audit,
    CASE WHEN cmaTerritoryChangeDate < CAST('1900-01-01' AS DATETIME2(6)) THEN NULL
        ELSE CAST(cmaTerritoryChangeDate AS DATETIME2(6)) END AS dt_territory_change,
    CASE WHEN cmaLastStatusChangeDate < CAST('1900-01-01' AS DATETIME2(6)) THEN NULL
        ELSE CAST(cmaLastStatusChangeDate AS DATETIME2(6)) END AS dt_last_status_change,
    TRIM(usra)                                           AS name_created_by,
    CASE WHEN dtea < CAST('1900-01-01' AS DATETIME2(6)) THEN NULL
        ELSE CAST(dtea AS DATETIME2(6)) END              AS ts_created,
    TRIM(usrc)                                           AS name_modified_by,
    CASE WHEN dtec < CAST('1900-01-01' AS DATETIME2(6)) THEN NULL
        ELSE CAST(dtec AS DATETIME2(6)) END              AS ts_modified
FROM Enterprise_Lakehouse.Customers.AccountMaster
WHERE cmaCustomerNumber IS NOT NULL
