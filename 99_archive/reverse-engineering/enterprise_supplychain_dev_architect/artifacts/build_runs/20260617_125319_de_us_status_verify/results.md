# DE US status verification — 20260617_125319_de_us_status_verify

- Server: `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com`
- Database: `SupplyChain_Processing_Warehouse`
- Lakehouse: `Enterprise_Lakehouse`
- Today: `2026-06-17`

## SupplyChain_Enh_1.DemandForecastSnapshotDaily
- Claimed: ✅ Hoàn thành
- Issue: Snapshot chậm 85 ngày (MAX Snapshot = 2026-02-24)
- Resolved: ['SupplyChain_Enh_1.DemandForecastSnapshotDaily']
- Exists: False
- Errors: ('42S02', "[42S02] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Invalid object name 'Enterprise_Lakehouse.SupplyChain_Enh_1.DemandForecastSnapshotDaily'. (208) (SQLExecDirectW)")

## SupplyChain_DW.DimAFIWarehouses
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (194 ngày stale)
- Resolved: ['SupplyChain_DW.DimAFIWarehouses']
- Exists: True

## Customers.AccountMaster
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (169 ngày stale)
- Resolved: ['Customers.AccountMaster']
- Exists: True
- Freshness: `cmaTerritoryChangeDate` max=2026-06-15 00:00:00 (days_since=2)

## Customers.ShippingLocations
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (169 ngày stale)
- Resolved: ['Customers.ShippingLocations']
- Exists: True
- Freshness: `cslTerritoryEffectivityDate` max=2026-06-16 00:00:00 (days_since=1)

## Wholesale_ProductSourcing_AFI.CustomerGrouping
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (161 ngày stale)
- Resolved: ['Wholesale_ProductSourcing_AFI.CustomerGrouping']
- Exists: True

## Wholesale_Codis_AFI.COMAST
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Codis_AFI.COMAST']
- Exists: True

## Wholesale_Codis_AFI.Codatan
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Codis_AFI.Codatan']
- Exists: True
- Freshness: `RQIDT` max=20391225 (days_since=-4939)

## Wholesale_Codis_AFI.EXTORD
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Codis_AFI.EXTORD']
- Exists: True
- Freshness: `HDATE` max=20260617 (days_since=0)

## Wholesale_Codis_AFI.EXTORIT
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Codis_AFI.EXTORIT']
- Exists: True
- Freshness: `IPRMDT` max=20391225 (days_since=-4939)

## Wholesale_Codis_AFI.AAORDTYP
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Codis_AFI.AAORDTYP']
- Exists: True
- Freshness: `OTDATE` max=20210317 (days_since=1918)

## Manufacturing_ProductionPlanning_AFI.MOMAST
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (169 ngày stale)
- Resolved: ['Manufacturing_ProductionPlanning_AFI.MOMAST']
- Exists: True
- Freshness: `ODUDT` max=1261231 (days_since=-197)

## Manufacturing_Inventory_AFI.TFRDTL
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (161 ngày stale)
- Resolved: ['Manufacturing_Inventory_AFI.TFRDTL']
- Exists: True
- Freshness: `DETADT` max=0 (days_since=None)

## Manufacturing_Inventory_AFI.TFRHDR
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (161 ngày stale)
- Resolved: ['Manufacturing_Inventory_AFI.TFRHDR']
- Exists: True
- Freshness: `HARRDT` max=20280619 (days_since=-733)

## Wholesale_Codis_AFI.AshleyWarehouseMaster
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Codis_AFI.AshleyWarehouseMaster']
- Exists: True

## Wholesale_Purchasing_AFI.ATPSUM
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (98 ngày stale)
- Resolved: ['Wholesale_Purchasing_AFI.ATPSUM']
- Exists: True

## ItemMaster_AFI.ITBEXT
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (71 ngày stale)
- Resolved: ['ItemMaster_AFI.ITBEXT']
- Exists: True
- Freshness: `MFSDT` max=20391101 (days_since=-4885)

## ItemMaster_AFI.ITMRVA
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (66 ngày stale)
- Resolved: ['ItemMaster_AFI.ITMRVA']
- Exists: True
- Freshness: `BZBLDT` max=1060826 (days_since=7235)

## ItemMaster_AFI.ITEMBL
- Claimed: ✅ Hoàn thành
- Issue: Data freshness (58 ngày stale)
- Resolved: ['ItemMaster_AFI.ITEMBL']
- Exists: True
- Freshness: `LACDT` max=1800305 (days_since=-19620)

## SupplyChain_Enh.CurFcstSnapshotWeekly
- Claimed: ✅ Hoàn thành
- Issue: Cần pull/load table
- Resolved: ['SupplyChain_Enh.CurFcstSnapshotWeekly']
- Exists: True
- Freshness: `SnapshotDate` max=2026-06-15 05:37:35 (days_since=2)

## SalesHistory_AFI.InvoiceHeader
- Claimed: 🟡 Cần Analytics kiểm tra lại
- Issue: Thiếu dữ liệu lịch sử (~4M vs ~25M records)
- Resolved: ['SalesHistory_AFI.InvoiceHeader']
- Exists: True
- Freshness: `InvoiceDate` max=2026-06-16 (days_since=1)

