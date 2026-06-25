# Source Confirmation Status — Inventory Health ETL

> Snapshot 2026-05-14 (post-probe). Single source of truth cho mọi quyết định source/ETL.

---

## 1. Tổng quan

| Hạng mục | Số lượng | Trạng thái |
|---|---|---|
| **Bronze tables xác định** | **25** | 25/25 tồn tại trên Lakehouse |
| Bronze governed (Enterprise) | 22 | OK (1 vẫn 0 rows — PoDetail) |
| Bronze replacement (SupplyChain) | 3 | đang dùng tạm chờ DE promote |
| Silver tables | 26 (17 base + 4 helper + 4 snapshot + 1 ItemBalanceHistory placeholder) | SQL viết xong, chờ deploy + smoke |
| Gold tables | 8 (5 dim + 1 helper + 2 fact) | SQL viết xong |
| DAX measures | 30 KPI | TMDL + measures viết xong |

---

## 2. 25 Bronze sources — chi tiết verified

### A. Governed Enterprise (24 — dùng được Phase 1 trực tiếp)

| # | Source | Rows | Cols | Note |
|---|---|---|---|---|
| 1 | `Enterprise.MasterData_DW.DimItemMaster` | 382,302 | 173 | ✅ ItemSKU + 172 attrs; **Category=RetailCategoryName**, **Series=SeriesNumber/SeriesName** |
| 2 | `Enterprise.MasterData_DW.DimDate` | 21,551 | 72 | ✅ DateID, FiscalDate, FiscalWeekLastDate, FiscalMonth, FiscalMonthYear |
| 3 | `Enterprise.Wholesale_Codis_AFI.AshleyWarehouseMaster` | 54 | 29 | ✅ ⚠️ NO warehouse-name col; use wmaWarehouse as code+name |
| 4 | `Enterprise.Purchasing_AFI.VendorMaster` | **86,598** | 51 | ✅ VendorNumber + VendorName (Matrix v3 said 169K — wrong) |
| 5 | `Enterprise.ItemMaster_AFI.ITEMBL` | 3,411,561 | 124 | ✅ Use **MOHTQ** (PHYOH=0 dead) |
| 6 | `Enterprise.ItemMaster_AFI.ITMRVA` | 2,897,198 | 122 | ✅ Filter STID='000' + ROW_NUMBER dedupe |
| 7 | `Enterprise.ItemMaster_AFI.ITBEXT` | 3,389,222 | 50 | ✅ Use only `MFPUS` col (CRHLD/DLHLD/TOHLD/ATPQT all dead) |
| 8 | `Enterprise.SupplyChain_Enh_1.DemandInventorySnapshotWeekly` | **557,141,256** | 31 | ✅ **No channel split** (no DfcCustomerGroups in inventory). dinSnapshot=week-end |
| 9 | `Enterprise.SupplyChain_Enh_1.DemandForecastSnapshotWeekly` | **306,173,656** | 23 | ✅ **3-way channel split** (DfcCustomerGroups + dfcFCSTTypeCode + dfcMgmtCode) → SUM. dfcSnapshot=week-end (NO separate dfcWeekEnding) |
| 10 | `Enterprise.Wholesale_Purchasing_AFI.ATPSUM` | 296,744 | 119 | ✅ APAT01-27 + APWK01-27 wide → UNPIVOT. APWK is **decimal** (year-week code), not date |
| 11 | `Enterprise.Wholesale_DemandPlanning_AFI.SupplyForecast` | 921,060 | 7 | ⚠️ ONLY 7 cols. `FCST_1_ID`/`FCST_2_ID` likely item/wh; `FCST_YR_PRD` is year-period numeric code; `FCST_RSLT_QTY` is forecast qty |
| 12 | `Enterprise.Wholesale_DemandPlanning_AFI.SupplyPlanDetail` | 3,877,267 | 27 | ✅ All 13 spd* cols verified |
| 13 | `Enterprise.Wholesale_DemandPlanning_AFI.DemandInventory` | 3,829,284 | 31 | (Current SS alternative — not used in Phase 1 ETL) |
| 14 | `Enterprise.SalesHistory_AFI.InvoiceDetail` | 128,309,247 | 80 | ✅ PK=`(InvoiceNumber, ItemSequence)`. **Warehouse** (not WarehouseCode) |
| 15 | `Enterprise.Manufacturing_ProductionPlanning_AFI.MOMAST` | 251,596 | 71 | ✅ FITEM/FITWH/OSTAT(varchar)/ORQTY/QTYRC/ODUDT |
| 16 | `Enterprise.Manufacturing_Inventory_AFI.TFRDTL` | 675,462 | 19 | ✅ DTFRNO/DITNBR/DTFRQT/DSHPQT/DCUBES; no obvious line col — use synthetic |
| 17 | `Enterprise.Manufacturing_Inventory_AFI.TFRHDR` | 26,135 | 20 | ✅ HTFRNO/HFHOUS/HTHOUS/HCANCL/HSTATS |
| 18 | `Enterprise.Manufacturing_Inventory_AFI.IMHIST` | 11,664,291 | 105 | ✅ ITNBR/HOUSE/TCODE/TRNDT(decimal date key)/TRQTY/PRQOH/NUQOH |
| 19 | `Enterprise.CustomerOrders_AFI.OpenOrderDetail` | 918,213 | 66 | ✅ ItemAllocationFlag=decimal (not bit); use PromiseDate/MaterialRequestDate |
| 20 | `Enterprise.CustomerOrders_AFI.OpenOrderHeader` | 219,900 | 15 | ✅ Small dim header |
| 21 | `Enterprise.CustomerOrders_AFI.ExtendedOrder` | (not in v3) | — | not loaded into Silver Phase 1 |
| 22 | `Enterprise.MasterData_ProductKnowledge.Item_ENV` | (not in v3) | — | not loaded into Silver Phase 1 |
| 23 | `Enterprise.Wholesale_ProductSourcing_AFI.Container` | 299,485 | 39 | (Container Count KPI Phase 2) |
| 24 | `Enterprise.Wholesale_ProductSourcing_AFI.PoDetail` | **0** | 53 | 🚨 STILL EMPTY — pending DE reload |

