# Matrix v3 — KPI × EDW Source × Lakehouse Mapping (Final)

**Source:** `Inventory Health Project_Resources.xlsx` → sheet **`BRD_6_3_Source_Matrix`** (file mới, đọc lại 2026-05-06).
**Target lakehouse:** `Enterprise_Lakehouse` (Fabric workspace `Enterprise SupplyChain-Dev`, env=dev, GUID `584e7d2c-46ca-49dc-bb6c-68df6ef4f424`).
**Inventory scanned:** 400 tables × 12,584 columns × 32 schemas. Mọi source được verify column-existence + row-count + grain-uniqueness + key DQ trên SQL endpoint.

**Confidence legend:**
🟢 **OK** = source tồn tại đầy đủ, key/grain clean, KPI tính được
🟡 **PARTIAL** = tính được nhưng có caveat (null %, dedupe, missing piece)
🔴 **BLOCKED** = source rỗng / không tồn tại / out-of-scope

---

## 📋 Bảng đầy đủ — KPI × Source EDW × Lakehouse

| Order | Section | KPI / Field (BRD 6.3) | BRD Definition | Proposed Source (EDW) | Expected Grain | Snapshot | Question / Note | PIC | **Lakehouse table(s) cần dùng (verified)** | **Cần join / multi-table?** | **Verdict** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **1** | Base Supply / Demand | **On Hand Quantity** | Total inventory On Hand at Warehouse, expressed in units, $ COGS, $ Revenue, Volume (Cu Ft), WoS; segment by location | Primary: `ItemMaster_AFI.ITEMBL` (**[MOHTQ]**)<br>Supporting: `ITEMASA.UCDEF` cost; `DimItemMaster` revenue price + cube | ItemSKU-Location | Current daily; historical weekending if retained |  | Kiệt | **`ItemMaster_AFI.ITEMBL`** (3.40M; grain unique [ITNBR,HOUSE]; **MOHTQ** valid 178K pos rows, sum=153.4M; **PHYOH=0 toàn bảng → DEAD col**)<br>+ `ItemMaster_AFI.ITMRVA` (2.89M, UCDEF cost, STID=000)<br>+ `MasterData_DW.DimItemMaster` (381K, FOBArcPrice + Cubes + AFIItemStatus) | 3 bảng: ITEMBL ⨝ ITMRVA (ITNBR) ⨝ DimItemMaster (ItemSKU=ITNBR) | 🟢 OK |
| — | Base Supply / Demand | **Transfer In Intransit** | Total inventory On Hand at related Intransit Warehouse, expressed in units, $ COGS, $ Revenue, Volume (Cu Ft), WoS | *(no proposal in matrix)* | ItemSKU-Location | Current daily; historical weekending | Transfer InTransit Logic |  | **`Wholesale_Codis_AFI.AshleyWarehouseMaster.wmaIntransitWarehouse`** (54 rows; mapping `1→A`, `15→L`, `12→M`, `28→PE`...)<br>+ `ItemMaster_AFI.ITEMBL` filter `HOUSE IN (intransit pair codes)` (32 single-letter HOUSE codes có data MOHTQ ≥ 0)<br>+ Supplemental: `Manufacturing_Inventory_AFI.TFRHDR` (15.8K) + `TFRDTL` (472K) cho transfer events<br>+ Snapshot: `Wholesale_DemandPlanning_AFI.SupplyPlanDetail.spdInTransitTransferIn` (8.4K positive rows) | 3 bảng: AWM (lookup pair) → ITEMBL (filter HOUSE=pair) | 🟢 OK 🆕 |
| **2** | Base Supply / Demand | **PO In Transit Quantity** | Total inventory In Transit; units/$/Volume/WoS/Containers | Primary: `Wholesale_ProductSourcing_AFI.PoDetail` (`podIntransitQty`) + **PoMaster** | ItemSKU-Location | Current daily | PO detail Status = 20 | Kiệt | **`Wholesale_ProductSourcing_AFI.PoDetail`** ✅ schema OK (53 cols; có `podIntransitQty, podstatuscode, poditemnum, podwarehouse`)<br>🚨 **0 rows in dev**<br>**`PoMaster` ❌ NOT FOUND** (đã scan 400 tables) — PoDetail flatten vendor/due/buyer<br>**`Wholesale_ProductSourcing_AFI.Container`** (283K rows) cho cargo/ETA tracking | PoDetail standalone (không cần PoMaster) + Container cho cubes | 🔴 **BLOCKED** (PoDetail empty) |
| **3** | Base Supply / Demand | **PO On Order Quantity** | Total inventory on Firm PO, not yet shipped | Primary: `Wholesale_ProductSourcing_AFI.PoDetail` + PoMaster | ItemSKU-Location | Current daily | PO detail Status = 10; Firm PO? | Kiệt | Same as #2 — `PoDetail` rỗng | Same | 🔴 **BLOCKED** |
| — | Base Supply / Demand | **MO On Order Quantity** 🆕 | Total inventory on firm manufacturing order | `Manufacturing_ProductionPlanning_AFI.MOMAST` | ItemSKU-Location | Current daily |  |  | **`Manufacturing_ProductionPlanning_AFI.MOMAST`** ✅ verified — 277,439 rows; key cols: **`FITEM`** (item), **`FITWH`** (warehouse), `ORQTY` (order qty), `QTYRC` (received qty), `QTDEV` (deviated), `OSTAT` (order status), `ODUDT` (due date), `IPMO/TLMO` (in-progress / time-line MO)<br>Sibling history: `MOHMST` (same schema)<br>Daily detail: `Manufacturing_ProductionPlanning_AFI.DailyProdMoDetail` | 1 bảng MOMAST (KPI = SUM(ORQTY-QTYRC) WHERE OSTAT IN ('firm states') GROUP BY FITEM, FITWH) — cần Robert chốt giá trị OSTAT nào là "firm" | 🟢 OK 🆕 |
| **6** | Base Supply / Demand | **Allocated Demand Quantity** | Qty of on-hand reserved against confirmed customer orders within ATP window not yet shipped | *(no proposal — unresolved)* | ItemSKU-Location | Current daily; historical only if ATP/allocation snapshots exist | Authoritative source unresolved | Kiệt | **`CustomerOrders_AFI.OpenOrderDetail`** ✅ (918,213 rows; có **`ItemAllocationFlag`** + `QuantityShipped` + `QuantityBackOrdered` + `ItemProcessingStatus` + `Warehouse`)<br>Logic: `WHERE ItemAllocationFlag=1 AND QuantityShipped=0` (allocated nhưng chưa ship)<br>Header: `CustomerOrders_AFI.OpenOrderHeader` (224,342 rows)<br>Alt ATP candidate: `Wholesale_Purchasing_AFI.ATPSUM` (296K) | 2 bảng: OpenOrderDetail ⨝ OpenOrderHeader (OrderNumber) | 🟡 **PARTIAL** — workshop để chốt giữa OpenOrderDetail vs ATPSUM |
| **7** | Base Supply / Demand | **Forecast Demand Quantity** | Projected unit demand at SKU-Location level cho forward-looking horizon based on approved forecast | Primary: `[SupplyChain_Enh].[DemandForecastSnapshot]` (cutoff 4/08/2025) + `Wholesale_DemandPlanning_AFI.SupplyForecast` (current)<br>Depend Forecast LEFT JOIN `[SupplyChain_Enh].[DemandInventorySnapshot]` | ItemSKU-Location | Approved current forecast snapshot; historical snapshots if needed | Final rule: weekly forecast tại Saturday, mỗi snapshot 13 tuần forward | Kiệt | **History (rename `_Enh`→`_Enh_1`)**:<br>• `SupplyChain_Enh_1.DemandForecastSnapshotWeekly` (306M rows ✅ — match BRD weekly grain) → key: `dfcItem, dfcWarehouse, dfcSnapshot, dfcResultantForecast`<br>• Hoặc `*Daily` (1.3B rows; freshness max 2026-02-24 ⚠ stale 10 tuần)<br>**Current**: `Wholesale_DemandPlanning_AFI.SupplyForecast` (871K, FCST_RSLT_QTY+FCST_1_ID+FCST_2_ID, freshness 2026-05-05)<br>**Dependent**: `SupplyChain_Enh_1.DemandInventorySnapshotWeekly` (557M)<br>⚠ True grain bao gồm `DfcCustomerGroups + dfcFCSTTypeCode + dfcMgmtCode` — multi-channel split (MFRM/RHCUST/NFM/ECOMM); SUM qua channels | 3 bảng: Snapshot Weekly ⨝ DemandInventory (item+wh+month) ⨝ SupplyForecast (current overlay) | 🟡 **PARTIAL** (channel SUM logic + freshness gap) |
| **8** | Base Supply / Demand | **Average Weekly Demand (AWD)** | Avg 13-week forecasted demand at SKU-Location. Fallback 13w historical if forecast=0 | Derived from #7. Fallback: `[Wholesale_SalesHistory_AFI].[InvoiceDetail]` for 13-week historical shipped-demand average | ItemSKU-Location | Current daily (next 13w); fallback prior 13w actuals |  | Kiệt | Forecast: see #7. Historical fallback: **`SalesHistory_AFI.InvoiceDetail`** (127.7M rows; ItemSKU + Warehouse + QuantityShipped + InvoiceDate; 100% join coverage to DimItemMaster). ⚠ matrix viết `Wholesale_SalesHistory_AFI` nhưng namespace đó chỉ chứa audit/serial-number tables, fact thật ở `SalesHistory_AFI` | 1+ bảng (Forecast tables × CASE WHEN forecast=0 fall back to InvoiceDetail) | 🟢 OK |
| **9** | Financial | **Inventory Value (at Cost)** | $ value of on-hand × standard cost | Derived from `ItemMaster_AFI.ITEMBL` × `MasterData_ItemMaster_AFI.ITEMASA.UCDEF` | ItemSKU-Location | Current daily; historical weekending |  | Giang | **`ITEMBL.MOHTQ`** (NOT PHYOH) × **`ItemMaster_AFI.ITMRVA.UCDEF`** (filter STID='000', ITRV='current')<br>Join `ITNBR ↔ ITNBR` 100% coverage ✅ | 2 bảng: ITEMBL ⨝ ITMRVA (ITNBR, optional STID/ITRV filter) | 🟢 OK |
| **10** | Financial | **Standard Cost** | Per-unit cost cho inventory valuation và financial reporting | Primary: `MasterData_ItemMaster_AFI.ITEMASA.UCDEF` | ItemSKU | Current attribute joined to SKU-Location facts | Need confirm STID=000 in all cost-based KPIs | Giang | **`ItemMaster_AFI.ITMRVA`** (rename: `MasterData_ItemMaster_AFI.ITEMASA → ItemMaster_AFI.ITMRVA`)<br>2.89M rows; grain unique trên (STID, ITNBR, ITRV); 0% null UCDEF | 1 bảng (filter STID=000) | 🟢 OK |
| **11** | Financial | **Standard Selling Price** | FOBARC; estimate revenue exposure & forecast revenue | Primary: `MasterData_DW.DimItemMaster.FOBArcPrice` | ItemSKU | Current attribute joined to SKU-Location facts |  | Giang | **`MasterData_DW.DimItemMaster.FOBArcPrice`** ✅ (381K rows, **6.1% null** — 23,419/381,663 SKU thiếu giá ⚠) | 1 bảng | 🟡 **PARTIAL** (FOB null cho ~6% SKU; cần fallback) |
| **12** | Financial | **COGS** | Cost của units shipped trong period (UCDEF tại STID=000) | Derived: `SalesHistory_AFI.InvoiceDetail` shipped × `MasterData_ItemMaster_AFI.ITEMASA.UCDEF` | Shipment grain → SKU-Location-period | Apply latest standard cost cho toàn period |  | Giang | **`SalesHistory_AFI.InvoiceDetail`** × **`ItemMaster_AFI.ITMRVA.UCDEF` (STID=000)** ✅<br>InvoiceDetail.ItemSKU 100% coverage to DimItemMaster | 2 bảng: InvoiceDetail (QuantityShipped × UCDEF) ⨝ ITMRVA (ITNBR=ItemSKU, STID='000') | 🟢 OK |
| **13** | Physical | **Used Storage Cube** | Cubic volume of on-hand inventory @ warehouse | Derived: `ITEMBL` on-hand × `MasterData_DW.DimItemMaster.Cubes` | ItemSKU-Location | Current daily |  | Giang | **`ITEMBL.MOHTQ`** × **`DimItemMaster.Cubes`** (1 null/381,663 — virtually full coverage ✅) | 2 bảng: ITEMBL ⨝ DimItemMaster (ItemSKU=ITNBR) | 🟢 OK |
| **14** | Physical | **Total Available Warehouse Cube** | Total usable cubic capacity (rack + bulk) | No confirmed source. Future: `SS vs Capacity Projections 20260312.xlsx` cols B,C,D,E,G | Warehouse-Date |  |  | Giang | ❌ **NOT in lakehouse**. File-based source from WH team. BRD §11.4 explicitly out-of-scope phase 1 | n/a | 🔴 **BLOCKED** |
| **15** | Physical | **Container Count (in-transit)** | # shipping containers cho inventory in-transit | No confirmed source. Heuristic: total qty PO × cubes / 2400 | Likely Warehouse-Date or shipment/container level → roll-up | Current daily |  | Giang | **`Wholesale_ProductSourcing_AFI.Container`** ✅ verified (283,585 rows; cols: `concontainer, conID, conmothervessel, conmothervoyage, conETA, conPickUpDate, conviacode, conPallets, conTruckLoad, conReceiptToStock, conCargoReceived` etc.) — đây mới là source thật, không cần heuristic<br>Filter: `WHERE conReceiptToStock IS NULL OR conCargoReceived IS NULL` (chưa nhận về kho) | 2 bảng: Container ⨝ PoDetail (?) qua container/PO link — cần verify FK; nếu PoDetail rỗng thì Container alone vẫn cho count | 🟡 **PARTIAL** (Container ✅ nhưng PoDetail rỗng → khó breakdown theo SKU; warehouse-level count vẫn chạy được) |
| **16** | Safety Stock | **Safety Stock Target** |  | `[SupplyChain_Enh].[DemandInventorySnapshot]` |  |  | Average SS over 13 weeks | Kiệt | **History**: `SupplyChain_Enh_1.DemandInventorySnapshotWeekly` (557M, **dinSafetyStock** + dinIOSafetyStock + dinIOMin/MaxSafetyStock)<br>**Current**: `Wholesale_DemandPlanning_AFI.DemandInventory` (3.66M, grain unique ✅)<br>⚠ **Daily snapshot có 21% true duplicate** (dinSecondaryVendor anomaly) → dedupe Silver | 1 bảng (chọn weekly hoặc daily) | 🟡 **PARTIAL** (dedupe needed) |
| **17** | Inactive Item | **Inactive Item Logic** | `AFI Item Status IN ('D','R') AND ([OnHand] + [OnOrderQty]) = 0` | Past: `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` (BRD viết sai: `DemandFulfilmentCommonContain_Logility.ItemStatus` — đúng là `DemandFulfillmentCommonContainer_Logility`, double L + Container đầy đủ; ItemStatus có thể là column) + `Wholesale_DemandPlanning_AFI.SupplyPlanDetail` (Onhand + On order)<br>Current+Future: `ItemMaster.ItemStatus` + `ITEMBL` (**MOHTQ**) + `PoDetail + PoMaster` where PO status < 50 |  |  |  | Giang | **Status**: `MasterData_DW.DimItemMaster.AFIItemStatus` (Logility raw chưa load lên Lake → mất past tracking — EDW location: `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`)<br>**OnHand**: `ITEMBL.MOHTQ` ✅<br>**OnOrder PO**: `PoDetail` 🚨 empty (BLOCKER)<br>**OnOrder MO**: `MOMAST` (FITEM, FITWH, ORQTY-QTYRC) ✅<br>**OnOrder Transfer**: `Wholesale_DemandPlanning_AFI.SupplyPlanDetail.spdOnOrderTransferIn` ✅ | 4 bảng: DimItemMaster ⨝ ITEMBL ⨝ MOMAST ⨝ SupplyPlanDetail (item+wh) — chờ PoDetail load mới full | 🟡 **PARTIAL** (PO blocker) |
| **18** | SLOB | **SLOB (Slow Moving / Obsolete)** | `AFI Item Status <> 'N' AND [Last Invoice Date] > -17 [FiscalWeekIndicator]` | Past: `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` (BRD viết tắt: `Logility.ItemStatus`) + `[Wholesale_SalesHistory_AFI].InvoiceDetail`<br>Current+Future: `ItemMaster.ItemStatus` + InvoiceDetail |  |  |  | Giang | **`MasterData_DW.DimItemMaster.AFIItemStatus`** + **`SalesHistory_AFI.InvoiceDetail`** (rename, 127.7M rows). LastInvoiceDate = `MAX(InvoiceDate) GROUP BY ItemSKU, Warehouse` | 2 bảng: DimItemMaster ⨝ InvoiceDetail (ItemSKU) | 🟢 OK |
| **19** | Revenue at Risk | **Revenue at Risk** | Description: revenue exposed do thiếu availability cover expected sales<br>Calc: At Week 4 Ending: `[SINegQty] × [FOBPrice]` | `SINegQty = SupplyPlanDetail.spdShippableInventory` |  |  |  | Giang | **`Wholesale_DemandPlanning_AFI.SupplyPlanDetail`** (3.7M, grain unique trên item+wh+weekEnding ✅) — filter `spdShippableInventory < 0` (NEG)<br>× **`MasterData_DW.DimItemMaster.FOBArcPrice`** (6.1% null ⚠)<br>**History**: `SupplyChain_Enh_1.SupplyPlanDetailSnapshotDaily` 🚨 không có cột snapshot ID; phải dùng `MAX(dtec)` per (item,wh,week) — 85× dup nếu không filter | 2 bảng: SupplyPlanDetail ⨝ DimItemMaster (item) — filter weekEnding = current+4w | 🟡 **PARTIAL** (FOB null + snapshot dedupe) |
| **20** | §6.5 Dim | **Lifecycle Status** |  | `demandfulfillmentcommoncontainer_>itemstatus` (Past)<br>`dimitemmaster>afiitemstatus` (Current+Future) |  |  |  | Kiệt | **`MasterData_DW.DimItemMaster.AFIItemStatus`** (381K, 0% null ✅)<br>+ `MarketingItemStatus, ManufacturingStatus, PreviousStatusCode, StatusCodeChangeDate, NewItemFlag, DiscontinuedFlag, DiscontinuedDate`<br>Logility past status ❌ NOT loaded | 1 bảng | 🟢 OK (current/future) / 🟡 (past) |
| — | §6.5 Dim | **Active Status** |  | Classification Inventory <> "Inactive" |  |  |  | Kiệt | Derived from #17 Inactive logic | n/a (derived) | 🟡 (depends on #17) |
| — | §6.5 Dim | **Vendor** |  | `dimitemmaster.PrimaryVendor` (vendor number) |  |  |  | Kiệt | **`DimItemMaster.PrimaryVendor`** (0% null ✅)<br>Lookup: **`Purchasing_AFI.VendorMaster.VendorNumber`** (169K vendors; ITMRVA.VNDNR↔VendorMaster = 99.9% coverage) | 2 bảng: DimItemMaster ⨝ VendorMaster (PrimaryVendor=VendorNumber) | 🟢 OK |
| — | §6.5 Dim | **Distribution Center (DC/WH)** |  | warehouse master (check SCP core schema) |  |  |  | Kiệt | **`Wholesale_Codis_AFI.AshleyWarehouseMaster`** (54 rows, 29 cols, có `wmaSellableWarehouse + wmaWarehouseType + wmaIntransitWarehouse`)<br>Sibling: `CustomerOrders_AFI.WarehouseMaster` (29 cols, identical data, different naming)<br>Thinner dim: `SupplyChain_DW.DimAFIWarehouses` (8 cols) | 1 bảng (chọn AshleyWarehouseMaster làm authoritative) | 🟢 OK |
| — | §6.5 Dim | **On Hold status** |  |  |  |  | Holding Transfers Logic | Kiệt | ❌ **NOT FOUND** in 400 tables. Matrix marks "unresolved". Có thể nằm trong `ITEMBL.ALCTL`/`ITBEXT.CRHLD,DLHLD,TOHLD` (hold qty cols) — chưa probe data | 1 bảng (cần probe) | 🔴 **BLOCKED** |
| **21** | Warehouse Filter | **FG Item Class Filter** | Item class code starting với "Z", exclude not ending với "K" |  |  |  |  | Giang | **`ITEMBL.ITCLS`** hoặc `DimItemMaster.ItemClassCode`<br>SQL: `WHERE LEFT(ITCLS,1)='Z' AND RIGHT(LTRIM(RTRIM(ITCLS)),1)='K'` | 1 bảng (filter only) | 🟢 OK |
| **22** | Warehouse Filter | **FG Warehouse Filter** | Warehouse Codes = `1, 15, 17, 28, 335, 5, ECR`. Outside list = manufacturing WH, out-of-scope |  |  |  |  | Giang | Filter: `ITEMBL.HOUSE IN ('1','5','15','17','28','335','ECR')` — ⚠ code `'335'` chưa thấy trong 71 ITEMBL houses; cần verify với business<br>Cross-check via `AshleyWarehouseMaster.wmaSellableWarehouse=True` | 2 bảng (ITEMBL + AshleyWarehouseMaster) | 🟢 OK (verify '335') |
| **23** | Turns | **Turns** | # times inventory sold and replaced annually<br>Calc: Annualized COGS / Current Inventory Value (at Cost) | Derived from #12 (COGS) & On Hand $ |  | 52w window last COGS / Onhand inventory value | Giang | Derived from #9 + #12 — both 🟢 OK<br>Cần `MasterData_DW.DimDate` (21,551 rows) cho fiscal-week window logic | 4 bảng: InvoiceDetail × ITMRVA (COGS) / ITEMBL × ITMRVA (InvVal) — DimDate cho window | 🟢 OK |
| — | ATP In-Stock Rate 🆕 | **ATP In-Stock Rate** | % active SKUs với positive ATP (count + $-weighted/Volume-weighted) | Using: `[SupplyChain_Enh].[ATPWeekEnding]` filter ATPWeek='Week1' (Past, Current+Future) |  |  |  |  | **`SupplyChain_Enh.ATPWeekEnding` ❌ NOT FOUND**<br>Closest: **`Wholesale_Purchasing_AFI.ATPSUM`** ✅ (296,142 rows; cols: `APITNB` (item) + `APHOUS` (warehouse) + `APAT01..APAT27` (ATP qty week 1..27) + `APWK01..APWK27` (week-end dates)) → tương đương ATPWeekEnding; lấy `APAT01` cho Week1<br>Sibling: `Wholesale_Purchasing_AFI.ATPSUP` (296K, demand 28 weeks)<br>⚠ `ITBEXT.ATPQT` = **DEAD col** (0 positive, sum=0 — như PHYOH, không loaded) — **không dùng**<br>Active filter: từ #17 Inactive logic | 3 bảng: ATPSUM (filter APAT01>0) ⨝ DimItemMaster (FOBArcPrice cho $-weighted) ⨝ Cubes (volume-weighted) ⨝ Inactive logic | 🟡 **PARTIAL** 🆕 (ATPSUM thay ATPWeekEnding, cần Robert chốt) |
| — | Shippable Inventory In-Stock Rate 🆕 | **Shippable Inv In-Stock Rate** | % active SKUs với positive Shippable Inv (count + $/Volume-weighted) | Using: `Wholesale_DemandPlanning_AFI.SupplyPlanDetail.spdShippableInventory` (Past, Current+Future) |  |  |  |  | **`Wholesale_DemandPlanning_AFI.SupplyPlanDetail.spdShippableInventory`** ✅ (3.7M rows current; grain unique trên item+wh+weekEnding)<br>**History**: `SupplyChain_Enh_1.SupplyPlanDetailSnapshotWeekly` (57M)<br>Active filter: từ #17 Inactive logic | 3 bảng: SupplyPlanDetail ⨝ DimItemMaster ⨝ Inactive logic | 🟢 OK 🆕 |
| — | Safety Stock Multiple 🆕 | **Safety Stock Multiple** | Inv position relative to safety stock target<br>Calc: Inv Position / SS Target | (Derived) |  |  |  |  | Derived from #1 (OnHand) + #16 (SS Target) | 2 bảng (already covered) | 🟡 **PARTIAL** (depends on #16 dedupe) |
| — | Obsolete Ratio 🆕 | **Obsolete Ratio** | % total inv value not moved (no sales/transfers/consumption) ≥ -17 weeks. Subset of TB inventory not selling.<br>Calc: (Inv Value with No Movement ≥ -17w / Total Inv Value) × 100 | (No proposal) |  |  |  |  | **No-movement detection sources**:<br>• **`Manufacturing_Inventory_AFI.IMHIST`** ✅ (11.66M rows — Inventory Movement History; cols: ITNBR, HOUSE, **TCODE** (transaction code), TRQTY, TRNDT, PRQOH/NUQOH (prior/new on-hand), VNDNR) → tracking sales/receipts/transfers/scrap by TCODE<br>• `SalesHistory_AFI.InvoiceDetail` (sales movement)<br>• `Manufacturing_Inventory_AFI.TFRDTL/TFRHDR` (transfer movement)<br>• `ItemMaster_AFI.ITEMBL.MOHTQ` × `ITMRVA.UCDEF` (Total Inv Value denominator)<br>SQL: `WHERE NOT EXISTS (SELECT 1 FROM IMHIST h WHERE h.ITNBR = ib.ITNBR AND h.HOUSE = ib.HOUSE AND h.TRNDT >= today - 17 weeks)` | 4 bảng: ITEMBL ⨝ ITMRVA (numerator base) + IMHIST (movement filter) ⨝ DimDate (week-17 cutoff) | 🟢 OK 🆕 |

