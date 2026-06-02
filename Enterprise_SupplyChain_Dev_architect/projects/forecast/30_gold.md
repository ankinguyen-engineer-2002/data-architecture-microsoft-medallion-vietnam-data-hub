# 30 — Gold Layer

> Scanned: 2026-05-06 · Updated 2026-06-01 after shared dimension consolidation and live semantic smoke.
> **Warehouse:** `SupplyChain_Gold_Warehouse` (`98e2a911-5af9-442e-9cc8-5d8dadb8b762`)
> **Schema:** `ForecastAccuracy_DW`
> **Role:** Dedicated serving boundary for Direct Lake semantic model.

## Summary

| Type | Count | Total rows |
|------|------:|-----------:|
| Fact tables | 2 | 254,267,610 |
| Forecast mart-specific dimension tables | 2 active + 2 inactive legacy physical dims | 35,625 active mart-specific rows |
| Shared dimension tables | 3 | 405,487 |
| Views (1-to-1 with tables) | 7 | — |

> ETL DDL for all 7 Gold views: see [`etl/gold_views.sql`](etl/gold_views.sql).

---

## Fact Tables

### `FactForecastActual` — 138,509,914 rows

UNION ALL of 3 demand sources into a unified fact for forecast accuracy reporting.

| Column | Type | Source / Logic |
|--------|------|---------------|
| `ItemSKU` | VARCHAR | from each source |
| `WarehouseCode` | VARCHAR | from each source |
| `CustomerGroupCode` | VARCHAR | from each source |
| `FSCMonthFirst` | DATE | from each source |
| `FSCMonthLast` | DATE | from each source |
| `HorizonCode` | VARCHAR(20) | `'Actual demand'` (literal) / `HorizonCode` (forecast) / `'Naive forecast'` (literal) |
| `StatusCode` | VARCHAR | from each source |
| `VersionName` | VARCHAR | `VersionName` (actual) / `VersionCode` (forecast) / `VersionName` (naive) |
| `Qty` | FLOAT | `CAST(QtyDemand AS FLOAT)` (actual) / `CAST(QtyForecast AS FLOAT)` (forecast) / `CAST(QtyDemand AS FLOAT)` (naive) |
| `LoadDT` | DATETIME2(6) | `CAST(GETUTCDATE() AS DATETIME2(6))` |

**Source SQL:**
```sql
CREATE VIEW ForecastAccuracy_DW.v_FactForecastActual AS
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
       CAST('Actual demand' AS VARCHAR(20)) AS HorizonCode, StatusCode, VersionName,
       CAST(QtyDemand AS FLOAT) AS Qty,
       CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.SalesHistory_Enh.ActualDemandMonthly
UNION ALL
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
       HorizonCode, StatusCode, VersionCode, CAST(QtyForecast AS FLOAT),
       CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly
UNION ALL
SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst, FSCMonthLast,
       CAST('Naive forecast' AS VARCHAR(20)), StatusCode, VersionName,
       CAST(QtyDemand AS FLOAT),
       CAST(GETUTCDATE() AS DATETIME2(6))
FROM SupplyChain_Processing_Warehouse.ForecastHistory_Enh.NaiveForecastMonthly;
```

### `FactForecastKpi` — 115,757,696 rows

Computed KPI fact derived from joining `FactForecastActual` against itself (Forecast vs Actual) with horizon spine + 7 derived error metrics.

**Derived KPI columns (7 added vs v8):**
- `QtyNaiveFcstError` — naive forecast error
- `QtyAbsNaiveFcstError` — absolute naive error
- `QtySquaredFcstError` — squared error
- `QtySquaredNaiveFcstError` — squared naive error
- `ValidObsFlag` — flag for valid observation (forecast + actual both present)
- `ValidActualNonzeroFlag` — flag for non-zero actual demand
- `AbsPctError` — absolute percent error (MAPE component)

Spine joins via CROSS JOIN to `DimForecastHorizon` for monthly horizon expansion.

> Full DDL: [`etl/gold_views.sql`](etl/gold_views.sql) — search for `v_FactForecastKpi`.

---

## Dimension Tables