### B. SupplyChain Lakehouse (3 — replacement đang dùng tạm)

| # | Source | Rows | Cols | Workaround For |
|---|---|---|---|---|
| 23 | `SupplyChain_Lakehouse.dbo.podetail_v2` | **21,923,551** | 53 | PoDetail empty. PK=(podordernum, podvendornum, poditemsequence). **`poditemnum`** (not poditem). `podstatuscode` is varchar |
| 24 | `SupplyChain_Lakehouse.dbo.pomaster` | **5,681,305** | 75 | PoMaster doesn't exist in Enterprise. ETA/container/vendor enrichment |
| 25 | `SupplyChain_Lakehouse.dbo.logility_demandfulfillment` | **38,356,303** | **53** | Logility doesn't exist in Enterprise. ⭐ Rich source — has OnHandQty, ShippableInvQty, SafetyStockQty, ItemStatus, FutureStatus, Vendor, Price |

---

## 3. SQL files — 10 layer scripts (~3,000 lines total)

| File | Purpose | Procs |
|---|---|---|
| `_scripts/sql/01_setup.sql` | Schemas + EtlWatermark + 4 snapshot DDLs | 0 procs (DDL only) |
| `_scripts/sql/02_silver_dims.sql` | Dim helpers Tier 0 | 3 procs |
| `_scripts/sql/03_silver_base.sql` | Base Tier 1 + large Tier 2 | 14 procs |
| `_scripts/sql/04_silver_helpers.sql` | Pre-compute helpers Tier 3 | 4 procs |
| `_scripts/sql/05_silver_snapshots.sql` | Snapshot capture Tier 4 | 4 procs |
| `_scripts/sql/06_gold_dims.sql` | Gold 5 dimensions | 5 procs |
| `_scripts/sql/07_gold_helpers.sql` | CogsRollingHelper | 1 proc |
| `_scripts/sql/08_gold_facts.sql` | 2 facts (HealthSnapshot + RiskForward) | 2 procs |
| `_scripts/sql/09_master.sql` | usp_RefreshAll silver + gold | 2 master procs |
| `_scripts/sql/10_verify.sql` | Smoke + KPI sample (no procs) | 0 |

**Total**: 25 stored procs covering Bronze → Silver → Gold pipeline.

---

## 4. Semantic model + DAX — Power BI

| File | Purpose |
|---|---|
| `FinalDecision/semantic_model/InventoryHealth_SemanticModel.tmdl` | Full TMDL spec: 7 tables (5 dim + 2 fact), 9 relationships, Direct Lake source |
| `FinalDecision/semantic_model/InventoryHealth_Measures.dax` | 30+ DAX measures covering all KPIs |

### Star schema

