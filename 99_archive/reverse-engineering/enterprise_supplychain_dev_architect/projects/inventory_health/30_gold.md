# 30 — Gold Layer

> **Status (updated 2026-06-01):** LIVE post-cleanup. Active Inventory Health facts/helpers remain in `InventoryHealth_DW`; shared `DimCalendar`, `DimProduct`, and `DimWarehouse` now live in `Shared_DW`. Gold tables have live data, semantic smoke tests pass, and latest `pl_sc_master` / `pl_sc_gold` job samples include Completed runs.
>
> **2026-06-15 routing note:** live Gold publish is still pipeline CTAS, not the Silver generic-SP path. `pl_sc_gold` is project-filtered again, so the active Gold control plane should be read as `4 inventory_health rows + 3 shared rows`, not as one unscoped combined publish set.
>
> **2026-05-22 changes** (2 cleanup rounds):
> - Round 1: Dropped `DimRuleVersion` (over-engineering — versioning via new semantic model when BRD changes, not via versioned dim). Removed RuleVersionKey column from both Fact views + 2 TMDL relationships + 1 DAX measure simplified.
> - Round 2: Dropped `DimDate` (duplicate of `Shared_DW.DimCalendar`). Inv_health TMDL rebinds to the shared Gold DimCalendar via column-name aliases — single shared date dim across both marts. Eliminates physical Gold dim duplication.

## Schema

`InventoryHealth_DW` in `SupplyChain_Gold_Warehouse` (`98e2a911-...`).

Pattern: cross-DB CTAS via `pl_sc_gold` pipeline (registry-driven). Each Gold view reads Silver physical tables via 3-part name `[SupplyChain_Processing_Warehouse].[<schema>].[<table>]`.

**2026-05-28 DA-first refactor:** `CogsRollingHelper` reads `[SupplyChain_Processing_Warehouse].[SalesHistory_Enh].[v_InvoiceDetailLineLevel]` directly. It no longer depends on Mart B `InventoryHistory_Enh.SalesShipment`.

**2026-06-01 DA-first rebuild:** physical facts/helpers now report `FactInventoryHealthSnapshot=2,739,398`, `FactInventoryRiskForward=3,778,995`, and `CogsRollingHelper=3,092,173` after rebuilding from the latest DA-aligned Gold views. `FactInventoryRiskForward` no longer exposes `ATPQty` or `ATPInStockFlag`; semantic definition was updated accordingly. Pre-rebuild physical backup tables were dropped after approval because this is still a dev rollout; view and semantic definitions remain backed up under `artifacts/backups/`.

## Star schema (post-cleanup 2026-05-22)

```
       DimCalendar (shared) ────┐
               DimProduct ────┤
              DimWarehouse ───┼── FactInventoryHealthSnapshot
                DimVendor ────┘        │
                                       │
                                       └─→ CogsRollingHelper (hidden, JOIN at view-time)

       DimCalendar (shared) ────┐
               DimProduct ────┼── FactInventoryRiskForward
              DimWarehouse ───┘
```

## Assets (6 inv_health + 1 shared, was 8 pre-cleanup)

### Shared dims cross-mart (3)

| Asset | TMDL bind | Notes |
|---|---|---|
| `DimCalendar` | `Shared_DW.DimCalendar` (75 cols) | Single shared date dim used by both forecast + inv_health marts. Inv_health TMDL aliases display names: DateKey→DateSK, FiscalMonth→FSCMonthNum, FiscalMonthYear→FSCMonthYearNum, etc. |
| `DimProduct` | `Shared_DW.DimProduct` (218 cols) | Canonical shared product/item dim. Replaces Inventory `DimItem`; includes `Cubes`, `FOBArcPrice`, `UnavailableFlag`, vendor attributes, and forecast-compatible fields. |
| `DimWarehouse` | `Shared_DW.DimWarehouse` (20 cols) | Shared warehouse dim with forecast display contract plus inventory B3 flags. |

### Dims (inventory-specific)

