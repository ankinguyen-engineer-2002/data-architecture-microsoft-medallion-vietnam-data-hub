# ─── Cell 0 ───
TARGET_TABLE = "ref_customer_grouping"
SOURCE_TABLE = "Wholesale_ProductSourcing_AFI/CustomerGrouping"

COLUMN_SQL = """
SELECT DISTINCT
    UPPER(TRIM(CustomerGroup))                                  AS code_customer_group
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