```
                       ┌───────────────┐
                       │   DimDate     │
                       └───────┬───────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                                             │
┌───────▼──────────────────┐               ┌──────────▼─────────────────┐
│ FactInventoryHealth      │               │ FactInventoryRiskForward   │
│ Snapshot (Current/Weekly)│               │ (Forward projection)       │
└───────┬──────────────────┘               └──────────┬─────────────────┘
        │                                             │
        │  ┌────────────────────────────────────────┐ │
        ├─►│   DimItem  ◄── DimVendor (snowflake)   ├◄┤
        │  └────────────────────────────────────────┘ │
        │  ┌────────────────────────────────────────┐ │
        ├─►│   DimWarehouse                         ├◄┤
        │  └────────────────────────────────────────┘ │
        │  ┌────────────────────────────────────────┐ │
        └─►│   DimRuleVersion                       ├◄┘
           └────────────────────────────────────────┘
```

---

## 5. 30 KPI → measure mapping (definitive)

| # | KPI BRD | Measure DAX | Source fact + cols |
|---|---|---|---|
| 1 | On Hand Quantity | `Total On Hand Qty` | Health.OnHandQty (IsLatestSnapshot=1) |
| 2 | Transfer InTransit Qty | `Transfer InTransit Qty` | Health.TransferInInTransitQty |
| 3 | PO In Transit Qty | `PO In Transit Qty` | Health.POInTransitQty |
| 4 | PO On Order Qty | `PO On Order Qty` | Health.POOnOrderQty |
| 5 | MO On Order Qty | `MO On Order Qty` | Health.MOOnOrderQty |
| 6 | Allocated Demand Qty | `Allocated Demand Qty` | Risk.AllocatedDemandQty |
| 7 | Forecast Demand Qty | `Forecast Demand Qty 13W` | Risk.NetForecastQty |
| 8 | AWD | `AWD` | Health.AwdQty (weighted by Item) |
| 9 | Inventory Value at Cost | `Inventory Value at Cost` | Health.InventoryValueAtCost |
| 10 | Standard Cost | `Weighted Standard Cost` | derive |
| 11 | Standard Selling Price | `Standard Selling Price Avg` | DimItem.FobArcPrice |
| 12 | COGS | `Total COGS` | Health.PeriodCogs |
| 13 | Used Storage Cube | `Used Storage Cube` | Health.UsedStorageCube |
| 14 | Total Avail WH Cube | `Total Available Warehouse Cube` | DimWarehouse (Phase 2) |
| 15 | Container Count | — | Phase 2 (Container source) |
| 16 | Safety Stock Target | `Safety Stock Target` | Health.SafetyStockTargetQty |
| 17 | Inactive Flag | `Inactive Item Count` | Health.InactiveFlag=1 |
| 18 | SLOB | `SLOB Item Count` / `SLOB Value` | Health.SlobFlag=1 |
| 19 | Revenue at Risk | `Revenue at Risk` | Risk.RevenueAtRiskValue (Week4) |
| 20 | Lifecycle Status | DimItem.LifecycleStatus | slicer |
| 21 | Active Status | DimItem.LifecycleStatus<>'Inactive' | filter |
| 22 | Vendor | DimVendor.VendorName | slicer (snowflake) |
| 23 | DC/WH | DimWarehouse.WarehouseCode | slicer |
| 24 | On Hold Status / Ratio | `On Hold Qty` / `On Hold Ratio` | Health.OnHoldQty (snapshot-aware) |
| 25 | FG filter | DimItem.IsFinishedGoodsItem=1 + DimWarehouse.IsFinishedGoodsWarehouse=1 | filter |
| 26 | Turns | `Inventory Turns` | Health.Cogs52W / AverageInventoryValueAtCost |
| 27 | ATP In-Stock Rate | `ATP In Stock Rate` | Risk.ATPInStockFlag |
| 28 | Shippable Inv In-Stock Rate | `Shippable In Stock Rate` | Risk.ShippableInStockFlag |
| 29 | Safety Stock Multiple | `Safety Stock Multiple` | derive |
| 30 | Obsolete Ratio | `Obsolete Ratio` | Health.ObsoleteValue / InventoryValueAtCost |
| 31 | Aged Inventory % | — | Phase 2 (serial source) |
| 32 | Warehouse Capacity Utilization | `Capacity Utilization Pct` | derive (DimWh Phase 2) |
| 33 | Total Inventory Commitment | `Total Inventory Commitment Qty` | derive |

Coverage: **30/33 buildable trong Phase 1** (3 còn lại defer Phase 2 vì source missing).

---

## 6. Deploy runbook (draft action — chưa pipeline)

### Bước 1: Setup (~10 phút)

```sql
-- Trong Processing Warehouse
:r 01_setup.sql   -- creates [silver] + EtlWatermark + snapshot DDLs

-- Trong Gold Warehouse
-- Manual: CREATE SCHEMA gold AUTHORIZATION dbo;
```