| Asset | View | Source | Notes |
|---|---|---|---|
| ~~`DimDate`~~ | — | **DROPPED 2026-05-22** | Consolidated to `Shared_DW.DimCalendar` — single shared date dim used by both marts. TMDL rebinds cross-schema. |
| ~~`DimItem`~~ | `v_DimItem` compatibility only | **LEGACY after 2026-05-29 shared `DimProduct` cutover** | Physical `InventoryHealth_DW.DimItem` still exists with 383,371 rows but semantic now binds table `DimProduct` to `Shared_DW.DimProduct` (383,883 rows / 218 cols). |
| ~~`DimWarehouse`~~ | — | **MOVED to `Shared_DW.DimWarehouse`** | Inventory semantic binds to shared warehouse dim; no active `InventoryHealth_DW.DimWarehouse` physical table exists. |
| `DimVendor` | `v_DimVendor` | `ReferenceMaster_Enh.Vendor` (NEW master) | 86,620 rows live |
| ~~`DimRuleVersion`~~ | ~~`v_DimRuleVersion`~~ | **DROPPED 2026-05-22** — versioning via new semantic model when BRD changes |

### Helper (1, hidden from semantic model)

| Asset | View | Notes |
|---|---|---|
| `CogsRollingHelper` | `v_CogsRollingHelper` | 3,092,173 rows live after DA-first rebuild. Monthly grain from Mart A invoice line + inline cost current; 12M + 52M rolling sums. **H4 fix** (ORDER BY FiscalMonthYear) + **M3 fix** (Cogs52W → Cogs52M rename). Robert sign-off pending on weekly vs monthly grain. |

### Facts (2)

| Asset | View | Grain | Notes |
|---|---|---|---|
| `FactInventoryHealthSnapshot` | `v_FactInventoryHealthSnapshot` | `(ItemSku, WarehouseCode, SnapshotDate, SnapshotType)` where SnapshotType ∈ {Current, Weekly} | 2,739,398 rows live after DA-first rebuild. New view collapses weekly history to snapshot/fiscal-month aligned rows and includes 53 output columns. **M4 fix** (SLOB NULL guard). |
| `FactInventoryRiskForward` | `v_FactInventoryRiskForward` | `(ItemSku, WarehouseCode, WeekEndingDate)` | 3,778,995 rows live after DA-first rebuild. Forward supply-plan risk fact; ATP output columns removed per DA Gold SQL. **H5 fix** (WeekFourFlag exact week). Robert sign-off pending. |

## Cross-mart reuse decisions

- **Source level**: REUSE `ReferenceMaster_Enh.ItemMaster/Warehouse/Calendar` (extension via `v_*Ext` views in Silver layer).
- **Semantic level**: DO NOT bind DirectLake to `ForecastAccuracy_DW.Dim*`. Use `Shared_DW.DimCalendar`, `Shared_DW.DimProduct`, and `Shared_DW.DimWarehouse` as the canonical shared dims, with Inventory semantic table names/aliases preserved.
- Bob Q2 (DimCalendar/DimProduct cross-mart) — flagged in `01_docs/open_questions_for_bob.md`.

## Load orchestration

Gold tables get populated via `pl_sc_gold` pipeline (existing, registry-driven):

```sql
-- pl_sc_gold logic (excerpt)
SELECT physical_schema, physical_object, legacy_view_name
FROM Meta.AssetRegistry
WHERE canonical_layer='Gold' AND project=@project AND is_active=1
    -- ForEach: replace target table then CTAS from <legacy_view_name>
```

[Verified] On 2026-06-15 the live `pl_sc_gold` definition was re-aligned to this project-filtered pattern. Do not manually run destructive Gold table replacement outside the pipeline without explicit approval and a fresh backup/diff plan.

## Track A fix carry-over (Gold-side)

| Fix | Location in v_* |
|---|---|
| **H4** ORDER BY FiscalMonthYear | `v_CogsRollingHelper` window OVER clauses |
| **H5** WeekFourFlag exact week | `v_FactInventoryRiskForward` WeekFourFlag column |
| **M3** Cogs52W → Cogs52M rename | `v_CogsRollingHelper` + propagated to TMDL/DAX |
| **M4** SLOB + ObsoleteValue NULL guard | `v_FactInventoryHealthSnapshot` SlobFlag + ObsoleteValue cases |

## File reference

- [etl/gold_views.sql](etl/gold_views.sql) — 8 CREATE VIEW statements
- [etl/registry_inserts.sql](etl/registry_inserts.sql) — 8 Gold registry rows
- [etl/dq_rules_inserts.sql](etl/dq_rules_inserts.sql) — 7 Gold DQ rules
- [04_semantic/SemanticModel.tmdl](04_semantic/SemanticModel.tmdl) — DirectLake binding (`schemaName: InventoryHealth_DW`)
