# Inventory Health ETL — Combined Person A + B QC Report

> Pure-read QC review của toàn bộ Silver + Gold + Semantic. Generated 2026-05-15 sau khi probe Bronze sample + cross-check BRD + paper review SQL bundle.
>
> **Scope**: pure read, KHÔNG tạo bất cứ object nào trong warehouse. Nếu execute test sau này → bắt buộc chạy cleanup script (`_scripts/sql/99_cleanup_silver.sql` + `99_cleanup_gold.sql`).
>
> **Outcome**: 18 bugs identified (5 HIGH critical, 6 MEDIUM, 7 LOW). 30 KPI mapping verified với 7 ⚠️ flags cần business sign-off.

---

## 1. Executive summary

| Layer | Files reviewed | Procs reviewed | Bugs found |
|---|---|---|---|
| Silver | 5 SQL files (01-05) | 25 procs | 7 (1 HIGH + 4 MEDIUM + 2 LOW) |
| Gold | 3 SQL files (06-08) | 8 procs | 6 (3 HIGH + 2 MEDIUM + 1 LOW) |
| Master + Verify | 2 SQL files (09-10) | 2 procs | 2 (2 HIGH) |
| TMDL + DAX | 2 files | 30 measures + 9 rel | 3 (1 HIGH + 1 MEDIUM + 1 LOW) |
| **TỔNG** | **12 files** | **35 procs + 30 measures** | **18 bugs (5H/6M/7L)** |

---

## 2. Bronze probe evidence (read-only sample data)

### 2.1 Top OnHand SKU-WH (combo 1)

| ItemSku | WH | OnHand (MOHTQ) | ItemClass | AfiStatus | FOB | Cubes | StdCost | IVC (manual calc) |
|---|---|---|---|---|---|---|---|---|
| 52293 | 190 | 8,076,000 | BEMS | **NULL** | **NULL** | **NULL** | 0.074 | $597K |
| 78892 | 1 | 5,572,311 | UHS | **NULL** | **NULL** | **NULL** | 0.0075 | $42K |
| 77564 | ECR | 3,598,029 | UFRH | **NULL** | **NULL** | **NULL** | 0.347 | $1.25M |
| 01237 | 1 | 2,630,767 | HS | **NULL** | **NULL** | **NULL** | 0.0052 | $14K |
| H0089-033 | 17 | 2,047,714 | UFHW | **NULL** | **NULL** | **NULL** | 0.087 | $177K |

🚨 **Critical**: All top OH items have `AfiStatus=NULL`, `FOB=NULL`, `Cubes=NULL` → **không có trong DimItemMaster**.

### 2.2 ITEMBL ↔ DimItemMaster coverage

| Scope | Distinct ItemSku | Matched DimItem | Unmatched |
|---|---|---|---|
| **All ITEMBL items** | 558,057 | 179,593 (32%) | 378,464 (68%) |
| **FG-class filter (`LIKE 'Z%K'`)** | 5,673 | **5,672 (99.98%)** | 1 |

→ DimItemMaster covers FG items only. ITEMBL covers raw materials + components + FG. Without FG filter, fact table sẽ có 68% rows với NULL dim fields.

### 2.3 Inactive candidates (AfiStatus IN D/R + OnHand=0)

5 sample items tìm thấy with StatusChangeDate=2026-05-14 → recent status change

### 2.4 SLOB candidates (LastInvoice < today-17W, AfiStatus<>'N')

5 sample items, all WH=335, WeeksSinceLast=23 — Q4-2025 last sale.

### 2.5 SupplyPlanDetail freshness

| Metric | Value |
|---|---|
| Total rows | 3,879,820 |
| Distinct snapshot dates | **1 (today 2026-05-16)** |
| spdShippableInventory negative | 334,420 (8.6%) — Revenue at Risk candidates |
| Coverage ↔ DimItemMaster | 93.6% (19,325/20,641) |

### 2.6 ATPSUM column structure

| Metric | Value |
|---|---|
| APAT cols | **APAT01..APAT43** (43 cols, not 27) |
| APWK cols | **APWK01 ONLY** (1 col) |
| Total rows | 296,778 |
| Week1 positive (APAT01>0) | 57,482 |
| Week2 positive (APAT02>0) | 57,663 |

🚨 **Critical**: Silver UNPIVOT references `APWK01-27` but only `APWK01` exists → compile error.

### 2.7 MOMAST OSTAT distribution