### Bước 2: Silver build (~30-60 phút lần đầu)

```sql
-- Trong Processing Warehouse, run order:
:r 02_silver_dims.sql
:r 03_silver_base.sql
:r 04_silver_helpers.sql
:r 05_silver_snapshots.sql

-- Smoke
:r 10_verify.sql   -- section A only
```

### Bước 3: Gold build (~20-40 phút lần đầu)

```sql
-- Trong Gold Warehouse:
:r 06_gold_dims.sql
:r 07_gold_helpers.sql
:r 08_gold_facts.sql

-- Smoke
:r 10_verify.sql   -- sections B, C, D, E
```

### Bước 4: Compile master + first daily run

```sql
-- Trong từng Warehouse:
:r 09_master.sql

-- Test run:
EXEC silver.usp_RefreshAll;   -- in Processing WH
EXEC gold.usp_RefreshAll;     -- in Gold WH
```

### Bước 5: Power BI semantic

1. Power BI Desktop → New report → Direct Lake on OneLake
2. Pick `SupplyChain Gold Warehouse` → select 7 tables (DimDate, DimItem, DimWarehouse, DimVendor, DimRuleVersion, FactInventoryHealthSnapshot, FactInventoryRiskForward)
3. Apply relationships per `InventoryHealth_SemanticModel.tmdl`
4. Paste DAX measures from `InventoryHealth_Measures.dax` (Tabular Editor recommended)
5. Build report visuals using measures

### Bước 6: Verify với KPI sample

`10_verify.sql` sections F.1-F.7 — confirm KPI numbers match BRD reference.

---

## 7. Outstanding items (chưa giải quyết)

| Item | Impact | Action |
|---|---|---|
| Enterprise PoDetail **0 rows** | PO KPI relying on Enterprise schema returns 0 (workaround: SC podetail_v2 active) | Wait DE reload |
| `Inventory_Enh_History.ItemBalance` schema **không tồn tại** | BRD primary historical source unavailable | Fallback: `silver.InventorySnapshotWeekly` covers most needs |
| MOMAST OSTAT firm codes | Placeholder `IN ('10','40','45')` in code | Robert confirm |
| `SupplyForecast` 7-col structure | Assume FCST_1_ID=item, FCST_2_ID=wh — needs business confirm | Probe sample row for semantic |
| Logility 9,128 dup grain | Dedupe via ROW_NUMBER ORDER BY StatusChngDate DESC | Wait DE upstream fix |
| Warehouse capacity source | NULL Phase 1 | WH team file load Phase 2 |
| Container Count rule | Heuristic placeholder | Phase 2 |
| Aged Inventory % | No serial source | Phase 2 |

---

## 8. Files & paths

| Category | Path |
|---|---|
| Plan v3 | `/Users/MAC/Documents/InventoryHealth/FinalDecision/InventoryHealth_ETL_Plan_v3.md` |
| Plan v2 (deprecated) | `/Users/MAC/Documents/InventoryHealth/FinalDecision/InventoryHealth_ETL_Plan_v2.md` |
| SQL scripts (10) | `/Users/MAC/Documents/InventoryHealth/_scripts/sql/01-10.sql` |
| Semantic model TMDL | `/Users/MAC/Documents/InventoryHealth/FinalDecision/semantic_model/InventoryHealth_SemanticModel.tmdl` |
| DAX measures | `/Users/MAC/Documents/InventoryHealth/FinalDecision/semantic_model/InventoryHealth_Measures.dax` |
| Bronze truth (JSON, full) | `/Users/MAC/Documents/InventoryHealth/_artifacts/bronze_source_truth.json` |
| Bronze truth (MD, readable) | `/Users/MAC/Documents/InventoryHealth/_artifacts/bronze_source_truth.md` |
| Source corrections | `/Users/MAC/Documents/InventoryHealth/_artifacts/source_corrections.md` |
| Probe script | `/Users/MAC/Documents/InventoryHealth/_scripts/probe_all_sources.py` |
| BRD KPIs (new) | `/Users/MAC/Documents/InventoryHealth/FinalDecision/Final02/Inventory Health Semantic Model Dummy Data - New Structure v3 1.xlsx` |
| Lineage diagram | `/Users/MAC/Documents/InventoryHealth/FinalDecision/InventoryHealth_DataLineage.svg` |

---

## 9. Summary line

> **25 bronze sources verified · 25 silver procs + 10 SQL scripts written · 2 facts + 5 dims + 30+ DAX measures defined · 30/33 KPIs build-ready Phase 1 · 3 KPIs defer Phase 2 (capacity, container, aged).**
