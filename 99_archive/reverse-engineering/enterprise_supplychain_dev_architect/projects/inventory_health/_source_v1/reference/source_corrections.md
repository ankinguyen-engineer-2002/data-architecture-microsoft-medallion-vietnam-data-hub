# Source Corrections vs Plan v3 Assumptions

Findings from `probe_all_sources.py` run 2026-05-14. Plan v3 SQL needs these corrections.

## Schema corrections

| Plan v3 assumed | Actual on Lakehouse | Action |
|---|---|---|
| `DimItemMaster.Category` | **Not present** — use `RetailCategoryName` or `RetailCategoryCode` | Rewrite SQL |
| `DimItemMaster.Series` | **Not present** — use `SeriesNumber`, `SeriesName`, or `SeriesDescription` | Rewrite SQL |
| `AshleyWarehouseMaster.wmaWarehouseName` | **Not present** — table has NO warehouse-name column | Use `wmaWarehouse` as both code+name |
| `AshleyWarehouseMaster.wmaRegion` | **Not present** | Skip or default NULL |
| `DemandInventorySnapshotWeekly.dinCustomerGroups/dinFCSTTypeCode/dinMgmtCode` | **Not present** — no channel split in inventory snapshot | **DROP channel SUM** — direct map |
| `DemandForecastSnapshotWeekly.dfcWeekEnding` | **Not present** — `dfcSnapshot` IS the week-ending | Use `dfcSnapshot` for both snapshot & week-end |
| `DemandForecastSnapshotWeekly.DfcCustomerGroups + dfcFCSTTypeCode + dfcMgmtCode` | **All 3 PRESENT** — channel split exists here | Keep SUM across these 3 |
| `SupplyForecast.ItemSKU / WarehouseCode / WeekEndingDate / ForecastQty` | Only `FCST_1_ID`, `FCST_2_ID`, `FCST_YR_PRD`, `FCST_RSLT_QTY`, `PROMO_LIFT_QTY` (7 cols) | **FCST_1_ID = Item, FCST_2_ID = Warehouse** (assumption); `FCST_YR_PRD` = year-period code derived |
| `SupplyPlanDetail` | All 13 cols probed ✅ correct | OK |
| `InvoiceDetail.WarehouseCode` | Use `Warehouse` (col 12) | Rename |
| `InvoiceDetail.InvoiceLine` | Use `ItemSequence` (col 4) | Rename |
| `InvoiceDetail` PK | `(InvoiceNumber, ItemSequence)` — both exist | Compose PK |
| `OpenOrderDetail.RequestedShipDate` | Use `MaterialRequestDate` (col 48) or `PromiseDate` (col 10) — note Aric chốt rule | Pick one |
| `OpenOrderHeader` | Only 15 cols: includes `OrderNumber`, `Warehouse`, `OrderDate`, `RequestDate` | OK |
| `podetail_v2.poditem` | Use `poditemnum` (col 3) | Rename |
| `podetail_v2.podstatuscode` | **Type is `varchar`** not int | Cast |
| `pomaster.pomvendornum/pomordernum/pometa/pometd` | All present ✅ | OK |
| `logility_demandfulfillment` | 53 cols including `OnHandQty`, `ShippableInvQty`, `MosofSupply`, `SafetyStockQty`, `ItemStatus`, `FutureStatus`, `StatusChngDate`, `Series`, `ItemClass`, `Vendor`, `Price` | **Much richer than expected** — can serve more than just Inactive/SLOB |
| `Inventory_Enh_History.ItemBalance` | **Schema doesn't exist** | Phase 1.5 — fall back to `silver.InventorySnapshotWeekly` (built from `DemandInventorySnapshotWeekly`) |

## Row count updates (vs Matrix v3)

| Table | Matrix v3 | Probe today | Delta |
|---|---|---|---|
| VendorMaster | 169K | **86,598** | -49% (Matrix v3 wrong) |
| MOMAST | 277K | **251,596** | -9% |
| TFRDTL | 472K | **675,462** | +43% |
| TFRHDR | 15.8K | **26,135** | +65% |
| OpenOrderHeader | 224K | **219,900** | -2% |
| ATPSUM | 296K | **296,744** | match |
| SupplyForecast | 871K | **921,060** | +6% |
| SupplyPlanDetail | 3.7M | **3,877,267** | +5% |
| DemandInventory | 3.66M | **3,829,284** | +5% |
| Container | 283K | **299,485** | +6% |
| PoDetail (Enterprise) | 0 | **0** | still empty |
| podetail_v2 (SC) | 21.92M | **21,923,551** | match |
| pomaster (SC) | 5.67M | **5,681,305** | match |
| logility (SC) | 38.36M | **38,356,303** | match |

## Verified key tables status (after probe)

| Table | Rows | Cols | Status |
|---|---|---|---|
| DimItemMaster | 382,302 | 173 | ✅ |
| DimDate | 21,551 | 72 | ✅ |
| AshleyWarehouseMaster | 54 | 29 | ✅ no name col |
| VendorMaster | 86,598 | 51 | ✅ (smaller than expected) |
| ITEMBL | 3,411,561 | 124 | ✅ MOHTQ confirmed |
| ITMRVA | 2,897,198 | 122 | ✅ |
| ITBEXT | 3,389,222 | 50 | ✅ MFPUS confirmed col 3 |
| DemandInventorySnapshotWeekly | 557,141,256 | 31 | ✅ no channel split |
| DemandForecastSnapshotWeekly | 306,173,656 | 23 | ✅ 3-way channel split confirmed |
| ATPSUM | 296,744 | 119 | ✅ wide format APAT01-27 / APWK01-27 |
| SupplyForecast | 921,060 | 7 | ⚠️ structure different than expected |
| SupplyPlanDetail | 3,877,267 | 27 | ✅ all spd cols confirmed |
| InvoiceDetail | 128,309,247 | 80 | ✅ but Warehouse not WarehouseCode |
| MOMAST | 251,596 | 71 | ✅ |
| TFRDTL | 675,462 | 19 | ✅ |
| TFRHDR | 26,135 | 20 | ✅ |
| IMHIST | 11,664,291 | 105 | ✅ |
| OpenOrderDetail | 918,213 | 66 | ✅ ItemAllocationFlag confirmed |
| OpenOrderHeader | 219,900 | 15 | ✅ small dim header |
| PoDetail (Enterprise) | **0** | 53 | 🚨 still empty |
| Container | 299,485 | 39 | ✅ |
| podetail_v2 (SC) | 21,923,551 | 53 | ✅ replacement |
| pomaster (SC) | 5,681,305 | 75 | ✅ replacement |
| logility_demandfulfillment (SC) | 38,356,303 | 53 | ✅ replacement (rich) |

## Files

- Full JSON metadata: `_artifacts/bronze_source_truth.json` (1 row per table with all cols + row counts)
- Human-readable MD: `_artifacts/bronze_source_truth.md` (full column lists)
- This corrections doc: `_artifacts/source_corrections.md`
