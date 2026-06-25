# Inventory Health — Master Architecture Plan

> Comprehensive picture: Bronze → 5-Wave Silver → Gold → Power BI Semantic.
> Single source of truth cho toàn bộ logic + code + sample data + KPI coverage. Generated 2026-05-16 sau 5 rounds Lakehouse probing.
>
> Mục tiêu: Aric thấy bức tranh toàn cảnh — bao nhiêu source, ETL chia mấy lớp, semantic xử lý mấy KPI cụ thể, dù chưa 100% Enterprise governed vẫn build được Phase 1 với assumptions hợp lý.

---

## 0. Executive Summary

```
┌──────────────────────────────────────────────────────────────────────┐
│  ARCHITECTURE LAYERS                                                  │
├──────────────────────────────────────────────────────────────────────┤
│  Bronze (Lakehouses)        — 32 sources                              │
│    ├── 14 ready                                                       │
│    ├──  4 cần handle Silver                                           │
│    ├──  3 chưa load (DE pending)                                      │
│    └──  4 stale/broken (DE fix needed)                                │
│                                                                       │
│  Silver (Processing WH)     — ~35 tables in 4 waves                   │
│    ├── Wave 1: 18 base direct extracts                                │
│    ├── Wave 2:  4 enriched/derived intermediate                       │
│    ├── Wave 3:  7 pre-compute helpers (AWD, LastInv, ...)             │
│    └── Wave 4:  6 snapshot captures (4 P1 + 2 P2)                     │
│                                                                       │
│  Gold (Gold WH)             — 8 tables                                │
│    ├── 5 conformed dimensions                                         │
│    ├── 1 helper (CogsRollingHelper)                                   │
│    └── 2 facts (HealthSnapshot + RiskForward)                         │
│                                                                       │
│  Semantic (Power BI)        — 7 exposed tables + 30 DAX measures      │
│                                                                       │
│  KPI Coverage Phase 1       — 26/30 KPI buildable ≈ 87%               │
│    └── 4 defer Phase 2 (Capacity, Container, Aged, OnHold past)       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 1. BRONZE — 32 sources, 3 nhóm rõ ràng

### 🟢 Nhóm A — 14 bảng READY (production-grade, dùng được ngay)

| # | Bảng | Lake | Rows | KPI fed |
|---|---|---|---|---|
| 1 | `MasterData_DW.DimItemMaster` | Ent | 382,302 | #11, #17, #18, #20, #21 |
| 2 | `MasterData_DW.DimDate` | Ent | 21,551 | All time-grain |
| 3 | `Wholesale_Codis_AFI.AshleyWarehouseMaster` | Ent | 54 | #2, #20, #21 |
| 4 | `Purchasing_AFI.VendorMaster` | Ent | 86,598 | DimVendor (99.88% coverage) |
| 5 | `ItemMaster_AFI.ITEMBL` | Ent | 3,411,561 | #1, #2, #9, #13, #17, #30 |
| 6 | `ItemMaster_AFI.ITMRVA` | Ent | 2,897,198 | #9, #10, #12 |
| 7 | `Wholesale_DemandPlanning_AFI.SupplyPlanDetail` | Ent | 3,879,820 | #19, #24 |
| 8 | `SalesHistory_AFI.InvoiceDetail` | Ent | 128,309,247 | #8, #12, #18 |
| 9 | `Manufacturing_Inventory_AFI.TFRDTL` | Ent | 675,462 | #27 |
| 10 | `Manufacturing_Inventory_AFI.TFRHDR` | Ent | 26,135 | #27 |
| 11 | `Manufacturing_Inventory_AFI.IMHIST` | Ent | 11,664,291 | #18, #26 (movement) |
| 12 | `CustomerOrders_AFI.OpenOrderHeader` | Ent | 219,900 | #6 header join |
| 13 | **`Wholesale_DemandPlanning_AFI.DemandForecast`** ⭐ | Ent | **12,265,560** | **#7, #8** (fresh today, replaces stale snapshot) |
| 14 | **`Wholesale_ProductSourcing_AFI.PoDetail`** ⭐ | Ent | **21,945,294** | **#3, #4** (DE mới load) |

### 🟡 Nhóm B — 4 bảng CẦN HANDLE silver (quirks, dùng được sau fix)

| # | Bảng | Quirk | Silver action |
|---|---|---|---|
| 1 | `ItemMaster_AFI.ITBEXT` | 4 cols dead (CRHLD/DLHLD/TOHLD/ATPQT=0) | Chỉ dùng `MFPUS` → UnavailableFlag |
| 2 | `Manufacturing_ProductionPlanning_AFI.MOMAST` | OSTAT firm chưa Robert chốt; 49 blank | Filter blank, OSTAT IN ('10','40','45') placeholder |
| 3 | `CustomerOrders_AFI.OpenOrderDetail` | 🚨 ItemAllocationFlag value = **2** (NOT 1) | Đổi filter `= 2` |
| 4 | `Wholesale_Purchasing_AFI.ATPSUM` | 43 APAT + chỉ 1 APWK01 (base YYYYMMDD) | UNPIVOT APAT01-43 + derive WeekEnding = APWK01 + (n-1)×7 days |

### 🔴 Nhóm C — 3 bảng CHƯA LOAD ENTERPRISE (workaround SC)

| # | Bảng | Workaround | KPI block |
|---|---|---|---|
| 1 | `Enterprise.PoMaster` | `SC.dbo.pomaster` (5.68M) | #3 PO ETA/vendor enrichment |
| 2 | `Enterprise.SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` | `SC.dbo.logility_demandfulfillment` (38.36M, 9128 dup) | #17 Inactive past, #18 SLOB past, #20 Lifecycle past |
| 3 | `Enterprise.Inventory_Enh_History.ItemBalance` | `silver.InventorySnapshotWeekly` fallback | Historical inventory trend audit-grade |

### ⚠️ Nhóm D — 4 bảng STALE / SCHEMA ISSUE (DE fix)

| # | Bảng | Vấn đề | Action |
|---|---|---|---|
| 1 | `SupplyChain_Enh_1.DemandForecastSnapshotWeekly` | Stale **2.1 năm** (2024-03-25) | Skip, dùng `DemandForecast` thay |
| 2 | `SupplyChain_Enh_1.DemandForecastSnapshotDaily` | Stale 11 tuần | Defer Phase 2 |
| 3 | `SupplyChain_Enh_1.DemandInventorySnapshotWeekly` | Stale 10 tuần | Live with caveat |
| 4 | `Wholesale_Purchasing_AFI.ATPSUM` | "8AM 2nd version" mechanism — không có audit col `usra/dtea` trên ATPSUM (≠ other tables) | Dùng latest snapshot; chờ DE confirm version logic |

### ⏭️ Skip Phase 1 (verify Phase 2)

| Bảng | Status |
|---|---|
| `Wholesale_ProductSourcing_AFI.Container` | 299,485 rows verified — Phase 2 KPI #15 Container Count |
| `CustomerOrders_AFI.ExtendedOrder` | Not in Phase 1 scope (matrix v3 mention On Hold order-level) |
| `MasterData_ProductKnowledge.Item_ENV` | Phase 2 hold buy code |
| `DemandPlanning_AFI.DemandForecast` | Identical to Wholesale_DemandPlanning_AFI.DemandForecast — pick 1 canonical |

---

## 2. SILVER — 4-WAVE ARCHITECTURE (~35 tables, Processing WH)

Silver có **nhiều layer hơn Bronze** vì có wave intermediate phục vụ wave kế tiếp. Lớp cuối phục vụ Gold.

```
┌─── WAVE 1 ────────────────────────────────────────────────────────────┐
│  Base direct extracts (18 tables) — clean Bronze → TRIM/dedupe/filter │
│  Depends: Bronze only                                                  │
└────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─── WAVE 2 ────────────────────────────────────────────────────────────┐
│  Enriched intermediate (4 tables) — join Wave 1 results                │
│  Depends: Wave 1                                                       │
└────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─── WAVE 3 ────────────────────────────────────────────────────────────┐
│  Pre-compute helpers (7 tables) — AWD, LastInvoice, etc.               │
│  Depends: Wave 1 + 2                                                   │
└────────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─── WAVE 4 ────────────────────────────────────────────────────────────┐
│  Snapshot capture (6 tables, daily/weekly schedule)                    │
│  Depends: Wave 1                                                       │
└────────────────────────────────────────────────────────────────────────┘
                                  ↓
                              ⭐ GOLD layer ⭐