| OSTAT | Rows | % |
|---|---|---|
| '55' | 165,709 | 66% — most common (likely Closed/Released) |
| **'10'** | 60,347 | 24% — Firm/Open candidate |
| **'40'** | 18,951 | 8% — Open candidate |
| **'45'** | 12,303 | 5% — Open candidate |
| '99' | 84 | <1% |
| blank | 49 | <1% |

→ Plan v3 placeholder `IN ('10','40','45')` covers 36% rows (open) reasonably; '55' is closed (exclude).

### 2.8 OpenOrderDetail ItemAllocationFlag

| Flag | Rows | NotShipped | Shipped |
|---|---|---|---|
| 0 | 16,802 | 16,608 | 194 |
| **2** | **901,411** | **900,601** | 810 |

🚨 **Critical**: Allocated value is **2, NOT 1**. Silver code `WHERE ItemAllocationFlag = 1` returns 0 rows.

### 2.9 AshleyWarehouseMaster — FG list verification

12 WH found in scope list. **Chỉ '335' có `wmaSellableWarehouse=True`** — other 11 = False. Intransit mapping verified:
- 1→A, 5→B, 15→L, 17→N, 28→T, 335→G, ECR→E, 3→W, 12→M, 16→V, 19→S, 42→F

### 2.10 ITMRVA STID='000' dedup necessity

| Metric | Value |
|---|---|
| Distinct items at STID='000' | 599,212 |
| **Dup items at STID='000'** | **0** |
| 2 dup rows reported earlier | Were at **STID='042'**, not '000' |

→ Silver `usp_Build_CostCurrent` filter STID='000' đã unique. ROW_NUMBER dedupe **không cần thiết** (harmless but optimization opportunity).

### 2.11 DimDate format

| Column | Sample | Type | Range |
|---|---|---|---|
| FiscalMonth | 5 | INT | 1-12 (cycle, not chronological) |
| FiscalMonthYear | 202605 | INT | YYYYMM chronological |
| FiscalWeek | 20 | INT | 1-53 |
| FiscalWeekIndicator | 0 | INT | 0=current, negative=past |

🚨 **Critical**: CogsRollingHelper uses `ORDER BY FiscalMonth` (cycle 1-12) cho rolling window → SUM wrong months across years.

### 2.12 DemandForecastSnapshotWeekly vs DemandForecast (current)

| Source | Rows | LastSnap | Freshness |
|---|---|---|---|
| `SupplyChain_Enh_1.DemandForecastSnapshotWeekly` | 306M | 2024-03-25 | **Stale 2.1 năm** 🚨 |
| `Wholesale_DemandPlanning_AFI.DemandForecast` (current) | 12.27M | 2026-05-16 | **Fresh today** ✅ |

→ Plan đang dùng SnapshotWeekly stale → AWD logic broken. Đề xuất switch.

### 2.13 DimItemMaster NULL %

| Col | Total | NULL | % |
|---|---|---|---|
| Cubes | 382,302 | 1 | 0.0003% ✅ |
| FOBArcPrice | 382,302 | 23,441 | **6.13%** (~6%) ⚠️ |
| AFIItemStatus | 382,302 | 0 | 0% ✅ |

---

## 3. Bug log — 18 issues (5 HIGH / 6 MEDIUM / 7 LOW)

### 🚨 HIGH severity (5)

| # | Section / File | Issue | Impact | Fix proposed |
|---|---|---|---|---|
| H1 | Silver `03_silver_base.sql` `usp_Build_AllocatedDemandCandidate` | Filter `ItemAllocationFlag = 1`. Real value is `2` (901,411 rows). | KPI #6 Allocated Demand = 0 always | `WHERE ItemAllocationFlag = 2 AND ISNULL(QuantityShipped,0)=0` |
| H2 | Silver `03_silver_base.sql` `usp_Build_AtpWeekEnding` | UNPIVOT references `APWK01..APWK27` nhưng table chỉ có `APWK01` (1 col). | Proc compile fail → silver.AtpWeekEnding empty → ATP In-Stock Rate broken | Derive WeekEndingDate từ APWK01 + offset; OR mark Phase 2 conditional |
| H3 | Silver `03_silver_base.sql` `usp_Build_InventoryCurrent` | KHÔNG filter FG class. Pulls all 558K items, 68% miss DimItemMaster. | Gold fact rows with NULL Class/FOB/Cubes (68%) — Inventory Classification distorted | Add filter: `LEFT(LTRIM(RTRIM(b.ITCLS)),1)='Z' AND RIGHT(LTRIM(RTRIM(b.ITCLS)),1)='K'` (FG class) — OR filter by FG warehouse list |
| H4 | Gold `07_gold_helpers.sql` `usp_Build_CogsRollingHelper` | Window `ORDER BY FiscalMonth` — FiscalMonth=1-12 cycle, NOT chronological | Rolling sum wraps around year boundary → wrong Cogs52W, Cogs12M | `ORDER BY FiscalMonthYear` (YYYYMM int) |
| H5 | Gold `08_gold_facts.sql` `usp_Build_FactInventoryRiskForward` | `WeekFourFlag` filter `WeekEndingDate ∈ [today, today+4w]` = 5 weeks. BRD §6.3 nói **"At Week Four Ending"** = 1 specific week | Revenue at Risk over-aggregates 5w instead of 1 | `CASE WHEN WeekEndingDate = DATEADD(week, 4, today) THEN 1 ELSE 0` — chỉ exact week 4 |

