# ─── Cell 0 ───
TARGET_TABLE = "ref_customer_account_group"
SOURCE_TABLE = "Wholesale_ProductSourcing_AFI/CustomerGrouping"

COLUMN_SQL = """
SELECT
    TRIM(CAST(CustomerNumber AS STRING))                 AS id_customer,
    UPPER(TRIM(CustomerGroup))                           AS code_customer_group,
    TRIM(CustomerGroupLevel3)                            AS name_customer_group_level3,
    TRIM(BusinessTypeCode)                               AS name_business_type,
    TRIM(usra)                                           AS name_created_by,
    CAST(dtea AS TIMESTAMP)                              AS ts_created,
    TRIM(usrc)                                           AS name_modified_by,
    CAST(dtec AS TIMESTAMP)                              AS ts_modified

FROM raw_source
WHERE CustomerNumber IS NOT NULL
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

