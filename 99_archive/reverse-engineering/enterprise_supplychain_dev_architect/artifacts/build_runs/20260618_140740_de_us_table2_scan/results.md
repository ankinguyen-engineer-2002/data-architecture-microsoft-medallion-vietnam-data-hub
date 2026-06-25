# Table 2 live scan — Enterprise_Lakehouse (2026-06-18)

- Mode: `deep`
- Server: `7woj2wroypauvkpn72b56t46ju-qp6ntsfwdaou5atebne65u3p4a.datawarehouse.fabric.microsoft.com`
- Database: `SupplyChain_Processing_Warehouse`
- Lakehouse: `Enterprise_Lakehouse`
- Source list: `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260617_125319_de_us_status_verify/status_table_with_aric_check.md`

## Table: `SalesHistory_AFI_Enh.InvoiceHeader`
- Resolved: `['SalesHistory_AFI_Enh.InvoiceHeader']`
- Exists: `True`
- Freshness: col=`InvoiceDate` max=`2026-06-17` days_since=`1`
- Date maxes: `[{'col': 'InvoiceDate', 'max': '2026-06-17'}, {'col': 'RequestDate', 'max': '2028-09-28'}, {'col': 'OrderDate', 'max': '2026-06-16'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['InvoiceNumber'], 'dup_groups': 90035, 'dup_extra_rows': 1203027}`

## Table: `SalesHistory_AFI_Enh.InvoiceDetail`
- Resolved: `['SalesHistory_AFI_Enh.InvoiceDetail']`
- Exists: `True`
- Freshness: col=`InvoiceDate` max=`2026-06-17` days_since=`1`
- Date maxes: `[{'col': 'InvoiceDate', 'max': '2026-06-17'}, {'col': 'OriginalInvoiceDate', 'max': '2026-06-11'}, {'col': 'RequestDate', 'max': '2028-09-28'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['InvoiceNumber', 'ItemSequence', 'LineReleaseNumber', 'OriginalSequenceNumber', 'ItemSKU'], 'dup_groups': 691, 'dup_extra_rows': 691}`

## Table: `SupplyChain_Enh.PurchaseOrderSnapshot`
- Resolved: `['SupplyChain_Enh.PurchaseOrderSnapshot']`
- Exists: `True`
- Freshness: col=`posSnapshot` max=`2026-06-17 15:00:45` days_since=`1`
- Date maxes: `[{'col': 'posSnapshot', 'max': '2026-06-17 15:00:45'}, {'col': 'posDueDt', 'max': '1301030'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['posSnapshot', 'posItNbr', 'posWhse', 'posVndnr', 'posDueDt'], 'dup_groups': 97186056, 'dup_extra_rows': 121041212}`

## Table: `SupplyChain_Enh.ATPWeekEnding`
- Resolved: `['SupplyChain_Enh.ATPWeekEnding']`
- Exists: `True`
- Freshness: col=`WeekEnding` max=`2026-07-25` days_since=`-37`
- Date maxes: `[{'col': 'WeekEnding', 'max': '2026-07-25'}, {'col': 'RunDate', 'max': '2026-06-18'}, {'col': 'InsertedDate', 'max': '2026-06-18 00:10:44'}]`
- ATPWeekEnding WeekEnding max: `{'col': 'WeekEnding', 'max': '2026-07-25'}`
- AFIFinanceDivision NULL exists: `True`
- Duplicates (key-based): `{'dup_key_cols': ['WeekEnding', 'ItemSKU', 'ItemGrouping', 'Warehouse', 'AFIFinanceDivision'], 'dup_groups': 24880117, 'dup_extra_rows': 927105444}`
- Duplicates (strict-grain): `{'dup_key_cols': ['WeekEnding', 'ItemSKU', 'Warehouse', 'SeriesNumber', 'InsertedVersion', 'ATPWeek', 'AFIFinanceDivision', 'AFISalesDivision', 'ItemGrouping'], 'dup_groups': 136657530, 'dup_extra_rows': 813458160}`