### ⚠️ MEDIUM severity (6)

| # | Section / File | Issue | Impact | Fix proposed |
|---|---|---|---|---|
| M1 | Master `09_master.sql` Saturday detection | Formula `((@@DATEFIRST + 5) % 7 + 1)` với DATEFIRST=7 returns 6, but Saturday weekday=7 with default | Logility weekly snapshot **never fires** | `IF DATENAME(weekday, SYSUTCDATETIME()) = 'Saturday'` |
| M2 | Verify `10_verify.sql` L76-79 | Python walrus `:=` không phải T-SQL | Compile fail when run | Remove `:=` syntax, just reference column |
| M3 | Gold/DAX naming `Cogs52W` | Actually 52 months trailing (CogsRollingHelper uses ROWS 51 PRECEDING với FiscalMonth grain monthly) | Misleading column name + DAX measure label sai semantic | Rename `Cogs52M` hoặc fix grain to weekly |
| M4 | Gold `08_gold_facts.sql` SLOB flag | `ISNULL(LastInvoiceDate, '1900-01-01') < DATEADD(week,-17,SnapshotDate)` → SKU never invoiced → SLOB=1 | Items new (NewItemFlag=1) without first invoice will be flagged SLOB incorrectly | Add `AND LastInvoiceDate IS NOT NULL` hoặc exclude New items |
| M5 | DAX `InventoryHealth_Measures.dax` `AWD` measure | `DIVIDE(SUM(AwdQty), DISTINCTCOUNT(ItemSku))`. 1 item × 3 WH → divides by 1, not 3 | AWD measure overstated for multi-WH items | `DIVIDE(SUM(AwdQty), COUNTROWS(SUMMARIZE(fact, ItemSku, WarehouseCode)))` |
| M6 | Silver `02_silver_dims.sql` `usp_Build_ItemMaster` | `DimItemMaster.RetailCategoryName` dùng làm "Category" but BRD intent có thể là different field | "Category" semantic uncertain → DimItem.CategoryName might mislead users | Verify với business which category attribute BRD intended (RetailCategoryName vs DiscountClass vs SalesClass etc.) |

### 🟡 LOW severity (7)

| # | Section / File | Issue | Impact | Fix proposed |
|---|---|---|---|---|
| L1 | Silver `03_silver_base.sql` `usp_Build_CostCurrent` | ROW_NUMBER dedupe at STID+ITNBR not needed (0 dups at STID='000') | Wasted compute | Optional simplify — remove ROW_NUMBER (low priority since correctness OK) |
| L2 | Silver `03_silver_base.sql` `usp_Build_PurchaseOrder` | Source = SC `dbo.podetail_v2`, but Enterprise.PoDetail = 0 rows | When Enterprise reloaded, swap source path. 1 dup key handled by ROW_NUMBER | Document in code comment for future migration |
| L3 | Silver `03_silver_base.sql` `usp_Build_ManufacturingOrder` | OSTAT firm filter `IN ('10','40','45')` placeholder. Real distribution: 24%+8%+5%=37% rows | Robert chưa confirm firm definition | Confirm with Robert; current covers 91K rows (open) vs 165K closed |
| L4 | Silver `03_silver_base.sql` `usp_Build_HoldingTransfer` | `TransferLine` synthesized via ROW_NUMBER (TFRDTL has no obvious line col) | Snapshot capture line numbering may be inconsistent across runs if ORDER BY ties | Add deterministic ORDER BY (e.g. include rowversion if exists) |
| L5 | Gold `08_gold_facts.sql` Health fact `ti_curr` CTE | Transfer InTransit chỉ current state, no Weekly historical capture | Weekly historical rows have NULL TransferInInTransitQty | Phase 2: derive from silver.InventorySnapshotWeekly filter intransit WH codes |
| L6 | Gold `08_gold_facts.sql` Pass 2 UPDATE `avgivc` CTE | DISTINCT on (Item, Wh, FiscalMonthYear, IVC, FiscalMonth) may produce multiple rows per (Item, Wh, FiscalMonthYear) if IVC values differ within same month | Window avg may double-count | DISTINCT on (Item, Wh, FiscalMonthYear) + aggregate IVC first |
| L7 | DAX `SLOB Value` measure | `CALCULATE(SUM(ObsoleteValue), SlobFlag=1)`. ObsoleteValue đã chỉ có giá trị khi SLOB → filter trùng lặp | Redundant but not wrong | Simplify to `SUM(ObsoleteValue)` |

