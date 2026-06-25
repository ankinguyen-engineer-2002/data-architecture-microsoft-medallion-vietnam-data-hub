# ─── Cell 0 ───
# Fabric notebook source
# Notebook: nb_utl_dq_setup
# Purpose: Create utl_dq_rules + utl_dq_results tables, seed BRZ rules
# Run once: to initialize DQ system

# ─── Cell 1 ───
# Cell 1 — Environment

# ─── Cell 2 ───
context = notebookutils.runtime.context
LAKEHOUSE = "SupplyChain_Lakehouse"

# ─── Cell 3 ───
# Cell 2 — Create utl_dq_rules table

# ─── Cell 4 ───
spark.sql(f"""
CREATE TABLE IF NOT EXISTS {LAKEHOUSE}.dbo.utl_dq_rules (
    rule_id        STRING      COMMENT 'Unique rule ID, e.g. BRZ_001',
    layer          STRING      COMMENT 'BRZ, REF, SLV, GLD',
    table_name     STRING      COMMENT 'Target table name',
    check_type     STRING      COMMENT 'uniqueness, row_count, freshness, null_percent',
    column_name    STRING      COMMENT 'Column(s) to check, * for table-level',
    check_params   STRING      COMMENT 'JSON config per check_type',
    severity       STRING      COMMENT 'CRITICAL or WARNING',
    is_active      INT         COMMENT '1 = active, 0 = disabled',
    description    STRING      COMMENT 'Human-readable description',
    created_at     TIMESTAMP   COMMENT 'Rule creation timestamp',
    updated_at     TIMESTAMP   COMMENT 'Last modified timestamp'
)
USING DELTA
COMMENT 'DQ rules configuration table — metadata-driven checks'
""")

print("utl_dq_rules table created/verified.")

# ─── Cell 5 ───
# Cell 3 — Create utl_dq_results table

# ─── Cell 6 ───
spark.sql(f"""
CREATE TABLE IF NOT EXISTS {LAKEHOUSE}.dbo.utl_dq_results (
    result_id         STRING      COMMENT 'UUID per check result',
    run_id            STRING      COMMENT 'UUID grouping one execution run',
    run_timestamp     TIMESTAMP   COMMENT 'When the check ran',
    layer             STRING      COMMENT 'BRZ, REF, SLV, GLD',
    table_name        STRING      COMMENT 'Table that was checked',
    rule_id           STRING      COMMENT 'FK to utl_dq_rules',
    check_type        STRING      COMMENT 'Denormalized check type',
    column_name       STRING      COMMENT 'Column checked',
    severity          STRING      COMMENT 'CRITICAL or WARNING',
    passed            BOOLEAN     COMMENT 'True = passed',
    actual_value      STRING      COMMENT 'Measured value',
    expected_value    STRING      COMMENT 'Threshold/expected',
    error_message     STRING      COMMENT 'NULL if passed',
    execution_time_ms LONG        COMMENT 'Check duration in ms',
    environment       STRING      COMMENT 'dev or prod'
)
USING DELTA
COMMENT 'DQ check results — append-only history for trending'
""")

print("utl_dq_results table created/verified.")

# ─── Cell 7 ───
# Cell 4 — Seed BRZ rules (28 rules for 7 tables)

# ─── Cell 8 ───
from datetime import datetime, timezone
from pyspark.sql import Row

NOW = datetime.now(timezone.utc)