---

## 🔢 Tổng kết verdict

| Verdict | Count | KPIs |
|---|---|---|
| 🟢 **OK** | **15** | OnHand, Transfer InTransit, MO On Order, AWD, InvValue, StdCost, COGS, UsedCube, SLOB, Lifecycle, Vendor, DC/WH, FG-Class, FG-WH, Turns, Shippable Rate, Obsolete Ratio |
| 🟡 **PARTIAL** | **8** | Allocated Demand, Forecast (channel SUM), Std Selling Price (6% null), Container Count (PoDetail blocker), Safety Stock (21% dedupe), Inactive (PO blocker), Revenue@Risk (snapshot dedupe), ATP Rate (ATPSUM thay), SS Multiple |
| 🔴 **BLOCKED** | **4** | PO In Transit (#2), PO On Order (#3), WH Capacity (#14), On Hold |

---

## 🆕 4 KPI mới trong matrix v3 — tất cả mappable

| KPI | Source matrix v3 đề xuất | Lakehouse map | Verdict |
|---|---|---|---|
| **ATP In-Stock Rate** | `[SupplyChain_Enh].[ATPWeekEnding]` ❌ | **`Wholesale_Purchasing_AFI.ATPSUM`** (296K, APITNB+APHOUS+APAT01-27) | 🟡 |
| **Shippable Inv In-Stock Rate** | `SupplyPlanDetail.spdShippableInventory` ✅ | `Wholesale_DemandPlanning_AFI.SupplyPlanDetail` + history snapshot | 🟢 |
| **Safety Stock Multiple** | (derived) | Derived from #1 OnHand + #16 SS Target | 🟡 |
| **Obsolete Ratio** | (no proposal) | **`IMHIST` movement-detection** (11.66M rows) + ITEMBL/ITMRVA + DimDate | 🟢 |

---

## ⚠️ 9 issues cần workshop với Robert/Matt/PIC

1. 🚨 **`ITEMBL.PHYOH = 0` toàn bảng dev** → bắt buộc chuyển sang `MOHTQ`. Bug load hay quy ước design?
2. 🚨 **`PoDetail = 0 rows`** trong dev → chặn 4 KPI (#2, #3, #15 part, #17 part). DataOps cần re-load.
3. ⚠ **Forecast snapshot stale 10 tuần** (max 2026-02-24) → restart pipeline `pl_forecast`?
4. ⚠ **DemandInventorySnapshotDaily 21% true duplicate** (Wanek vendor split) → fix Bronze hay dedupe Silver?
5. ⚠ **SupplyPlanDetailSnapshotDaily không có cột snapshot ID** → bổ sung `spdSnapshotDate=CAST(dtec AS DATE)` Silver?
6. ❓ Filter '335' trong FG warehouse list không thấy trong 71 ITEMBL HOUSE codes — typo BRD hay WH mới?
7. ❓ MOMAST `OSTAT` giá trị nào là "firm MO"? (cần Robert chốt)
8. ❓ Allocated Demand: chốt giữa `OpenOrderDetail.ItemAllocationFlag` vs `ATPSUM` — hai approach khác nhau hoàn toàn.
9. ❓ ATP In-Stock Rate: matrix viết `SupplyChain_Enh.ATPWeekEnding` nhưng table không tồn tại; thay bằng `Wholesale_Purchasing_AFI.ATPSUM` (cùng grain item+WH+27 tuần ATP) được không?

---

## 🔧 EDW vs Lakehouse — Authoritative naming (updated 2026-05-12)

User confirmed thực tế trên EDW. Một số tên BRD viết khác EDW:

### A. Schema strip pattern: `MasterData_*` → strip khi mirror lên Lake

| EDW (authoritative) | Lake (mirror) |
|---|---|
| `MasterData_ItemMaster_AFI.ITEMBL` | `ItemMaster_AFI.ITEMBL` |
| `MasterData_ItemMaster_AFI.ITBEXT` | `ItemMaster_AFI.ITBEXT` |
| `MasterData_ItemMaster_AFI.ITEMASA` | `ItemMaster_AFI.ITMRVA` (đổi cả tên table) |

**EDW có 8 variants của ITEMBL** — Lake chỉ kéo flavor chính `MasterData_ItemMaster_AFI`:
- `MasterData_ItemMaster_AFI.*` ← **chính, đã kéo lên Lake**
- `MasterData_ItemMaster_AFI_Wrk.*` (staging/work)
- `MasterData_ItemMaster_AFI_xbk.*_YYYY_MM_DD_*` (backup snapshots)
- `MasterData_ItemMaster_WVF.*`, `MasterData_ItemMaster_WNK.*`, `MasterData_ItemMaster_MIL.*` (other business unit flavors)
- `PowerBI_Distribution.*`, `PowerBI_Wholesale.*` (curated for PBI)
- `Masterdata_xbk.*`

→ Khi DE US fix dead cols PHYOH/CRHLD/DLHLD/TOHLD/ATPQT, **specify rõ source = `MasterData_ItemMaster_AFI`** (không phải Wrk/xbk/PowerBI variants).

### B. Logility table — BRD viết sai

| BRD viết (sai) | EDW thật (correct) |
|---|---|
| `DemandFulfilmentCommonContain_Logility.ItemStatus` | `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` |

Sai 2 chỗ:
- `Fulfilment` → đúng là `Fulfillment` (double L)
- `Contain` → đúng là `Container` (đầy đủ)
- Schema không phải standalone, mà nằm trong `SupplyChain_Enh`
- `.ItemStatus` cuối câu BRD có thể là **column** bên trong table chứ không phải table riêng

**EDW có 4 variants:**
- `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` ← chính
- `PowerBI_SupplyChain.DemandFulfillmentCommonContainer_Logility` (curated PBI)
- `Supply_Chain_Archive.DemandFulfillmentCommonContainer_Logility` (archive)
- `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility_China` (China variant, không cần)

→ Khi ask DE US load past status, **specify `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`** (flavor main).

### C. Confirm naming khác BRD đã handle

| BRD viết | EDW/Lake thật |
|---|---|
| `Wholesale_SalesHistory_AFI.InvoiceDetail` | EDW + Lake: `SalesHistory_AFI.InvoiceDetail` (đã chuẩn) |
| `Manufacturing_Inventory.TFRDTL/TFRHDR/IMHIST` | EDW + Lake: `Manufacturing_Inventory_AFI.*` (`_AFI` suffix) |
| `Purchasing.VendorMaster` | EDW + Lake: `Purchasing_AFI.VendorMaster` |
| `SupplyChain_Enh.ATPWeekEnding` | Không tồn tại EDW + Lake; replace bằng `Wholesale_Purchasing_AFI.ATPSUM` |
| `SupplyChain_Enh.DemandForecastSnapshot` | Lake: `SupplyChain_Enh_1.DemandForecastSnapshotWeekly/Daily` (Lake còn cả `_Enh` lẫn `_Enh_1`) |

---

## 📂 Reproducible artifacts

| File | Purpose |
|---|---|
| `_artifacts/Matrix_v3_Final_Lakehouse_Mapping.md` | **This document** (final v3 mapping) |
| `_artifacts/v3_sources_probe.json` | Raw probes ATPSUM/ATPSUP/Container/IMHIST/MOMAST/OpenOrderDetail |
| `_artifacts/Matrix_v2_with_Lakehouse_Mapping.md` | Matrix v2 mapping (matrix update lần 2) |
| `_artifacts/Matrix_to_Lakehouse_Mapping.md` | Matrix v1 fuzzy-match output |
| `_artifacts/Deep_Check_Report.md` | Schema duplicates + snapshot grain + join integrity |
| `_artifacts/KPI_Feasibility_Report.md` | First-pass feasibility |
| `_artifacts/full_inventory.json` | 400 tables × 12,584 cols inventory |
| `_artifacts/feasibility_results.json`, `dq_focused.json`, `deep_check_results.json`, `deep_check_2.json` | Raw scan/DQ results |
| `_scripts/probe_v3_sources.py` | Re-run v3 source probes |
| `_scripts/sql_lib.py` | Reusable AAD-pyodbc connector |