---

## 4. KPI cross-check matrix (30 KPI BRD) — verified

| # | KPI BRD | Fact / Source | Status | Note |
|---|---|---|---|---|
| 1 | On Hand Quantity | FactHealth.OnHandQty | ✅ | MOHTQ (not PHYOH) |
| 2 | Transfer InTransit | FactHealth.TransferInInTransitQty | ⚠️ | Current only, no Weekly historical (L5) |
| 3 | PO In Transit Qty | FactHealth.POInTransitQty | ⚠️ | SC replacement, status=20 |
| 4 | PO On Order Qty | FactHealth.POOnOrderQty | ⚠️ | SC replacement, status=10 |
| 5 | MO On Order Qty | FactHealth.MOOnOrderQty | ⚠️ | OSTAT firm chưa confirm (L3) |
| 6 | **Allocated Demand Qty** | FactRisk.AllocatedDemandQty | **🚨 BROKEN (H1)** | Flag value = 2, code filters 1 → always 0 |
| 7 | Forecast Demand Qty | FactRisk.NetForecastQty | ⚠️ | Forecast Snapshot stale 2 năm |
| 8 | **AWD** | FactHealth.AwdQty | **⚠️ Degraded** | Fallback historical only (forecast stale); DAX bug M5 |
| 9 | Inventory Value at Cost | FactHealth.InventoryValueAtCost | ⚠️ | Distorted by 68% no-DimItem rows (H3) |
| 10 | Standard Cost | DimItem-related | ✅ | UCDEF STID='000' verified |
| 11 | Standard Selling Price | DimItem.FobArcPrice | ⚠️ | 6.13% NULL acceptable |
| 12 | **COGS** | FactHealth.PeriodCogs | **🚨 Wrong (H4)** | Rolling window ORDER BY wrong |
| 13 | Used Storage Cube | FactHealth.UsedStorageCube | ⚠️ | Distorted by NULL Cubes for non-FG items |
| 14 | Total Available Warehouse Cube | DimWarehouse.TotalAvailableWarehouseCube | — | Phase 2 (NULL) |
| 15 | Container Count | — | — | Phase 2 |
| 16 | Safety Stock Target | FactHealth.SafetyStockTargetQty | ✅ | dinSafetyStock from snapshot |
| 17 | Inactive Item | FactHealth.InactiveFlag | ⚠️ | snapshot-aware Phase 1 OK |
| 18 | SLOB | FactHealth.SlobFlag | ⚠️ | NULL LastInvoice handling (M4) |
| 19 | **Revenue at Risk** | FactRisk.RevenueAtRiskValue | **🚨 Wrong (H5)** | WeekFourFlag aggregates 5w not 1 |
| 20 | Lifecycle Status | DimItem.LifecycleStatus | ✅ | |
| 21 | Active Status | DimItem.LifecycleStatus<>'Inactive' | ✅ | |
| 22 | Vendor | DimVendor.VendorName | ✅ | Snowflake via DimItem |
| 23 | DC/WH | DimWarehouse.WarehouseCode | ✅ | |
| 24 | On Hold Status / Ratio | FactHealth.OnHoldFlag/OnHoldQty | ⚠️ | snapshot-aware Phase 1 |
| 25 | FG Filter (Item) | DimItem.IsFinishedGoodsItem | ✅ | LIKE 'Z%K' |
| 26 | **Turns** | derived | **🚨 Wrong (H4+M3)** | Cogs52W actually 52-month + ORDER BY bug |
| 27 | ATP In-Stock Rate | FactRisk.ATPInStockFlag | **🚨 Broken (H2)** | UNPIVOT fails — APWK missing |
| 28 | Shippable Inv In-Stock Rate | FactRisk.ShippableInStockFlag | ✅ | SI>0 — spdShippableInventory direct |
| 29 | Safety Stock Multiple | derived | ✅ | OnHand/SS |
| 30 | Obsolete Ratio | derived from SLOB Value / IVC | ⚠️ | Inherits SLOB null handling (M4) |
| 31 | On Hold Ratio | derived | ⚠️ | Phase 1 snapshot-aware |
| 32 | Aged Inventory | — | — | Phase 2 |
| 33 | Capacity Utilization | derived | — | Phase 2 (no cube source) |