brz_rules = [
    # --- brz_wholesale_codis_afi__codatan ---
    Row(rule_id="BRZ_001", layer="BRZ", table_name="brz_wholesale_codis_afi__codatan",
        check_type="uniqueness", column_name="*",
        check_params='{"columns":["id_order","num_item_sequence"]}',
        severity="CRITICAL", is_active=1,
        description="Composite PK must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_002", layer="BRZ", table_name="brz_wholesale_codis_afi__codatan",
        check_type="null_percent", column_name="*",
        check_params='{"columns":["id_order","num_item_sequence"],"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK columns must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_003", layer="BRZ", table_name="brz_wholesale_codis_afi__codatan",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_004", layer="BRZ", table_name="brz_wholesale_codis_afi__codatan",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),

    # --- brz_wholesale_codis_afi__comast ---
    Row(rule_id="BRZ_005", layer="BRZ", table_name="brz_wholesale_codis_afi__comast",
        check_type="uniqueness", column_name="id_order",
        check_params=None,
        severity="CRITICAL", is_active=1,
        description="PK id_order must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_006", layer="BRZ", table_name="brz_wholesale_codis_afi__comast",
        check_type="null_percent", column_name="id_order",
        check_params='{"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK id_order must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_007", layer="BRZ", table_name="brz_wholesale_codis_afi__comast",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_008", layer="BRZ", table_name="brz_wholesale_codis_afi__comast",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),

    # --- brz_supplychain_enh_1__demandforecastsnapshotdaily ---
    Row(rule_id="BRZ_009", layer="BRZ", table_name="brz_supplychain_enh_1__demandforecastsnapshotdaily",
        check_type="uniqueness", column_name="*",
        check_params='{"columns":["id_item_sku","code_warehouse","code_customer_group","num_fiscal_month","ts_snapshot"]}',
        severity="CRITICAL", is_active=1,
        description="Composite PK must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_010", layer="BRZ", table_name="brz_supplychain_enh_1__demandforecastsnapshotdaily",
        check_type="null_percent", column_name="*",
        check_params='{"columns":["id_item_sku","code_warehouse","code_customer_group","num_fiscal_month","ts_snapshot"],"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK columns must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_011", layer="BRZ", table_name="brz_supplychain_enh_1__demandforecastsnapshotdaily",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_012", layer="BRZ", table_name="brz_supplychain_enh_1__demandforecastsnapshotdaily",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),

    # --- brz_wholesale_codis_afi__extorit ---
    Row(rule_id="BRZ_013", layer="BRZ", table_name="brz_wholesale_codis_afi__extorit",
        check_type="uniqueness", column_name="*",
        check_params='{"columns":["id_order","num_item_sequence"]}',
        severity="CRITICAL", is_active=1,
        description="Composite PK must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_014", layer="BRZ", table_name="brz_wholesale_codis_afi__extorit",
        check_type="null_percent", column_name="*",
        check_params='{"columns":["id_order","num_item_sequence"],"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK columns must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_015", layer="BRZ", table_name="brz_wholesale_codis_afi__extorit",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_016", layer="BRZ", table_name="brz_wholesale_codis_afi__extorit",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),

    # --- brz_wholesale_codis_afi__extord ---
    Row(rule_id="BRZ_017", layer="BRZ", table_name="brz_wholesale_codis_afi__extord",
        check_type="uniqueness", column_name="id_order",
        check_params=None,
        severity="CRITICAL", is_active=1,
        description="PK id_order must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_018", layer="BRZ", table_name="brz_wholesale_codis_afi__extord",
        check_type="null_percent", column_name="id_order",
        check_params='{"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK id_order must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_019", layer="BRZ", table_name="brz_wholesale_codis_afi__extord",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_020", layer="BRZ", table_name="brz_wholesale_codis_afi__extord",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),

    # --- brz_saleshistory_afi__invoiceheader ---
    Row(rule_id="BRZ_021", layer="BRZ", table_name="brz_saleshistory_afi__invoiceheader",
        check_type="uniqueness", column_name="*",
        check_params='{"columns":["id_invoice","dt_invoice","dt_order","id_order"]}',
        severity="CRITICAL", is_active=1,
        description="Composite PK must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_022", layer="BRZ", table_name="brz_saleshistory_afi__invoiceheader",
        check_type="null_percent", column_name="*",
        check_params='{"columns":["id_invoice","dt_invoice","dt_order","id_order"],"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK columns must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_023", layer="BRZ", table_name="brz_saleshistory_afi__invoiceheader",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_024", layer="BRZ", table_name="brz_saleshistory_afi__invoiceheader",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),

    # --- brz_saleshistory_afi__invoicedetail ---
    Row(rule_id="BRZ_025", layer="BRZ", table_name="brz_saleshistory_afi__invoicedetail",
        check_type="uniqueness", column_name="id_invoice_extended",
        check_params=None,
        severity="CRITICAL", is_active=1,
        description="PK id_invoice_extended must be unique",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_026", layer="BRZ", table_name="brz_saleshistory_afi__invoicedetail",
        check_type="null_percent", column_name="id_invoice_extended",
        check_params='{"max_null_pct":0}',
        severity="WARNING", is_active=1,
        description="PK id_invoice_extended must not be null",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_027", layer="BRZ", table_name="brz_saleshistory_afi__invoicedetail",
        check_type="row_count", column_name="*",
        check_params='{"min":1}',
        severity="CRITICAL", is_active=1,
        description="Table must not be empty",
        created_at=NOW, updated_at=NOW),
    Row(rule_id="BRZ_028", layer="BRZ", table_name="brz_saleshistory_afi__invoicedetail",
        check_type="freshness", column_name="*",
        check_params='{"max_age_hours":48}',
        severity="CRITICAL", is_active=1,
        description="Data must be less than 48h old",
        created_at=NOW, updated_at=NOW),
]

# Clear existing BRZ rules to avoid duplicates on re-run
spark.sql(f"DELETE FROM {LAKEHOUSE}.dbo.utl_dq_rules WHERE layer = 'BRZ'")

rules_df = spark.createDataFrame(brz_rules)
rules_df.write.mode("append").format("delta").saveAsTable(
    f"{LAKEHOUSE}.dbo.utl_dq_rules"
)

print(f"Seeded {len(brz_rules)} BRZ rules into utl_dq_rules.")

# ─── Cell 9 ───
# Cell 5 — Verify

# ─── Cell 10 ───
print("\n--- utl_dq_rules ---")
spark.sql(f"""
    SELECT rule_id, table_name, check_type, severity
    FROM {LAKEHOUSE}.dbo.utl_dq_rules
    WHERE layer='BRZ'
    ORDER BY rule_id
""").show(30, truncate=False)

print(f"\n--- utl_dq_results ---")
print(f"Row count: {spark.table(f'{LAKEHOUSE}.dbo.utl_dq_results').count()}")