```

### Wave 1 — Base direct extracts (18 tables)

| # | Table | Source bronze | Logic | KPI feed |
|---|---|---|---|---|
| 1.01 | `silver.ItemMaster` | DimItemMaster + VendorMaster + ITBEXT(MFPUS) | TRIM, derive IsFinishedGoodsItem (LIKE 'Z%K'), UnavailableFlag from MFPUS='U' | DimItem feed |
| 1.02 | `silver.Warehouse` | AshleyWarehouseMaster | TRIM, derive IsFinishedGoodsWh (7-list) + IsNetworkWh (11-list) + IntransitWarehouseCode | DimWarehouse feed |
| 1.03 | `silver.Vendor` | VendorMaster | TRIM | DimVendor feed |
| 1.04 | `silver.CostCurrent` | ITMRVA | Filter STID='000' (no dup at this filter — ROW_NUMBER optional) | #9, #10, #12 |
| 1.05 | `silver.InventoryCurrent` | ITEMBL | Daily append; MOHTQ (NOT PHYOH); **filter `LIKE 'Z%K'` (FG only)**; TRIM | #1 OnHand current |
| 1.06 | `silver.InventorySnapshotWeekly` | DemandInventorySnapshotWeekly | Incremental by dinSnapshot; ROW_NUMBER dedupe safety | #1 historical, #16 Safety Stock |
| 1.07 | `silver.ForecastCurrent` | **DemandForecast** (NOT stale snapshot) | Fresh; channel SUM (DfcCustomerGroups+dfcFCSTTypeCode+dfcMgmtCode); monthly grain | #7, #8 AWD |
| 1.08 | `silver.SupplyPlan` | SupplyPlanDetail | Direct map; spd* cols; SINegQty derive | #19, #24 |
| 1.09 | `silver.SalesShipment` | InvoiceDetail | Incremental by InvoiceDate; PK (InvoiceNumber, ItemSequence); `Warehouse` (not WarehouseCode) | #12, #18, #8 fallback |
| 1.10 | `silver.PurchaseOrder` | **Enterprise.PoDetail** (NOT SC) + SC.pomaster header | ROW_NUMBER dedupe (1 dup key); status derive (10=OnOrder, 20=InTransit) | #3, #4 |
| 1.11 | `silver.ManufacturingOrder` | MOMAST | Filter blank FITEM/FITWH; OSTAT IN ('10','40','45') placeholder | #5 |
| 1.12 | `silver.HoldingTransfer` | TFRDTL + TFRHDR | JOIN, filter HCANCL='N' AND HFHOUS=HTHOUS; synthetic line via ROW_NUMBER | #27 |
| 1.13 | `silver.MovementHistory` | IMHIST | Incremental by TRNDT; JOIN DimDate for date conversion | #18, #26 NoMovement |
| 1.14 | `silver.AtpWeekEnding` | ATPSUM | **NEW LOGIC**: UNPIVOT APAT01-43; WeekEnding = APWK01 (YYYYMMDD) + (n-1)×7 days | #23 ATP |
| 1.15 | `silver.AllocatedDemandCandidate` | OpenOrderDetail + Header | **Filter `ItemAllocationFlag = 2` (NOT 1)** AND `QuantityShipped = 0` | #6 |
| 1.16 | `silver.LogilityItemStatus` | SC.dbo.logility_demandfulfillment | ROW_NUMBER dedupe 9128 dup; until Enterprise loaded | #17, #18, #20 |
| 1.17 | `silver.ContainerInfo` | Wholesale_ProductSourcing_AFI.Container | TRIM keys; Phase 2 prep | #15 (Phase 2) |
| 1.18 | `silver.ForecastSnapshotDaily` (Phase 2) | DemandForecastSnapshotDaily | Stale 11w; defer | Historical accuracy P2 |

### Wave 2 — Enriched intermediate (4 tables) — built ON TOP of Wave 1

| # | Table | Inputs (Wave 1) | Logic |
|---|---|---|---|
| 2.01 | `silver.TransferIntransitCurrent` | InventoryCurrent + Warehouse | JOIN ITEMBL filtered by `HOUSE IN (intransit_letter_codes)` mapped to destination WarehouseCode via Warehouse.IntransitWarehouseCode |
| 2.02 | `silver.ItemUniverse` | InventoryCurrent + InventorySnapshotWeekly | DISTINCT (ItemSku, WarehouseCode) — universe for helper computations |
| 2.03 | `silver.AsOfDateSet` | InventoryCurrent.SnapshotDate ∪ InventorySnapshotWeekly.SnapshotDate (last 104w) | Distinct AsOfDate values for helper grain |
| 2.04 | `silver.ItemMasterEnriched` | ItemMaster + LogilityItemStatus (latest) | Carry forward past Lifecycle status from Logility |

### Wave 3 — Pre-compute helpers (7 tables) — built ON TOP of Wave 1+2

| # | Helper | Grain | Logic | KPI |
|---|---|---|---|---|
| 3.01 | `silver.AwdHelper` | (ItemSku, WarehouseCode, AsOfDate) | **Forecast next 3 fiscal months / 13** (monthly granularity from DemandForecast); fallback **shipped last 13W / 13** from SalesShipment | #8 |
| 3.02 | `silver.LastInvoiceHelper` | (ItemSku, WarehouseCode, AsOfDate) | `MAX(InvoiceDate) WHERE InvoiceDate ≤ AsOfDate` | #18 SLOB |
| 3.03 | `silver.MovementFlagHelper` | (ItemSku, WarehouseCode, AsOfDate) | `HasMovementLast17W` = sales movement exists in `FiscalWeekIndicator > -17` | #18, #26 |
| 3.04 | `silver.SafetyStockHelper` | (ItemSku, WarehouseCode, AsOfDate) | Latest SS Target from InventorySnapshotWeekly ≤ AsOfDate | #16, #25 |
| 3.05 | `silver.OnHoldAggregateHelper` | (ItemSku, WarehouseCode) | SUM(TransferQty) GROUP BY from HoldingTransfer current | #27 |
| 3.06 | `silver.PoAggregateHelper` | (ItemSku, WarehouseCode) | SUM(POOnOrderQty + POInTransitQty) GROUP BY from PurchaseOrder | #3, #4 current |
| 3.07 | `silver.MoAggregateHelper` | (ItemSku, WarehouseCode) | SUM(MOOnOrderQty) GROUP BY firm OSTAT | #5 current |

### Wave 4 — Snapshot capture (6 tables, scheduled idempotent)

| # | Snapshot | Frequency | Source | Use |
|---|---|---|---|---|
| 4.01 | `silver.PurchaseOrderSnapshotDaily` | Daily | silver.PurchaseOrder | PO historical trend Phase 1 |
| 4.02 | `silver.ManufacturingOrderSnapshotDaily` | Daily | silver.ManufacturingOrder | MO historical |
| 4.03 | `silver.HoldingTransferSnapshotDaily` | Daily | silver.HoldingTransfer | OnHold historical |
| 4.04 | `silver.LogilityItemStatusSnapshotWeekly` | **Weekly Saturday** | silver.LogilityItemStatus | Inactive/SLOB weekly history Phase 1.5 |
| 4.05 | `silver.AtpSnapshotWeekly` (Phase 2) | Weekly | silver.AtpWeekEnding | ATP historical |
| 4.06 | `silver.AllocatedDemandSnapshotDaily` (Phase 2) | Daily | silver.AllocatedDemandCandidate | Allocated demand history |

### Silver Wave dependencies (execution order)

```
Wave 1 (parallel within tier 0):  ItemMaster, Warehouse, Vendor
Wave 1 (parallel within tier 1):  CostCurrent, InventoryCurrent, ForecastCurrent,
                                   SupplyPlan, SalesShipment, PurchaseOrder,
                                   ManufacturingOrder, HoldingTransfer,
                                   MovementHistory, AtpWeekEnding,
                                   AllocatedDemandCandidate, LogilityItemStatus,
                                   ContainerInfo
