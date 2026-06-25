# ─── Cell 0 ───
TARGET_TABLE  = "ref_warehouse"
SOURCE_TABLE  = "SupplyChain_DW/DimAFIWarehouses"

COLUMN_SQL = """
    SELECT
        CAST(AFIWarehousesKey AS INT)            AS sk_warehouse,
        TRIM(WarehouseCode)                      AS code_warehouse,
        TRIM(IntransitWarehouse)                 AS code_intransit_warehouse,
        TRIM(ContainerDirectWarehouse)           AS code_container_direct,
        CAST(ControlledWarehouse AS INT)         AS is_controlled_warehouse,
        TRIM(WarehouseLocation)                  AS name_warehouse_location,
        TRIM(WarehouseOrderGroup)                AS name_warehouse_order_group,
        CAST(FinanceInventoryReportFlag AS INT)  AS is_finance_inventory_report
    FROM raw_source
    WHERE AFIWarehousesKey IS NOT NULL
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