**Score Phase 1**:
- ✅ **Clean buildable**: 10 KPI
- ⚠️ **Buildable with caveat**: 14 KPI
- 🚨 **BLOCKED by bugs**: 5 KPI (Allocated Demand, COGS, Turns, Revenue at Risk, ATP In-Stock Rate)
- — Defer Phase 2: 4 KPI

---

## 5. End-to-end trace — Combo 1 (top OH item 52293)

| Layer | Value |
|---|---|
| **Bronze ITEMBL** | ItemSku=52293, WH=190, MOHTQ=8,076,000, ITCLS=BEMS |
| **Bronze ITMRVA STID='000'** | UCDEF=0.07399 |
| **Bronze DimItemMaster** | **❌ Item NOT FOUND** (FOB/Cubes/AfiStatus all NULL) |
| **Silver InventoryCurrent** | OnHandQty=8,076,000 (passes through) |
| **Silver CostCurrent** | StandardCost=0.07399 |
| **Silver ItemMaster** | **❌ No row** (no DimItem source) |
| **Gold DimItem** | **❌ No row** |
| **Gold FactInventoryHealthSnapshot** | Has row, but LEFT JOIN DimItem returns NULL → FobArcPrice=NULL, Cubes=NULL → IVR=0, UsedCube=0 |
| **Manual IVC** | 8,076,000 × 0.07399 = **$597,559** |
| **Manual UsedCube** | 8,076,000 × NULL = **NULL** ⚠️ — KPI #13 missing |
| **Manual IVR** | 8,076,000 × NULL = **NULL** ⚠️ — KPI #9 (revenue version) missing |

→ Confirms **bug H3**: non-FG items make it into fact with NULL critical attributes.

---

## 6. Cross-layer dependency review

| Dependency | Risk |
|---|---|
| Silver.AwdHelper → DemandForecastSnapshotWeekly (stale 2y) | AWD always falls back to historical → KPI #8 degraded |
| Silver.AtpWeekEnding → ATPSUM (APWK01 only) | UNPIVOT broken → Risk fact ATPQty all NULL |
| Silver.AllocatedDemandCandidate → OpenOrderDetail (flag=2 reality) | Filter wrong → 0 rows |
| Silver.InventoryCurrent → ITEMBL (no FG filter) | 68% rows orphan from DimItem |
| Gold.CogsRollingHelper → ORDER BY FiscalMonth (cycle) | Rolling wrong direction |
| Gold.FactInventoryHealthSnapshot → SLOB NULL handling | New items wrongly SLOB-flagged |
| Gold.FactInventoryRiskForward → WeekFourFlag 4-week range | Revenue at Risk over-aggregates |
| Master orchestration → Saturday detection broken | Logility weekly snapshot never runs |
| Verify smoke → walrus `:=` syntax | Compile fail |

---

## 7. Recommended fix order (sequential — easier to verify)

### Priority 1 — UNBLOCK Phase 1 (5 HIGH bugs)
1. **H2 ATPSUM UNPIVOT** — verify if only APWK01 or if other APWK exist under different naming
2. **H1 ItemAllocationFlag = 2** — single character fix
3. **H3 FG filter trong InventoryCurrent** — add WHERE clause
4. **H4 CogsRollingHelper ORDER BY FiscalMonthYear** — single field rename
5. **H5 WeekFourFlag** — change filter logic to single week-4

### Priority 2 — Master + verify (2 HIGH bugs)
6. **M1 Saturday detection** — replace formula with `DATENAME='Saturday'`
7. **M2 Walrus `:=` syntax** — replace with column ref

### Priority 3 — Naming + edge cases (4 MEDIUM)
8. **M3 Cogs52W rename to 52M** (or fix grain to weekly)
9. **M4 SLOB NULL last invoice** — exclude new items
10. **M5 DAX AWD measure** — use Item+WH combo
11. **M6 Category column semantic** — confirm with business