Wave 1 (sequential — large):       InventorySnapshotWeekly (557M), ForecastSnapshotDaily (P2)
       │
       ▼
Wave 2:                            TransferIntransitCurrent, ItemUniverse,
                                   AsOfDateSet, ItemMasterEnriched
       │
       ▼
Wave 3:                            AwdHelper, LastInvoiceHelper,
                                   MovementFlagHelper, SafetyStockHelper,
                                   OnHoldAggregateHelper, PoAggregateHelper,
                                   MoAggregateHelper
       │
       ▼
Wave 4 (scheduled job):            5 snapshot captures
```

**Tổng Silver**: ~35 tables (Wave 1: 18 + Wave 2: 4 + Wave 3: 7 + Wave 4: 6) — **nhiều hơn Bronze 32 sources** vì có intermediate.

---

## 3. GOLD — 8 tables (Gold WH)

```
┌──────────────────────────────────────────────────────────────────┐
│ GOLD LAYER (final, exposed to semantic model)                    │
├──────────────────────────────────────────────────────────────────┤
│ 5 DIM tables (conformed):                                         │
│   • DimDate           — daily grain                               │
│   • DimItem           — ItemSku PK, UnavailableFlag, FOB, Cubes  │
│   • DimWarehouse      — WarehouseCode PK, FG flag, IntransitMap  │
│   • DimVendor         — VendorNumber PK                          │
│   • DimRuleVersion    — RuleVersionKey for audit                 │
│                                                                  │
│ 1 HELPER (internal, not exposed):                                │
│   • CogsRollingHelper — Monthly + 52M (fix from 52W naming) + 12M│
│                                                                  │
│ 2 FACT tables (semantic exposed) ⭐                              │
│   • FactInventoryHealthSnapshot                                   │
│       Grain: ItemSku + Warehouse + SnapshotDate + SnapshotType   │
│       Rows: ~178K current × 1 day + ~178K × 143 weeks ≈ 25M      │
│       Cols: 30 (incl Cogs/Classification/Flags)                  │
│                                                                  │
│   • FactInventoryRiskForward                                      │
│       Grain: ItemSku + Warehouse + WeekEndingDate                 │
│       Rows: ~20K active × 13 weeks ≈ 260K                        │
│       Cols: 20 (incl SI/ATP/RevAtRisk)                           │
└──────────────────────────────────────────────────────────────────┘
```

### 3.1 Dim tables

| Dim | Grain | Cols | Source |
|---|---|---|---|
| `DimDate` | DateKey (YYYYMMDD int) | 11 (CalendarDate, WeekEndingDate, FiscalWeek, FiscalWeekIndicator, FiscalMonth, FiscalMonthYear, IsCurrentDate, IsCurrentWeek, IsMonthEnd) | DimDate Bronze direct |
| `DimItem` | ItemSku VARCHAR(50) | 18 (ItemDescription, ItemClassCode/Name, CategoryName, CollectiveClass, SeriesNumber/Name, AfiItemStatus, LifecycleStatus, PrimaryVendor#/Name, Cubes, FobArcPrice, IsFinishedGoodsItem, Discontinued/New flags, **UnavailableFlag**, StatusCodeChangeDate) | silver.ItemMaster |
| `DimWarehouse` | WarehouseCode VARCHAR(10) | 12 (Name, Type, OrderGroup, SourceId, SellableFlag, ControlledFlag, WhereMade, MfgSite, IntransitWhCode, IsFG_Wh, IsMfg_Wh, TotalAvailableCube[P2]) | silver.Warehouse |
| `DimVendor` | VendorNumber VARCHAR(20) | 2 (VendorName) | silver.Vendor |
| `DimRuleVersion` | RuleVersionKey BIGINT | 5 (RuleName, EffectiveStart/End, RuleDescription) | Manual seed v1 |

### 3.2 Gold helper

| Helper | Grain | Logic | KPI |
|---|---|---|---|
| `gold.CogsRollingHelper` | (ItemSku, Wh, FiscalMonth chronological int) | Monthly COGS = QuantityShipped × StandardCost; rolling 12M + **52M** (NOT 52W, fix from earlier bug); window ORDER BY FiscalMonthYear chronological | #12, #22 |

### 3.3 Facts — full column list

#### ⭐ `gold.FactInventoryHealthSnapshot` (current + weekly trend)

```
─ Identity (12 cols) ─
ItemSku, WarehouseCode, SnapshotDate, SnapshotType ('Current'|'Weekly'),
WeekEndingDate, DateKey, FiscalMonth, FiscalMonthYear, IsLatestSnapshot,
SourceSystem, SourceTable, EtlLoadDate