## SupplyChain_Enh.PurchaseOrderSnapshot
- Claimed: 🟡 Cần Analytics kiểm tra lại
- Issue: Chưa được promote lên Enterprise Lakehouse
- Resolved: ['SupplyChain_Enh.PurchaseOrderSnapshot']
- Exists: True
- Freshness: `posSnapshot` max=2026-06-16 15:00:53 (days_since=1)

## SupplyChain_Enh.ATPWeekEnding
- Claimed: 🟡 Cần Analytics kiểm tra lại
- Issue: Duplicate records + AFIFinanceDivision null
- Resolved: ['SupplyChain_Enh.ATPWeekEnding']
- Exists: True
- Freshness: `WeekEnding` max=2026-07-25 (days_since=-38)
- Duplicates: {'dup_key_cols': ['WeekEnding', 'ItemSKU', 'ItemGrouping', 'Warehouse', 'AFIFinanceDivision'], 'dup_groups': None, 'dup_extra_rows': None}

## Manufacturing_Inventory_AFI.IMHIST
- Claimed: 🟠 Cần xác nhận nghiệp vụ
- Issue: Future-dated records
- Resolved: ['Manufacturing_Inventory_AFI.IMHIST']
- Exists: True
- Freshness: `UPDDT` max=1260224 (days_since=113)
- Future-dated: {'future_date_col': 'UPDDT', 'future_any': None, 'future_error': "('22018', '[22018] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Operand type clash: date is incompatible with decimal (206) (SQLExecDirectW)')"}

## Wholesale_ProductSourcing_AFI.PoDetail vs Wholesale_ProductSourcing_AFI.PoMaster
- Claimed: 🟠 Cần xác nhận nghiệp vụ
- Issue: 481 orphan detail rows, 20 warehouse mismatch
- Resolved left: ['Wholesale_ProductSourcing_AFI.PoDetail']
- Resolved right: ['Wholesale_ProductSourcing_AFI.PoMaster']

## Manufacturing_Inventory_AFI.TFRDTL vs Manufacturing_Inventory_AFI.TFRHDR
- Claimed: 🟠 Cần xác nhận nghiệp vụ
- Issue: 188 orphan detail records
- Resolved left: ['Manufacturing_Inventory_AFI.TFRDTL']
- Resolved right: ['Manufacturing_Inventory_AFI.TFRHDR']
- Error: No join keys found

## Inventory_Enh_History.ItemBalance
- Claimed: 🔴 DE chưa hoàn thành
- Issue: Chưa được promote lên EL, đang dùng workaround Dataflow Gen2 (~49M rows)
- Resolved: ['Inventory_Enh_History.ItemBalance']
- Exists: False
- Errors: ('42S02', "[42S02] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Invalid object name 'Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance'. (208) (SQLExecDirectW)")

## DemandForecastSnapshotWeekly
- Claimed: 🔴 DE chưa hoàn thành
- Issue: Snapshot refresh dừng từ 2024-03-25
- Resolved: ['SupplyChain_Enh.DemandForecastSnapshotWeekly']
- Exists: True
- Freshness: `dfcSnapshot` max=2024-03-25 00:00:00 (days_since=814)

## MasterData_DW.DimDate
- Claimed: 🔴 DE chưa hoàn thành
- Issue: Data stale (204 ngày)
- Resolved: ['MasterData_DW.DimDate']
- Exists: True
- Freshness: `MapicsDate` max=1281231 (days_since=-928)

## MasterData_DW.DimItemMaster
- Claimed: 🔴 DE chưa hoàn thành
- Issue: Data stale (204 ngày)
- Resolved: ['MasterData_DW.DimItemMaster']
- Exists: True
- Freshness: `ManufacturingStatusChangeDate` max=2026-06-15 (days_since=2)

## DemandInventorySnapshotWeekly
- Claimed: 🔴 DE chưa hoàn thành
- Issue: Snapshot refresh dừng từ 2026-03-02
- Resolved: ['SupplyChain_Enh.DemandInventorySnapshotWeekly']
- Exists: True
- Freshness: `dinSnapshot` max=2026-03-02 05:30:02 (days_since=107)

## DemandFulfillmentCommonContainer_Logility
- Claimed: 🔴 DE chưa hoàn thành
- Issue: 9,128 duplicate groups; chưa có canonical dedupe rule
- Resolved: ['SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility']
- Exists: True
- Freshness: `WeekEnding` max=2026-05-16 (days_since=32)

## SupplyChain_Enh_1.SupplyPlanDetailSnapshotDaily
- Claimed: 🔴 DE chưa hoàn thành
- Issue: Missing snapshots 2025-12-20..2026-02-14 (IsActiveItemWhIn14DNext/7DNext)
- Resolved: ['SupplyChain_Enh_1.SupplyPlanDetailSnapshotDaily']
- Exists: False
- Errors: ('42S02', "[42S02] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Invalid object name 'Enterprise_Lakehouse.SupplyChain_Enh_1.SupplyPlanDetailSnapshotDaily'. (208) (SQLExecDirectW)")