## Table: `Manufacturing_Inventory_AFI.IMHIST`
- Resolved: `['Manufacturing_Inventory_AFI.IMHIST']`
- Exists: `True`
- Freshness: col=`UPDDT` max=`1260224` days_since=`114`
- Date maxes: `[{'col': 'UPDDT', 'max': '1260224'}, {'col': 'TRNDT', 'max': '1261110'}, {'col': 'LPHDT', 'max': '20071230'}]`
- Future-dated probe: `{'future_date_col': 'TRNDT', 'future_cutoff': 1260618, 'future_rows': 5, 'future_max_date': '1261110'}`

## Pair: `Wholesale_ProductSourcing_AFI.PoDetail` vs `Wholesale_ProductSourcing_AFI.PoMaster`
- Resolved left: `['Wholesale_ProductSourcing_AFI.PoDetail']`
- Resolved right: `['Wholesale_ProductSourcing_AFI.PoMaster']`
- Exists: left=True right=True
- Orphan detail rows: `0` (join mappings=[('podordernum', 'pomordernum')])

## Pair: `Manufacturing_Inventory_AFI.TFRDTL` vs `Manufacturing_Inventory_AFI.TFRHDR`
- Resolved left: `['Manufacturing_Inventory_AFI.TFRDTL']`
- Resolved right: `['Manufacturing_Inventory_AFI.TFRHDR']`
- Exists: left=True right=True
- Orphan detail rows: `440` (join mappings=[('DTFRNO', 'HTFRNO')])

## Table: `Inventory_Enh_History.ItemBalance`
- Resolved: `['Inventory_Enh_History.ItemBalance']`
- Exists: `False`
- Errors: `('42S02', "[42S02] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Invalid object name 'Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance'. (208) (SQLExecDirectW)")`

## Table: `MasterData_DW.DimItemMaster`
- Resolved: `['MasterData_DW.DimItemMaster']`
- Exists: `True`
- Freshness: col=`ManufacturingStatusChangeDate` max=`2026-06-15` days_since=`3`
- Date maxes: `[{'col': 'ManufacturingStatusChangeDate', 'max': '2026-06-15'}, {'col': 'DiscontinuedDate', 'max': '2026-06-15'}, {'col': 'StatusCodeChangeDate', 'max': '2026-06-15'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['ItemForecastPlannerID', 'ItemSKU', 'ItemKey', 'Item', 'ItemCode'], 'dup_groups': 0, 'dup_extra_rows': 0}`

## Table: `DemandInventorySnapshotWeekly`
- Resolved: `['SupplyChain_Enh.DemandInventorySnapshotWeekly']`
- Exists: `True`
- Freshness: col=`dinSnapshot` max=`2026-03-02 05:30:02` days_since=`108`
- Date maxes: `[{'col': 'dinSnapshot', 'max': '2026-03-02 05:30:02'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['dinSnapshot', 'dinItem', 'dinWarehouse'], 'dup_groups': 15476146, 'dup_extra_rows': 541665110}`

## Table: `DemandFulfillmentCommonContainer_Logility`
- Resolved: `['SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility']`
- Exists: `True`
- Freshness: col=`WeekEnding` max=`2026-05-16` days_since=`33`
- Date maxes: `[{'col': 'WeekEnding', 'max': '2026-05-16'}, {'col': 'StatusChngDate', 'max': '2026-05-08 00:00:00'}, {'col': 'FileDate', 'max': '2026-05-11 00:00:00'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['WeekEnding', 'Item', 'ItemClass', 'ItemStatus', 'KeyItem'], 'dup_groups': 5608169, 'dup_extra_rows': 32126444}`

## Table: `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily`
- Note: normalized schema 'SupplyChain_Enh_1' -> 'SupplyChain_Enh' (rule: ignore *_1 schemas)
- Resolved: `['SupplyChain_Enh.SupplyPlanDetailSnapshotDaily']`
- Exists: `True`
- Freshness: col=`spdWeekEnding` max=`2027-02-27` days_since=`-254`
- Date maxes: `[{'col': 'spdWeekEnding', 'max': '2027-02-27'}]`
- Duplicates (generic grain guess): `{'dup_key_cols': ['spdWeekEnding', 'spdItem', 'spdWarehouse'], 'dup_groups': 8284615, 'dup_extra_rows': 769998120}`