─ Base supply qty (10 cols) ─
OnHandQty, TransferInInTransitQty, POInTransitQty, POOnOrderQty,
MOOnOrderQty, InTransitQty (derived), OnOrderQty (derived),
TotalInventoryCommitmentQty (derived), AllocatedDemandQty, AwdQty

─ Demand & coverage (6 cols) ─
ForecastDemandQty, AwdSource ('Forecast'|'HistoricalFallback'),
WeeksOfSupply (derived), SafetyStockTargetQty, SafetyStockMultiple (derived),
BuildQuantity

─ Classification (7 cols) ─
InventoryClassification ('Inactive'|'Below Target'|'Sweet Spot'|
                         'Over Target'|'Excess'|'Aggressive Excess'|'TB Inventory'),
BelowTargetQty, SweetSpotQty, OverTargetQty, ExcessQty,
AggressiveExcessQty, TBQty

─ Financial (10 cols) ─
StandardCost, FobArcPrice, Cubes,
InventoryValueAtCost, InventoryValueAtRevenue, UsedStorageCube,
PeriodCogs, Cogs52M (renamed from Cogs52W), Cogs12M,
AverageInventoryValueAtCost, ObsoleteValue

─ Status flags (8 cols) ─
LastInvoiceDate, LifecycleStatus, ActiveStatus,
InactiveFlag, SlobFlag, NoMovementFlag, UnavailableFlag,
OnHoldFlag, OnHoldQty, RuleVersionKey
```

**Total: ~53 cols**

#### ⭐ `gold.FactInventoryRiskForward` (forward projection)

```
─ Identity (5 cols) ─
ItemSku, WarehouseCode, WeekEndingDate, DateKey, EtlLoadDate

