# 50 — Semantic Model

> **Status (updated 2026-06-01):** LIVE post-DA Mart B refactor and shared dimension consolidation. TMDL + DAX measures simplified. DirectLake binding points to `SupplyChain_Gold_Warehouse`; facts/helpers use `InventoryHealth_DW`, while `DimCalendar`, `DimProduct`, and `DimWarehouse` use `Shared_DW`.
>
> **2026-05-22 change**: Removed `DimRuleVersion` table + 2 relationships + simplified `Active Rule Version` DAX measure (hardcoded "InventoryHealth_BRD_v1"). Versioning approach: when BRD updates → create new semantic model `sc_inventory_health_control_tower_v2` rather than versioning via dim. RuleVersionKey columns also removed from both Fact tables.
>
> **2026-05-28 semantic fix**: Deployed `definition/relationships.tmdl` to live semantic model after QC found the live model had tables but no active relationships. DAX smoke test now confirms `DimWarehouse` filters both health and risk facts.
>
> **2026-06-01 live smoke test after DA-first Gold rebuild**: `FactInventoryHealthSnapshot` = 2,739,398 rows; `FactInventoryRiskForward` = 3,778,995 rows; `CogsRollingHelper` = 3,092,173 rows; `FactInventoryRiskForward` no longer contains `ATPQty` / `ATPInStockFlag`.
>
> **2026-06-15 drift note:** this page reflects the earlier dedicated inventory semantic phase. The current live v10 workspace audit shows no separate deployed `sc_inventory_health_control_tower` item in the workspace item list; current semantic/report state is documented in [../live_audit_2026-06-15_v10_core_stack.md](../live_audit_2026-06-15_v10_core_stack.md).
>
> **2026-06-15 verified current state (v10):** Inventory semantic is currently embedded in the workspace semantic model **`sc_control_tower`** (DirectLake on `SupplyChain_Gold_Warehouse`) instead of a dedicated `sc_inventory_health_control_tower` item. Live evidence snapshots:
> - Semantic TMDL export: `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260615_135903_semantic_snapshot/definitions/sc_control_tower/parts/definition/`
> - Gold warehouse object check: `InventoryHealth_DW` currently has exactly **4** tables: `DimVendor`, `FactInventoryHealthSnapshot`, `InventoryClassificationQtyWeekly`, `InventoryHealthSubStatusWeekly` (no `CogsRollingHelper`, no `FactInventoryRiskForward`).
> - Legacy semantic model **`Supply Chain Control Tower`** currently fails DirectLake framing because it still references a missing table `InventoryHealth_DW.CogsRollingHelper` (see same snapshot folder + Power BI refresh history exports in `.../20260615_135903_semantic_snapshot/`).

## Model

| Item | Value |
|---|---|
| Model name | `sc_inventory_health_control_tower` |
| Workspace | `SupplyChain Dev` (`c8d9fc83-...`) |
| Mode | Direct Lake on OneLake |
| Source warehouse | `SupplyChain_Gold_Warehouse` (`98e2a911-...`) |
| Source schemas | `InventoryHealth_DW` for facts/vendor + `Shared_DW` for calendar/product/warehouse |
| Culture | en-US |
| User-facing tables | **6** (4 Dims + 2 Facts) — was 7 pre-cleanup |
| Hidden tables | 1 (`CogsRollingHelper`) |
| Measures | Source-controlled DAX excludes retired ATP in-stock measures after DA removed ATP forward-looking logic |

## Live Smoke Test (2026-06-01)

Power BI `executeQueries` against `sc_inventory_health_control_tower` returned:

```text
DimProductRows   = 383,883
DimWarehouseRows = 53
DimCalendarRows  = 21,551
CogsRows         = 3,092,173
FactRows         = 2,739,398
RiskRows         = 3,778,995
ShippableRows    = 1,996,512
```

## Tables (TMDL bindings)

| TMDL table | DirectLake → Gold table | Role |
|---|---|---|
| `DimCalendar` | **`Shared_DW.DimCalendar`** (cross-schema, **single shared dim**) | Date dim. **2026-05-22**: rebind from `InventoryHealth_DW.DimDate` (dropped); **2026-05-29**: moved from mart A schema to `Shared_DW.DimCalendar` with TMDL column aliases (DateKey→DateSK, FiscalMonth→FSCMonthNum, etc.). DAX unchanged. |
| `DimProduct` | **`Shared_DW.DimProduct`** | Canonical shared item/product dim. **2026-05-29**: rebind from `InventoryHealth_DW.DimItem`; keeps inventory-facing attributes, maps `PrimaryVendorName` to `PrimaryVendorDisplayName`, uses canonical `ItemSKU` + `FOBArcPrice` column spelling. |
| `DimWarehouse` | `Shared_DW.DimWarehouse` | Shared warehouse dim with forecast fields + inventory B3 flags |
| `DimVendor` | `InventoryHealth_DW.DimVendor` | Vendor dim (Phase 1: 2 cols) |
| ~~`DimRuleVersion`~~ | ~~`InventoryHealth_DW.DimRuleVersion`~~ | **REMOVED 2026-05-22** — versioning via new model when BRD changes |
| `CogsRollingHelper` | `InventoryHealth_DW.CogsRollingHelper` | Hidden — joined to FactInventoryHealthSnapshot internally |
| `FactInventoryHealthSnapshot` | `InventoryHealth_DW.FactInventoryHealthSnapshot` | Primary fact (current + weekly snapshots) |
| `FactInventoryRiskForward` | `InventoryHealth_DW.FactInventoryRiskForward` | Forward-looking fact (Week 1-4) |