| Table | Rows | Cols | Source | Notes |
|-------|-----:|-----:|--------------------------------------|-------|
| `DimCalendar` | 21,551 | 75 | `Shared_DW.DimCalendar` | Shared calendar used by forecast + inventory semantic models. |
| `DimCustomerGrouping` | 35,617 | 3 | `ReferenceMaster_Enh.CustomerGrouping` | Mart-specific customer group mapping. |
| `DimForecastHorizon` | 8 | 3 | `ReferenceMaster_Enh.ForecastHorizon` | +`Rank` col for sort order vs v8. |
| `DimProduct` | 383,883 | 218 | `Shared_DW.DimProduct` via `ForecastAccuracy_DW.v_DimProduct` | Shared canonical product dim. The old physical `ForecastAccuracy_DW.DimProduct` has 381,163 rows / 207 cols and is inactive/stale. |
| `DimWarehouse` | 53 | 20 | `Shared_DW.DimWarehouse` | Shared warehouse master; display label contract restored. |

### 2026-06-01 Shared `DimProduct` Contract

`ForecastAccuracy_DW.v_DimProduct` now reads `Shared_DW.DimProduct`, which is built from:

```text
Enterprise_Lakehouse.MasterData_DW.DimItemMaster
  + Enterprise_Lakehouse.Purchasing_AFI.VendorMaster
  + Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT
```

The shared table has 383,883 rows / 218 columns. It preserves forecast compatibility while also carrying Inventory Health fields such as `Cubes`, `FOBArcPrice`, and `UnavailableFlag`.

### 2026-05-29 Shared `DimWarehouse` Display Contract

`DimWarehouse` is now served from `Shared_DW.DimWarehouse` for Forecast Accuracy
and Inventory Health. `WarehouseLocation` is the report display label and is
derived from `WarehouseOrderGroup` with `WarehouseCode` fallback. The D/W source
type is preserved separately as `WarehouseType`.

Operational fix applied 2026-05-29:
- Rebuilt `ReferenceMaster_Enh.Warehouse` from `ReferenceMaster_Enh.v_Warehouse`.
- Rebuilt `Shared_DW.DimWarehouse` from `Shared_DW.v_DimWarehouse`.
- Refreshed both Forecast and Inventory semantic models successfully.
- Forecast DAX smoke confirmed `DimWarehouse[WarehouseLocation]` groups by
  `ARCADIA`, `ECRU`, `LEESPORT`, `ADVANCE`, `REDLANDS`, `SALTILLO`, etc.,
  instead of collapsing to `D`.

**Pattern (all dims):**
```sql
CREATE VIEW ForecastAccuracy_DW.v_Dim<Entity> AS
SELECT *, CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.<Schema>.<Table>;
```

---

## Gold Refresh Pipeline

`pl_sc_gold` (`50ff6263-659d-4b09-9e45-b42a3434e093`):
- Reads `Meta.AssetRegistry` for `canonical_layer = 'Gold'` AND `is_active = 1`
- ForEach Gold asset → dynamic `DROP TABLE IF EXISTS` + `CREATE TABLE AS SELECT * FROM <view>`
- Cross-DB write via Pipeline (SP cannot write across WH)

Each Gold asset declared in registry as:

```sql
INSERT INTO Meta.AssetRegistry (
    asset_id, canonical_layer, access_mode,
    physical_schema, physical_object, load_type, frequency, cron_expression,
    project, is_active, source_objects, legacy_view_name
) VALUES (
    'gold::FactForecastActual', 'Gold', 'GoldPublish',
    'ForecastAccuracy_DW', 'FactForecastActual', 'overwrite', 'daily', '0 2 * * *',
    'forecast_accuracy', 1,
    '["SalesHistory_Enh.ActualDemandMonthly","ForecastHistory_Enh.ForecastDemandMonthly","ForecastHistory_Enh.NaiveForecastMonthly"]',
    'ForecastAccuracy_DW.v_FactForecastActual'
);
```

---

## Direct Lake Semantic Source

The semantic model `sc_forecast_control_tower` reads physical tables (NOT views) via Direct Lake mode. See [50_semantic.md](50_semantic.md) for model details.

7 Direct Lake edges live in `Meta.LineageEdge`:
- `ForecastAccuracy_DW.{DimCalendar | DimCustomerGrouping | DimForecastHorizon | DimProduct | DimWarehouse | FactForecastActual | FactForecastKpi}` → `SemanticModel.sc_forecast_control_tower` (edge_type = `directLake`)