─ Supply plan numbers (9 cols) ─
BeginningBalanceQty, FirmDemandQty, NetForecastQty,
FirmPurchaseOrderQty, PlannedPurchaseOrderQty, OnOrderTransferInQty,
ShippableInventoryQty, SafetyStockTargetQty, MonthsOfSupply

─ Derived (4 cols) ─
ExpectedDemand14DQty, Inbound14DQty, AllocatedDemandQty,
ATPQty (Week2 = APAT02)

─ Risk flags (6 cols) ─
ATPInStockFlag, ShippableInStockFlag, SINegQty, RevenueAtRiskValue,
WeekFourFlag (exact week 4 only, NOT [today, today+4w]), FobArcPrice

─ Audit ─
RuleVersionKey
```

**Total: ~25 cols**

---

## 4. SEMANTIC MODEL — Power BI

### 4.1 Tables expose (7)

| Type | Tables |
|---|---|
| Dim | DimDate, DimItem, DimWarehouse, DimVendor, DimRuleVersion |
| Fact | FactInventoryHealthSnapshot, FactInventoryRiskForward |
| **Hidden internal** | CogsRollingHelper (gold-side only, không expose) |

### 4.2 Relationships (9, all 1→N, oneDirection)

```
DimDate.DateKey      ──→ FactHealth.DateKey
DimDate.DateKey      ──→ FactRisk.DateKey
DimItem.ItemSku      ──→ FactHealth.ItemSku
DimItem.ItemSku      ──→ FactRisk.ItemSku
DimWarehouse.WhCode  ──→ FactHealth.WarehouseCode
DimWarehouse.WhCode  ──→ FactRisk.WarehouseCode
DimVendor.VendorNum  ──→ DimItem.PrimaryVendorNum (snowflake)
DimRuleVersion       ──→ FactHealth.RuleVersionKey
DimRuleVersion       ──→ FactRisk.RuleVersionKey
```

### 4.3 DAX measures — 30+ measures, 6 groups

| Group | Count | Measures |
|---|---|---|
| Base supply | 8 | Total On Hand Qty, Transfer InTransit Qty, PO In Transit/OnOrder Qty, MO On Order Qty, In Transit Qty, On Order Qty, Total Inv Commitment Qty |
| Demand & coverage | 5 | Allocated Demand Qty, Forecast Demand 13W, AWD, Weeks Of Supply, Safety Stock Target, Safety Stock Multiple |
| Financial | 7 | Inv Value at Cost, Inv Value at Revenue, Used Storage Cube, Weighted Std Cost, Std Selling Price Avg, Total COGS, COGS 52M (renamed), Avg Inv Value at Cost, Inventory Turns |
| Risk & In-Stock | 6 | Revenue at Risk, SI Neg Qty, Active SKU/SKU-WH Count, ATP/Shippable In Stock Count + Rate |
| Lifecycle/Flags | 6 | Inactive/SLOB/SLOB Value/Obsolete Ratio/On Hold Qty+Ratio/No Movement/Unavailable Item Count |
| Classification | 7 | 7 measures (1 per classification bucket value) |

---

## 5. KPI COVERAGE — 30 KPI BRD detail map

| # | KPI | Phase 1 | Phase 2 | Measure | Source tables |
|---|---|---|---|---|---|
| 1 | On Hand Quantity | ✅ | | Total On Hand Qty | ITEMBL.MOHTQ (+ FG filter) |
| 2 | Transfer InTransit | ✅ current / ⏭️ historical | | Transfer InTransit Qty | ITEMBL + Warehouse intransit map |
| 3 | PO In Transit Qty | ✅ | | PO In Transit Qty | PoDetail status=20 + PoMaster (SC) |
| 4 | PO On Order Qty | ✅ | | PO On Order Qty | PoDetail status=10 + PoMaster (SC) |
| 5 | MO On Order Qty | ✅ (placeholder OSTAT) | | MO On Order Qty | MOMAST |
| 6 | Allocated Demand | ✅ (Flag=2 fix) | | Allocated Demand Qty | OpenOrderDetail + Header |
| 7 | Forecast Demand 13W | ✅ (DemandForecast current) | | Forecast Demand 13W | DemandForecast |
| 8 | AWD | ✅ (with fallback) | | AWD | DemandForecast + InvoiceDetail fallback |
| 9 | Inventory Value @ Cost | ✅ | | Inventory Value at Cost | ITEMBL × ITMRVA |
| 10 | Standard Cost | ✅ | | Weighted Std Cost | ITMRVA STID='000' |
| 11 | Standard Selling Price | ✅ (6% null) | | Standard Selling Price Avg | DimItemMaster.FOBArcPrice |
| 12 | COGS | ✅ (rolling fix needed) | | Total COGS | InvoiceDetail × ITMRVA |
| 13 | Used Storage Cube | ✅ | | Used Storage Cube | ITEMBL × Cubes |
| 14 | Total Available WH Cube | | ⏭️ Phase 2 | — | File Excel external |
| 15 | Container Count | | ⏭️ Phase 2 | — | Container table |
| 16 | Safety Stock Target | ✅ | | Safety Stock Target | DemandInventorySnapshotWeekly.dinSafetyStock |
| 17 | Inactive Item | ✅ snapshot-aware | ⏭️ past via Logility | Inactive Item Count | AfiStatus + OnHand+OnOrder + Logility |
| 18 | SLOB | ✅ (NULL handling fix) | ⏭️ past via Logility | SLOB Value/Count | AfiStatus + LastInvoice 17W |
| 19 | Revenue at Risk | ✅ (Week4 scope fix) | | Revenue at Risk | SupplyPlanDetail.spdShippableInv × FOBArc |
| 20 | Dim (Lifecycle/Active/Vendor/WH) | ✅ | ⏭️ past Lifecycle via Logility | Dim slicers | DimItem/DimWh/DimVendor |
| 21 | FG Filter | ✅ | | filter | ItemClassCode + Warehouse list |
| 22 | Turns | ✅ (Cogs52M fix from 52W) | | Inventory Turns | derived #12 + #9 |
| 23 | ATP In-Stock Rate | ✅ (APAT01-43 UNPIVOT fix) | | ATP In Stock Rate | ATPSUM Week2 |
| 24 | Shippable Inv In-Stock Rate | ✅ | | Shippable In Stock Rate | SupplyPlanDetail.spdShippableInv |
| 25 | Safety Stock Multiple | ✅ | | Safety Stock Multiple | derived #1/#16 |
| 26 | Obsolete Ratio | ✅ | | Obsolete Ratio | derived from SLOB |
| 27 | On-Hold Ratio | ✅ current | ⏭️ past info missing | On Hold Ratio | TFRDTL + TFRHDR |
| 28 | Aged Inventory % | | ⏭️ Phase 2 | — | Serial source missing |
| 29 | Capacity Utilization | | ⏭️ Phase 2 | — | File Excel external |
| 30 | Total Inv Commitment | ✅ | | Total Inv Commitment Qty | sum components |

### Coverage Summary

```
✅ Phase 1 buildable (post bug fix)   : 26 KPI ≈ 87%
⏭️ Phase 2 (source missing/external)  :  4 KPI (14, 15, 28, 29)
```

**Sau khi fix 5 HIGH bugs trong QC report**:
- Allocated Demand (Flag=2 fix) → ✅
- COGS / Turns (Cogs52M + ORDER BY FiscalMonthYear fix) → ✅
- Revenue at Risk (WeekFour scope fix) → ✅
- ATP In-Stock Rate (UNPIVOT APAT01-43 fix) → ✅

→ **5/5 broken KPI** trở lại buildable, đạt 26/30 = **87% coverage Phase 1**.

---

## 6. LINEAGE DIAGRAMS

Đã có sẵn 2 diagram + 1 master plan:

| File | Purpose |
|---|---|
| `FinalDecision/InventoryHealth_DataLineage.svg` (137 KB, 4288 lines mermaid) | Detailed lineage per table (32 bronze + 21 silver + 8 gold) |
| `FinalDecision/InventoryHealth_DataLineage_Overview.svg` (37 KB) | Layer summary (Bronze → Silver → Gold → Semantic) |
| `FinalDecision/InventoryHealth_DataLineage.mmd` | Source — có thể update với 4-wave silver architecture |

**Recommendation**: update lineage diagram với 4-wave silver (Wave 1/2/3/4) cho rõ hơn data flow.

---

## 7. ASSUMPTIONS HỢP LÝ (chốt cứng để không block Phase 1)

### Đã chốt với Aric / business

| # | Assumption | Source |
|---|---|---|
| 1 | Snapshot = Daily current + Weekly history | Aric confirmed |
| 2 | Storage = SupplyChain Processing WH (silver) + Gold WH | Aric confirmed |
| 3 | Naming = PascalCase, business name silver (no slv_ prefix) | Aric confirmed |
| 4 | 2 facts only + financial folded into snapshot fact | Aric confirmed |
| 5 | PK = business key (no surrogate) | Aric confirmed |
| 6 | DimItem scope = FG only (filter `LIKE 'Z%K'`) | From bronze probe: 99.98% FG match DimItem |
| 7 | ItemAllocationFlag = **2** (not 1) for Allocated Demand | Bronze probe |
| 8 | ATPSUM Week2 → APAT02 + WeekEnding = APWK01 + 7 days | Bronze probe + sheet note |
| 9 | DemandForecast (current) replaces stale DemandForecastSnapshotWeekly | Probe finding |
| 10 | PoDetail Enterprise (mới load) > SC.podetail_v2 | DE just loaded |

### Cần Robert / business sign-off (placeholder — assumes correct)

| # | Assumption | Placeholder value | Confidence |
|---|---|---|---|
| 11 | MOMAST OSTAT firm codes | `IN ('10','40','45')` | Medium (covers 37% open candidates) |
| 12 | Classification thresholds | Below=0.5×SS, Sweet=1.5×SS, Over=17×AWD, Excess=52×AWD, AggrExcess=104×AWD | Medium (BRD v1 reference) |
| 13 | SLOB lookback | 17 weeks | High (BRD explicit) |
| 14 | WeekFour scope | 1 exact week (after fix) | High (BRD "At Week Four Ending") |
| 15 | FG warehouse list | `('1','5','15','17','28','335','ECR')` for sales/ATP context | Medium (sheet alt list 11 codes for network context) |
| 16 | Allocated Demand semantic | OpenOrderDetail ItemAllocationFlag=2 + QtyShipped=0 | High (Aric confirmed) |

### Cần DE confirm (work in parallel)

| # | Pending | Workaround |
|---|---|---|
| 17 | PoMaster load Enterprise | Use SC.dbo.pomaster |
| 18 | Logility load Enterprise | Use SC.dbo.logility_demandfulfillment |
| 19 | ItemBalance load Enterprise | Fallback DemandInventorySnapshotWeekly |
| 20 | Forecast Weekly stale 2y root cause | Use DemandForecast (current) |
| 21 | Inventory Weekly stale 10w | Live with caveat |
| 22 | ATPSUM "8AM 2nd version" mechanism | Use latest snapshot |
| 23 | PowerBI_SupplyChain.WarehouseMaster sheet ref | Use AshleyWarehouseMaster |

---

## 8. CODE FILES — Hiện trạng

| Path | Status |
|---|---|
| `_scripts/sql/01_setup.sql` | ✅ schemas + watermark + 4 snapshot DDL |
| `_scripts/sql/02_silver_dims.sql` | ⚠️ Wave 1 dim — cần update column naming (Series/Category) |
| `_scripts/sql/03_silver_base.sql` | ⚠️ Wave 1 base — cần 4 HIGH fixes (Flag=2, FG filter, PoDetail source, ATPSUM UNPIVOT) |
| `_scripts/sql/04_silver_helpers.sql` | ⚠️ Wave 3 helpers — cần reorder per wave |
| `_scripts/sql/05_silver_snapshots.sql` | ✅ Wave 4 — Saturday detection bug (M1) |
| `_scripts/sql/06_gold_dims.sql` | ✅ 5 dim procs |
| `_scripts/sql/07_gold_helpers.sql` | ⚠️ CogsRollingHelper — cần fix ORDER BY FiscalMonthYear + rename 52M |
| `_scripts/sql/08_gold_facts.sql` | ⚠️ 2 facts — cần WeekFour scope fix |
| `_scripts/sql/09_master.sql` | ⚠️ Saturday detection bug |
| `_scripts/sql/10_verify.sql` | ⚠️ walrus `:=` syntax bug |
| `_scripts/sql/99_cleanup_silver.sql` | ✅ |
| `_scripts/sql/99_cleanup_gold.sql` | ✅ |
| `FinalDecision/semantic_model/InventoryHealth_SemanticModel.tmdl` | ✅ |
| `FinalDecision/semantic_model/InventoryHealth_Measures.dax` | ⚠️ AWD measure DISTINCTCOUNT bug |

**Total bugs to fix**: 5 HIGH + 6 MEDIUM + 7 LOW = 18 (per QC report).

---

## 9. EXECUTION ROADMAP

### Sprint 0 (this week) — Pre-fix + DE chase

- [ ] Aric soạn message DE chase 3 missing tables + bổ sung 8 items mới (ATPSUM clarify, schema clarify)
- [ ] Aric email Robert: 6 business rule confirms
- [ ] Code maintainer: fix 5 HIGH bugs (Flag=2, FG filter, PoDetail Enterprise, ATPSUM UNPIVOT, WeekFour, Cogs52M rename + ORDER BY)
- [ ] Code maintainer: fix 6 MEDIUM bugs (Saturday detection, walrus, SLOB NULL, AWD DAX, CategoryName clarify)

### Sprint 1 (next 1-2 weeks) — Deploy DEV + test

- [ ] Deploy 01-05 silver SQL → dev Processing WH
- [ ] Run silver.usp_RefreshAll → smoke test row counts
- [ ] Deploy 06-08 gold SQL → dev Gold WH
- [ ] Run gold.usp_RefreshAll → KPI smoke test
- [ ] Load Power BI Desktop → DirectLake → verify 30 DAX measures
- [ ] **CLEANUP** dev WH (99_cleanup_*.sql)

### Sprint 2 (Phase 1.5) — Logility certification

- [ ] DE load Logility Enterprise + confirm status code mapping
- [ ] Update silver.LogilityItemStatus to certified source
- [ ] Backfill Inactive/SLOB historical
- [ ] Update DimItem.LifecycleStatus with time-aware Logility

### Sprint 3 (Phase 2) — Production deploy

- [ ] DE load PoMaster + ItemBalance Enterprise
- [ ] Switch silver.PurchaseOrder to fully Enterprise sources
- [ ] Switch ItemBalance fallback if DE done
- [ ] Fabric Pipeline scheduling
- [ ] Production cutover

---

## 10. FILE INDEX (mọi tài liệu sinh ra trong session)

| Category | File |
|---|---|
| **Plans** | `FinalDecision/InventoryHealth_ETL_Plan_v3.md` (concise overview) |
| | `FinalDecision/InventoryHealth_FULL_BUNDLE.md` (4,288 lines all-in-one) |
| | **`FinalDecision/Master_Architecture_Plan.md`** (this — comprehensive picture) |
| **QC** | `FinalDecision/Person_AB_QC_Report.md` (18 bugs, 30 KPI verify) |
| **Source truth** | `_artifacts/bronze_source_truth.json` + `.md` (32 tables, 1000+ cols) |
| | `_artifacts/source_corrections.md` |
| **SQL** | `_scripts/sql/01-10.sql` (10 files Silver+Gold ETL) |
| | `_scripts/sql/99_cleanup_silver.sql` + `99_cleanup_gold.sql` |
| **Semantic** | `FinalDecision/semantic_model/InventoryHealth_SemanticModel.tmdl` |
| | `FinalDecision/semantic_model/InventoryHealth_Measures.dax` |
| **Lineage** | `FinalDecision/InventoryHealth_DataLineage.svg` + `.png` + `.mmd` |
| | `FinalDecision/InventoryHealth_DataLineage_Overview.svg` + `.png` + `.mmd` |
| **Probe scripts** | `_scripts/probe_all_sources.py` + `probe_itembalance.py` |
| | `_scripts/sql_lib.py` |

---

## 11. KỲ VỌNG CUỐI CÙNG

```
┌─────────────────────────────────────────────────────────────────┐
│  WHEN WE FINISH PHASE 1 PRODUCTION:                              │
├─────────────────────────────────────────────────────────────────┤
│  ✅ 32 Bronze sources verified                                   │
│  ✅ 35 Silver tables (4 waves)                                   │
│  ✅ 8 Gold tables (5 dim + 1 helper + 2 fact)                    │
│  ✅ 7 Semantic tables expose                                     │
│  ✅ 30 DAX measures                                              │
│  ✅ 26/30 KPI buildable Phase 1 (87% coverage)                   │
│  ✅ Daily refresh via Fabric Pipeline                            │
│  ✅ Power BI DirectLake report                                   │
│                                                                  │
│  ⏭️ Phase 2 deliver:                                             │
│      • KPI #14 Total Avail WH Cube (file Excel governed)         │
│      • KPI #15 Container Count (PO/container join)               │
│      • KPI #28 Aged Inventory % (serial source)                  │
│      • KPI #29 Capacity Utilization (derived #14 + #13)          │
│      • Logility historical certified Inactive/SLOB               │
└─────────────────────────────────────────────────────────────────┘
```