### Priority 4 — Optimization + Phase 2 (7 LOW)
12-18. L1-L7 — fix during cleanup phase

---

## 8. Cleanup scripts ready (nếu execute test sau)

Đã chuẩn bị 2 cleanup script ở next step:
- `_scripts/sql/99_cleanup_silver.sql` — DROP all silver objects (procs + tables + schema)
- `_scripts/sql/99_cleanup_gold.sql` — DROP all gold objects

Chạy sau khi `EXEC silver.usp_RefreshAll` + `EXEC gold.usp_RefreshAll` để clean dev WH về trạng thái ban đầu.

---

## 9. External issues từ DE (status check)

| Issue | Status | Action pending |
|---|---|---|
| Enterprise.PoDetail = 0 rows | Đã email DE | Chờ reload |
| Enterprise.PoMaster không tồn tại | Đã email DE | Chờ create dataflow |
| Enterprise.Logility không tồn tại | Đã email DE | Chờ promote + status code mapping |
| Inventory_Enh_History.ItemBalance không tồn tại | Đã email DE | Chờ load |
| DemandForecastSnapshotWeekly stale 2 năm | Đã phát hiện | Email DE (1 lần) + đề xuất switch sang `Wholesale_DemandPlanning_AFI.DemandForecast` (fresh) |
| DemandInventorySnapshotWeekly stale 10 tuần | Đã phát hiện | Email DE pipeline re-trigger |
| Logility 9,128 dup rows | Replaced with ROW_NUMBER dedupe trong Silver | Done |
| ITMRVA 2 dup rows at STID='042' | KHÔNG ảnh hưởng vì silver filter STID='000' | Done (no fix needed) |
| ITBEXT MFPUS pull cho UnavailableFlag | Confirmed working | Done |

---

## 10. Recommendation cho phase tiếp theo

| Action | Owner | Priority |
|---|---|---|
| Fix 5 HIGH bugs (H1-H5) | Code maintainer | P0 |
| Confirm OpenOrderDetail Flag=2 với Robert | Robert | P0 |
| Confirm OSTAT firm codes với Robert | Robert | P1 |
| Switch Forecast source sang DemandForecast (current) | Code maintainer | P1 |
| Probe ATPSUM APWK column structure (P2 verify) | Aric | P1 |
| Email DE re: stale pipelines + missing tables | Aric | P0 |
| Execute test deploy trong dev WH (chỉ sau khi P0 fix) + cleanup | TBD | P2 |
| Power BI semantic model load + DAX validation | TBD | P2 |

---

## 11. Files generated trong session này

| File | Mục đích |
|---|---|
| `_artifacts/bronze_source_truth.json` + `.md` | Real columns + row counts cho 25 tables |
| `_artifacts/source_corrections.md` | Mismatch vs plan assumptions |
| `_scripts/probe_all_sources.py` | Reusable probe script |
| `_scripts/sql/01-10.sql` | 10 SQL files (silver + gold ETL) |
| `_scripts/sql/99_cleanup_silver.sql` | Cleanup silver sau test |
| `_scripts/sql/99_cleanup_gold.sql` | Cleanup gold sau test |
| `FinalDecision/InventoryHealth_ETL_Plan_v3.md` | Plan overview |
| `FinalDecision/InventoryHealth_FULL_BUNDLE.md` | Bundle 14 file gộp |
| `FinalDecision/semantic_model/*.tmdl + *.dax` | Power BI semantic + 30 measures |
| `FinalDecision/Source_Confirmation_Status.md` | KPI mapping doc |
| **`FinalDecision/Person_AB_QC_Report.md`** | **This document** |

---

## 12. Bottom line

```
┌─────────────────────────────────────────────────────────────┐
│  COMBINED PERSON A + B QC RESULT                            │
├─────────────────────────────────────────────────────────────┤
│  Bugs found      : 18 (5 HIGH, 6 MEDIUM, 7 LOW)             │
│  KPI blocked     : 5 of 30 (Allocated, COGS, Turns,         │
│                              Rev@Risk, ATP InStock)         │
│  KPI buildable   : 10 clean + 14 with caveat                │
│  External waits  : 4 DE dataflows + 4 business rules        │
│                                                              │
│  Production ready: ❌ NOT YET                                │
│  Next milestone  : Fix 5 HIGH bugs + DE responses           │
│  Estimated      : ~3-5 ngày để code-ready Phase 1           │
└─────────────────────────────────────────────────────────────┘
```
