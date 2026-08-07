#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "03_operations" / "orchestration"

REF_TABLES = [
    "Calendar",
    "CustomerAccount",
    "CustomerAccountGroup",
    "CustomerGrouping",
    "CustomerShippingLocation",
    "ForecastCycle",
    "ForecastHorizon",
    "ItemMaster",
    "OrderType",
    "Vendor",
    "Warehouse",
]


@dataclass(frozen=True)
class ProcSpec:
    rel_path: str
    database: str
    procedure: str
    targets: list[tuple[str, str]]
    mart: str
    wave_note: str


def exec_block(database: str, schema: str, table: str) -> str:
    if (schema, table) == ("ForecastHistory_Enh", "ForecastDemandMonthly"):
        return (
            "    EXEC [ETL_Framework].[DW_Developer].[usp_UpdateCuratedTableFromView_DateRange]\n"
            f"        '{database}', '{schema}', '{table}', 'Snapshot', 'Snapshot', -90;"
        )

    if (schema, table) == ("InventoryHistory_Enh", "PurchaseOrderSnapshotHistorical"):
        return (
            "    DECLARE @PurchaseOrderWindowStart date = DATEADD(day, -90, CAST(GETDATE() AS date));\n"
            "    DECLARE @PurchaseOrderSourceRows bigint;\n"
            "    DECLARE @PurchaseOrderDuplicateGroups bigint;\n"
            "    DECLARE @PurchaseOrderGuardMessage varchar(2047);\n\n"
            "    SELECT @PurchaseOrderSourceRows = COUNT_BIG(*)\n"
            "    FROM [InventoryHistory_Enh_Wrk].[v_PurchaseOrderSnapshotHistorical]\n"
            "    WHERE SnapshotDate >= @PurchaseOrderWindowStart;\n\n"
            "    IF @PurchaseOrderSourceRows = 0\n"
            "    BEGIN\n"
            "        SET @PurchaseOrderGuardMessage =\n"
            "            'PurchaseOrderSnapshotHistorical DateRange guard failed: target was not changed; '\n"
            "            + 'date key=SnapshotDate; window start=' + CONVERT(varchar(10), @PurchaseOrderWindowStart, 23)\n"
            "            + '; source rows=0; duplicate groups=not evaluated.';\n"
            "        THROW 51000, @PurchaseOrderGuardMessage, 1;\n"
            "    END;\n\n"
            "    SELECT @PurchaseOrderDuplicateGroups = COUNT_BIG(*)\n"
            "    FROM\n"
            "    (\n"
            "        SELECT SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode, DueDate, UnitCost\n"
            "        FROM [InventoryHistory_Enh_Wrk].[v_PurchaseOrderSnapshotHistorical]\n"
            "        WHERE SnapshotDate >= @PurchaseOrderWindowStart\n"
            "        GROUP BY SnapshotDate, ItemSku, WarehouseCode, VendorNumber, StatusCode, DueDate, UnitCost\n"
            "        HAVING COUNT_BIG(*) > 1\n"
            "    ) AS DuplicatePurchaseOrderKeys;\n\n"
            "    IF @PurchaseOrderDuplicateGroups > 0\n"
            "    BEGIN\n"
            "        SET @PurchaseOrderGuardMessage =\n"
            "            'PurchaseOrderSnapshotHistorical DateRange guard failed: target was not changed; '\n"
            "            + 'date key=SnapshotDate; window start=' + CONVERT(varchar(10), @PurchaseOrderWindowStart, 23)\n"
            "            + '; source rows=' + CONVERT(varchar(30), @PurchaseOrderSourceRows)\n"
            "            + '; duplicate groups=' + CONVERT(varchar(30), @PurchaseOrderDuplicateGroups) + '.';\n"
            "        THROW 51001, @PurchaseOrderGuardMessage, 1;\n"
            "    END;\n\n"
            "    EXEC [ETL_Framework].[DW_Developer].[usp_UpdateCuratedTableFromView_DateRange]\n"
            f"        '{database}',\n"
            f"        '{schema}',\n"
            f"        '{table}',\n"
            "        'SnapshotDate',\n"
            "        'SnapshotDate',\n"
            "        -90;"
        )

    if (schema, table) == ("InventoryHistory_Enh", "ForecastSnapshotWeekly"):
        return (
            "    IF NOT EXISTS\n"
            "    (\n"
            "        SELECT TOP (1) 1\n"
            "        FROM [InventoryHistory_Enh_Wrk].[v_ForecastSnapshotWeekly]\n"
            "        WHERE SnapshotDate >= DATEADD(day, -90, CAST(GETDATE() AS date))\n"
            "    )\n"
            "    BEGIN\n"
            "        THROW 51002,\n"
            "            'ForecastSnapshotWeekly DateRange guard failed: target was not changed because the source 90-day window is empty.',\n"
            "            1;\n"
            "    END;\n\n"
            "    EXEC [ETL_Framework].[DW_Developer].[usp_UpdateCuratedTableFromView_DateRange]\n"
            f"        '{database}', '{schema}', '{table}', 'SnapshotDate', 'SnapshotDate', -90;"
        )

    if (schema, table) == ("InventoryHistory_Enh", "SupplyPlanDetail"):
        return (
            "    EXEC [ETL_Framework].[DW_Developer].[usp_UpdateCuratedTableFromView_DateRange]\n"
            f"        '{database}', '{schema}', '{table}', 'SnapshotDate', 'SnapshotDate', -90;"
        )

    return (
        "    EXEC [ETL_Framework].[DW_Developer].[usp_RefreshCuratedTableFromView]\n"
        f"        '{database}', '{schema}', '{table}';"
    )