## Relationships (7 active, was 9 pre-cleanup)

Source-controlled relationship file for Fabric folder deploys: [`semantic/relationships.tmdl`](semantic/relationships.tmdl). Keep this as a separate `definition/relationships.tmdl` root part when deploying through Fabric `updateDefinition`; otherwise the live model can publish tables without relationships.

```
DimCalendar.DateKey            → FactInventoryHealthSnapshot.DateKey
DimCalendar.DateKey            → FactInventoryRiskForward.DateKey
DimProduct.ItemSKU         → FactInventoryHealthSnapshot.ItemSku
DimProduct.ItemSKU         → FactInventoryRiskForward.ItemSku
DimWarehouse.WarehouseCode → FactInventoryHealthSnapshot.WarehouseCode
DimWarehouse.WarehouseCode → FactInventoryRiskForward.WarehouseCode
DimVendor.VendorNumber     → DimProduct.PrimaryVendorNumber  (snowflake)
// DimRuleVersion → FactInventoryHealthSnapshot   [REMOVED 2026-05-22]
// DimRuleVersion → FactInventoryRiskForward      [REMOVED 2026-05-22]
```

Known data-coverage residual: 27 warehouse codes in fact data do not exist in `DimWarehouse`, creating a blank warehouse bucket. This is an upstream/master-data coverage issue, not a semantic relationship failure.

## DAX measures (see [semantic/Measures_DAX.dax](semantic/Measures_DAX.dax))

Coverage: 26 of 30 BRD KPIs (4 Phase 2 deferred — Used Storage Cube physical, Total Available WH Cube, etc.).

| Group | Measures (KPI ref) |
|---|---|
| Base supply | Total On Hand Qty, Transfer InTransit Qty, PO In Transit Qty, PO On Order Qty, MO On Order Qty (KPI #1–5) |
| Demand & coverage | Allocated Demand Qty, Forecast Demand Qty 13W, AWD (M5 fix — COUNTROWS SUMMARIZE), Weeks Of Supply (KPI #6–8) |
| Financial | Inventory Value at Cost, Weighted Standard Cost, Std Selling Price Avg, Total COGS, COGS 52M Trailing (M3 fix), Inventory Turns (KPI #9–12, 22) |
| Physical | Used Storage Cube, Total Available WH Cube (Phase 2 KPI #13–14) |
| Safety/Inactive/SLOB | Safety Stock Target, Inactive Item Count, SLOB Item Count, SLOB Value (M4 fix) (KPI #16–18) |
| Risk forward | Revenue at Risk W4 (H5 fix), Shippable In Stock Rate (ATP In Stock retired 2026-06-01 per DA Gold SQL) |
| Other | Safety Stock Multiple, Obsolete Ratio (KPI #25–30) |

## Schema rewrite applied (deliverable v1 → v10 → shared dims)

Original deliverable `schemaName: gold` bindings were rewritten to Fabric warehouse schemas. Current model intentionally uses mixed schemas:

- `Shared_DW`: `DimCalendar`, `DimProduct`, `DimWarehouse`
- `InventoryHealth_DW`: `DimVendor`, `CogsRollingHelper`, `FactInventoryHealthSnapshot`, `FactInventoryRiskForward`
- [Verified] 2026-06-01 source-control drift fixed: local consolidated `SemanticModel.tmdl` now includes the hidden `table CogsRollingHelper` block matching the live semantic contract.

Verify:
```bash
grep -c "schemaName: gold" semantic/SemanticModel.tmdl              # → 0
grep -c "schemaName: Shared_DW" semantic/SemanticModel.tmdl          # → 3
grep -c "schemaName: InventoryHealth_DW" semantic/SemanticModel.tmdl # → 3
```

DAX measure expressions reference table names (not schemas) → no DAX rewrite required.

## Deploy

1. Open Power BI Desktop → "New report" → "Direct Lake on OneLake"
2. Point to workspace `SupplyChain Dev` → warehouse `SupplyChain_Gold_Warehouse`
3. Select the 6 user-facing inventory tables plus hidden `CogsRollingHelper`; `DimCalendar`, `DimProduct`, and `DimWarehouse` bind to `Shared_DW`
4. Apply TMDL via Tabular Editor (preferred) OR include `definition/relationships.tmdl` in the Fabric `updateDefinition` payload
5. Paste 30 measures from `Measures_DAX.dax`
6. Refresh dataset — should complete in seconds (Direct Lake, no row import)
7. Smoke test: render 7 critical KPIs (Total On Hand, IVC, AWD, Revenue at Risk W4, ATP rate, SLOB Value, Inventory Turns)