def prelude(spec: ProcSpec) -> str:
    if spec.procedure != "Usp_Refresh_ForecastAccuracy_Silver_W02":
        return ""

    return (
        "    DECLARE @ForecastWindowStart date = DATEADD(day, -90, CAST(GETDATE() AS date));\n\n"
        "    IF NOT EXISTS\n"
        "    (\n"
        "        SELECT TOP (1) 1\n"
        "        FROM [ForecastHistory_Enh_Wrk].[v_ForecastDemandMonthly]\n"
        "        WHERE Snapshot >= @ForecastWindowStart\n"
        "    )\n"
        "    BEGIN\n"
        "        THROW 51010,\n"
        "            'ForecastDemandMonthly DateRange guard failed: target was not changed because the source 90-day window is empty.',\n"
        "            1;\n"
        "    END;\n\n"
    )


def render(spec: ProcSpec) -> str:
    blocks = "\n\n".join(exec_block(spec.database, schema, table) for schema, table in spec.targets)
    procedure_prelude = prelude(spec)
    return f"""-- Target database: {spec.database}
-- Mart: {spec.mart}
-- Wave order: {spec.wave_note}
-- Generated by 03_operations/tools/generate_wave_sps.py
CREATE OR ALTER PROCEDURE [dbo].[{spec.procedure}]
AS
BEGIN
    SET NOCOUNT ON;

{procedure_prelude}{blocks}
END;
"""


def specs() -> list[ProcSpec]:
    return [
        ProcSpec(
            rel_path="shared/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_Shared_ReferenceMaster.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_Shared_ReferenceMaster",
            targets=[("ReferenceMaster_Enh", name) for name in REF_TABLES],
            mart="shared",
            wave_note="Shared W01 ReferenceMaster prerequisites",
        ),
        ProcSpec(
            rel_path="shared/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_Shared_Staging.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_Shared_Staging",
            targets=[("Staging", "DemandForecastSnapshotDaily")],
            mart="shared",
            wave_note="Shared W01 Staging prerequisites",
        ),
        ProcSpec(
            rel_path="forecast_accuracy/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver_W01.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_ForecastAccuracy_Silver_W01",
            targets=[
                ("SalesHistory_Enh", "InvoiceDetailLineLevel"),
                ("OpenOrderHistory_Enh", "OpenOrderLineLevel"),
            ],
            mart="forecast_accuracy",
            wave_note="Silver W01 line-level tables",
        ),
        ProcSpec(
            rel_path="forecast_accuracy/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver_W02.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_ForecastAccuracy_Silver_W02",
            targets=[
                ("SalesHistory_Enh", "ActualDemandMonthly"),
                ("SalesHistory_Enh", "ActualDemandWeekly"),
                ("SalesHistory_Enh", "InvoiceWeekly"),
                ("ForecastHistory_Enh", "ForecastDemandMonthly"),
                ("OpenOrderHistory_Enh", "OpenOrderMonthly"),
            ],
            mart="forecast_accuracy",
            wave_note="Silver W02 aggregate tables",
        ),
        ProcSpec(
            rel_path="forecast_accuracy/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver_W03.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_ForecastAccuracy_Silver_W03",
            targets=[("ForecastHistory_Enh", "NaiveForecastMonthly")],
            mart="forecast_accuracy",
            wave_note="Silver W03 derived forecast table",
        ),
        ProcSpec(
            rel_path="inventory_health/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver_W01.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_InventoryHealth_Silver_W01",
            targets=[
                ("InventoryHistory_Enh", "InventorySnapshotWeekly"),
                ("InventoryHistory_Enh", "AtpWeekEnding"),
            ],
            mart="inventory_health",
            wave_note="Silver W01 inventory source transformations",
        ),
        ProcSpec(
            rel_path="inventory_health/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver_W02.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_InventoryHealth_Silver_W02",
            targets=[
                ("InventoryHistory_Enh", "PurchaseOrderSnapshotHistorical"),
                ("InventoryHistory_Enh", "ManufacturingOrderSnapshotDaily"),
                ("InventoryHistory_Enh", "HoldingTransferSnapshotDaily"),
                ("InventoryHistory_Enh", "ForecastSnapshotWeekly"),
                ("InventoryHistory_Enh", "SupplyPlanDetail"),
                ("InventoryHistory_Enh", "ItemBalanceHistorical_WithInTransit"),
                ("InventoryHistory_Enh", "SafetyStockHelper"),
                ("SalesHistory_Enh", "InvoiceDetailLineLevel"),
            ],
            mart="inventory_health",
            wave_note="Silver W02 derived source tables",
        ),
        ProcSpec(
            rel_path="inventory_health/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver_W03.sql",
            database="SupplyChain_Processing_Warehouse",
            procedure="Usp_Refresh_InventoryHealth_Silver_W03",
            targets=[
                ("InventoryHistory_Enh", "AFIStatusSnapshotWeekly"),
                ("InventoryHistory_Enh", "AwdHelper"),
                ("InventoryHistory_Enh", "LastInvoiceWeekly"),
                ("InventoryHistory_Enh", "Cogs52WWeekly"),
            ],
            mart="inventory_health",
            wave_note="Silver W03 dependent helper tables",
        ),
    ]


def main() -> int:
    for spec in specs():
        path = OUT / spec.rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render(spec), encoding="utf-8")
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
