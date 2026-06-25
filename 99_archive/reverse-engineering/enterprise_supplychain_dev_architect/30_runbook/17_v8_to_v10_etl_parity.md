# 17 — v8 → v10 ETL Parity & Semantic Model Clone Plan

**Date**: 2026-05-05
**Owner**: Aric (DataHub VN)
**Goal**: Achieve data parity between `Supply Chain Control Tower` semantic model (v8 Lakehouse/Spark) and v10 Gold Warehouse, then clone semantic model on top of v10.

## 1. Executive Summary

The `Supply Chain Control Tower` semantic model reads from 8 tables in `dbo.SupplyChain_Warehouse` produced by **v8 Lakehouse + Spark notebook ETL** (~26 active notebooks, 3 generic engines). v10 rebuilt the Gold serving layer in pure T-SQL (Warehouse + 28 views + 18 routines) but the schema was slimmed down during the Bob Standards rebuild (2026-05-04), losing logic that the model's DAX measures still reference.

This document maps v8 ETL ↔ v10 ETL component-by-component, identifies parity gaps, and lays out the port plan to make v10 Gold match the model's expected schema.

**Headline gaps**:
- `DimCalendar`: v10 has **10 cols** vs v8 **74 cols** → missing 64 calendar/fiscal/holiday attributes
- `FactForecastKpi`: v10 has **12 cols** vs v8 **18 cols** → missing 7 derived error metrics
- `DimForecastHorizon`: v10 missing `num_rank` column
- `dq_forecast_accuracy`: v10 doesn't have this table (drop from TMDL clone)

**Tin tốt**: Tất cả gap đều **derived computations từ data có sẵn** — không cần thêm bảng nguồn mới. Port = extend SQL trong views + ALTER TABLE.

## 2. Architecture Comparison

| Aspect | v8 (Cherry/BCherry build) | v10 (Aric rebuild post-Bob) |
|---|---|---|
| Compute | Spark SQL via PySpark notebooks | T-SQL views + stored procedures |
| Storage | `SupplyChain_Lakehouse` Delta tables | `SupplyChain_Processing_Warehouse` (Silver) + `SupplyChain_Gold_Warehouse` (Gold) |
| Schema | `dbo` flat | 6 schemas: Meta, Staging_WRK, ReferenceMaster_ENH, SalesHistory_ENH, ForecastHistory_ENH, OpenOrderHistory_ENH (Processing) + ForecastAccuracy_DW (Gold) |
| Naming | snake_case (`dim_calendar`, `code_warehouse`) | PascalCase (`DimCalendar`, `WarehouseCode`) |
| Engine pattern | 3 generic Spark notebooks: `brz_engine`, `slv_engine`, `gld_engine` invoked via `notebookutils.notebook.run` | 1 generic SP: `Meta.usp_GenericLoad` driven by `AssetRegistry` metadata |
| Metadata | `SupplyChain_Lakehouse.dbo.utl_pipeline_metadata` | `Meta.AssetRegistry` + `Meta.RunLog` + `Meta.PipelineRunLog` |
| ETL artifacts | 26 Spark notebooks + 3 engines = 30 | 28 T-SQL views + 18 SP/functions |
| Output target | `dbo.SupplyChain_Warehouse.<table>` (separately synced — mechanism out of scope) | `ForecastAccuracy_DW.<Table>` direct via Gold pipeline registry |

## 3. v8 Notebook ↔ v10 T-SQL View Mapping

### 3.1 Reference / Dimension layer

| v8 Notebook | v10 Silver View | v10 Gold View | Status |
|---|---|---|---|
| `nb_ref_calendar` | `ReferenceMaster_ENH.vw_Calendar` | `ForecastAccuracy_DW.vw_DimCalendar` | ⚠️ **Both shrunk vs v8** |
| `nb_ref_warehouse` | `vw_Warehouse` | `vw_DimWarehouse` (`SELECT *`) | ✅ Match |
| `nb_ref_customer_account` | `vw_CustomerAccount` | (not in TMDL) | ✅ Mapped |
| `nb_ref_customer_account_group` | `vw_CustomerAccountGroup` | (not in TMDL) | ✅ Mapped |
| `nb_ref_customer_grouping` | `vw_CustomerGrouping` | `vw_DimCustomerGrouping` | ⚠️ v10 added `Customer` col (enrichment) |
| `nb_ref_forecast_horizon` | `vw_ForecastHorizon` | `vw_DimForecastHorizon` | ⚠️ Missing `Rank` col |
| `nb_ref_item_master` | `vw_ItemMaster` | (not in TMDL) | ✅ Mapped |
| `nb_ref_order_type` | `vw_OrderType` | (not in TMDL) | ✅ Mapped |
| `nb_ref_product` | (Staging shortcut) | `vw_DimProduct` (`SELECT * FROM Staging_WRK.ProductEdw`) | ⚠️ v10 reads from Staging (not Silver) — verify |
| (none) | `vw_CustomerShippingLocation` | (none) | extra v10 |
| (none) | `vw_ForecastCycle` | (none) | extra v10 (used by ForecastDemandMonthly) |

### 3.2 Silver fact-feeder layer

| v8 Notebook | v10 View | Status |
|---|---|---|
| `nb_slv_actual_demand_monthly` | `SalesHistory_ENH.vw_ActualDemandMonthly` | ✅ Match |
| `nb_slv_actual_demand_weekly` | `vw_ActualDemandWeekly` | ✅ Match |
| `nb_slv_forecast_demand_monthly` | `ForecastHistory_ENH.vw_ForecastDemandMonthly` | ✅ Match (CTE + Lag horizon + filter) |
| `nb_slv_naive_forecast_monthly` | `vw_NaiveForecastMonthly` | ✅ Match (LAG window + month_weeks proportional) |
| `nb_slv_invoice_detail_line_level` | `SalesHistory_ENH.vw_InvoiceDetailLineLevel` | ✅ Match |
| `nb_slv_invoice_weekly` | `vw_InvoiceWeekly` | ✅ Match |
| `nb_slv_open_order_line_level` | `OpenOrderHistory_ENH.vw_OpenOrderLineLevel` | ✅ Match |
| `nb_slv_open_order_monthly` | `vw_OpenOrderMonthly` | ✅ Match |

### 3.3 Bronze (Staging) layer

| v8 Notebook | v10 View / Table | Status |
|---|---|---|
| `nb_brz_Wholesale_Codis_AFI__codatan` | `Staging_WRK.vw_Codatan` | ✅ Match |
| `nb_brz_Wholesale_Codis_AFI__COMAST` | `vw_Comast` | ✅ Match |
| `nb_brz_Wholesale_Codis_AFI__EXTORD` | `vw_Extord` | ✅ Match |
| `nb_brz_Wholesale_Codis_AFI__EXTORIT` | `vw_Extorit` | ✅ Match |
| `nb_brz_SalesHistory_AFI__InvoiceHeader` | (Lakehouse shortcut) | ✅ Same source via Enterprise_Lakehouse |
| `nb_brz_SalesHistory_AFI__InvoiceDetail` | (Lakehouse shortcut) | (Failed pull HTTP 500 — retry later) |
| `nb_brz_SupplyChain_Enh_1__DemandForecastSnapshotDaily` | `Staging_WRK.DemandForecastSnapshotDailyEdw` | ✅ Match |

### 3.4 Gold layer

| v8 Notebook | v10 Gold View | Status |
|---|---|---|
| `nb_gld_flat_forecast_actual` | `ForecastAccuracy_DW.vw_FactForecastActual` | ✅ Match (3 UNION ALL) |
| `nb_gld_forecast_kpi_metric` | `vw_FactForecastKpi` | ⚠️ **Missing 7 derived metric columns** |
| (no notebook) | `vw_DimCalendar` Gold | ⚠️ Missing 64 cols |
| (no notebook) | `vw_DimCustomerGrouping` Gold | ✅ |
| (no notebook) | `vw_DimWarehouse` Gold | ✅ |
| (no notebook) | `vw_DimProduct` Gold | Verify — reads from Staging not Silver |
| (no notebook) | `vw_DimForecastHorizon` Gold | ⚠️ Missing `Rank` col |

## 4. Column-Level Gap Matrix per Target Table

### 4.1 `DimCalendar` (v8: 74 → v10: 10)

**Severity**: 🔴 CRITICAL — biggest gap, affects most DAX measures.

**Source**: v8 reads from `MasterData_DW/DimDate` (Enterprise Lakehouse). v10 Silver `vw_Calendar` reads from `Enterprise_Lakehouse.MasterData_DW.DimDate` — same source.

**Silver state (`ReferenceMaster_ENH.Calendar`)**: ~44 cols (per current `vw_Calendar` DDL) — already significantly larger than Gold.

**Gold state (`ForecastAccuracy_DW.DimCalendar`)**: 10 cols (only `DateSK`, `FSCMonthFirst/Last/Name/YearName`, `FSCQuarterName/YearName`, `FSCYearNum/Name`, `LoadDT`).

**Missing (Gold needs to expose)**:

| Group | v8 columns missing in v10 Gold | Source available? |
|---|---|---|
| Calendar Day | `id_mapics_date`, `dt_date`, `dt_datetime`, `dt_calendar`, `name_calendar_date`, `num_cal_date_indicator`, `num_cal_day_of_week`, `name_cal_day_of_week`, `num_cal_day_of_month`, `num_cal_day_of_year` | ✅ in Silver as `MapicsDate`, `Date`, `Datetime`, `Calendar`, `CalendarDateName`, `CalDayOfWeekNum`, `CalDayOfWeekName`, etc. |
| Calendar Week | `num_cal_week`, `num_cal_week_indicator`, `num_cal_week_year`, `name_cal_week_year`, `dt_cal_week_first`, `dt_cal_week_last`, `num_cal_week_of_month` | ✅ partial in Silver (`CalWeekNum`, `CalWeekYearNum`, `CalWeekFirst`, `CalWeekLast`); week_indicator + week_of_month MISSING from Silver too |
| Calendar Month | `num_cal_month_indicator`, `dt_cal_month_first/last` | ✅ in Silver as `CalMonthFirst/Last` (only Indicator missing) |
| Calendar Quarter | `num_cal_quarter`, `name_cal_quarter`, `num_cal_quarter_indicator`, `num_cal_quarter_year`, `name_cal_quarter_year` | ✅ partial in Silver (`CalQuarterNum`, `CalQuarterName`); quarter_year + indicator MISSING |
| Calendar Semester | `num_cal_semester`, `num_cal_semester_year` | ❌ NOT in Silver — need to add to Silver from `CalendarSemester` source col |
| Calendar Year | `num_cal_year_indicator` | ❌ NOT in Silver |
| Fiscal Day | `dt_fiscal`, `name_fiscal_date`, `num_fsc_date_indicator`, `num_fsc_day_of_week`, `name_fsc_day_of_week`, `num_fsc_day_of_month`, `num_fsc_day_of_year` | ❌ NOT in Silver — need to add from `FiscalDate`, `FiscalDateName`, `FiscalDayOf*` source cols |
| Fiscal Week | `num_fsc_week_indicator`, `num_fsc_week_of_month` | ❌ Partial — Silver has `FSCWeekNum/YearNum/First/Last`; missing indicator + of_month |
| Fiscal Month | `num_fsc_month_indicator`, `num_fsc_month_year`, `name_fsc_month_year` | ✅ Silver has `FSCMonthYearNum`, `FSCMonthYearName`; missing only Indicator |
| Fiscal Quarter | `num_fsc_quarter`, `num_fsc_quarter_indicator`, `dt_fsc_quarter_first/last` | ❌ Partial in Silver (`FSCQuarterNum`, `FSCQuarterName`); missing indicator + dates (computed via window function in v8) |
| Fiscal Semester | `num_fsc_semester`, `num_fsc_semester_year` | ❌ NOT in Silver — add from source |
| Fiscal Year | `num_fsc_year_indicator`, `dt_fsc_year_first`, `dt_fsc_year_last` | ❌ NOT in Silver — add from `FiscalYearFirstDate`, `FiscalYearLastDate` source |
| Holiday | `code_holiday_indicator`, `name_holiday`, `code_working_day`, `code_weekday_weekend` | ✅ Silver has these as `HolidayIndicatorCode`, `HolidayName`, `WorkingDayCode`, `WeekdayWeekendCode` |

**Port action**:
1. **ALTER VIEW `ReferenceMaster_ENH.vw_Calendar`** to add ~30 missing source columns from `Enterprise_Lakehouse.MasterData_DW.DimDate` (CalendarSemester, FiscalDate, FiscalDayOf*, semester, year_first/last, indicators, week_of_month).
2. **ALTER TABLE `ReferenceMaster_ENH.Calendar`** to add the new cols (or DROP + CTAS).
3. **Re-run `usp_GenericLoad`** for Calendar.
4. **ALTER VIEW `ForecastAccuracy_DW.vw_DimCalendar`** to expose all 74 cols (PascalCase mapping).
5. **ALTER TABLE `ForecastAccuracy_DW.DimCalendar`** to add new cols.
6. **Re-run `pl_sc_gold`** for DimCalendar.

**v8→v10 column rename map (PascalCase)**:
| v8 (snake) | v10 (Pascal) |
|---|---|
| `sk_date` | `DateSK` (already exists) |
| `id_mapics_date` | `MapicsDate` |
| `dt_date` | `Date` |
| `dt_calendar` | `Calendar` |
| `name_calendar_date` | `CalendarDateName` |
| `num_cal_day_of_week` | `CalDayOfWeekNum` |
| `dt_fsc_month_first` | `FSCMonthFirst` (already exists) |
| `name_fsc_month_year` | `FSCMonthYearName` (already exists) |
| `code_holiday_indicator` | `HolidayIndicatorCode` |
| `name_holiday` | `HolidayName` |
| `code_working_day` | `WorkingDayCode` |
| `code_weekday_weekend` | `WeekdayWeekendCode` |
| ... (full mapping in CSV `v8_to_v10_column_mapping.csv`) | |

### 4.2 `FactForecastKpi` (v8: 18 → v10: 12)

**Severity**: 🔴 CRITICAL — DAX MAPE/RMSE measures depend on these.

**Logic location**: `ForecastAccuracy_DW.vw_FactForecastKpi` — same 4-CTE structure as v8, just missing 7 SELECT expressions.

**Missing computations** (all derive from existing fc/act/nv CTEs):

| v8 col | T-SQL expression to add to vw_FactForecastKpi | Output type |
|---|---|---|
| `qty_naive_fcst_error` | `CAST(COALESCE(nv.qn,0) - COALESCE(act.qa,0) AS FLOAT) AS QtyNaiveFcstError` | FLOAT |
| `qty_abs_naive_fcst_error` | `CAST(ABS(COALESCE(nv.qn,0) - COALESCE(act.qa,0)) AS FLOAT) AS QtyAbsNaiveFcstError` | FLOAT |
| `qty_squared_fcst_error` | `CAST(POWER(COALESCE(fc.qf,0) - COALESCE(act.qa,0), 2) AS FLOAT) AS QtySquaredFcstError` | FLOAT |
| `qty_squared_naive_fcst_error` | `CAST(POWER(COALESCE(nv.qn,0) - COALESCE(act.qa,0), 2) AS FLOAT) AS QtySquaredNaiveFcstError` | FLOAT |
| `valid_obs_flag` | `CAST(CASE WHEN act.qa IS NOT NULL AND fc.qf IS NOT NULL THEN 1 ELSE 0 END AS INT) AS ValidObsFlag` | INT |
| `valid_actual_nonzero_flag` | `CAST(CASE WHEN act.qa IS NOT NULL AND act.qa<>0 THEN 1 ELSE 0 END AS INT) AS ValidActualNonzeroFlag` | INT |
| `abs_pct_error` | `CAST(CASE WHEN act.qa IS NOT NULL AND act.qa<>0 THEN ABS((COALESCE(fc.qf,0) - act.qa) / act.qa) ELSE NULL END AS FLOAT) AS AbsPctError` | FLOAT |

**Port action**:
1. **ALTER VIEW `ForecastAccuracy_DW.vw_FactForecastKpi`** to add 7 SELECT expressions above.
2. **ALTER TABLE `ForecastAccuracy_DW.FactForecastKpi`** to add 7 cols (or DROP + CTAS).
3. **Re-run `pl_sc_gold`** for FactForecastKpi (will repopulate from extended view).

### 4.3 `DimForecastHorizon` (v8: 2 → v10: 2)

**Severity**: 🟡 MEDIUM — `num_rank` used for sort order in DAX.

**v8 logic** (hardcoded in `nb_ref_forecast_horizon.py`):
```sql
SELECT 'Lag-0' AS code_horizon, 1 AS num_rank UNION ALL
SELECT 'Lag-1', 2 UNION ALL ... SELECT 'Naive forecast', 8
```

**v10 state**: `ReferenceMaster_ENH.ForecastHorizon` has only `HorizonCode`. Gold `vw_DimForecastHorizon` SELECTs `HorizonCode + LoadDT` only.

**Port action**:
1. **ALTER VIEW `ReferenceMaster_ENH.vw_ForecastHorizon`** to add `Rank` literal column.
2. **ALTER TABLE `ReferenceMaster_ENH.ForecastHorizon`** to add `Rank` (or recreate).
3. **ALTER VIEW `ForecastAccuracy_DW.vw_DimForecastHorizon`** to expose `Rank`.
4. **ALTER TABLE `ForecastAccuracy_DW.DimForecastHorizon`** to add `Rank`.
5. Reload data.

### 4.4 `DimCustomerGrouping` (v8: 1 → v10: 3)

**Severity**: 🟢 OK — v10 ENRICHED, not gap. `Customer` col added in v10 is bonus.

**Action**: None for parity. TMDL clone maps only `code_customer_group` → `CustomerGroupCode`.

### 4.5 `DimWarehouse` (v8: 8 → v10: 9)

**Severity**: 🟢 OK — content match.

| v8 | v10 |
|---|---|
| `sk_warehouse` | `AFIWarehousesKey` |
| `code_warehouse` | `WarehouseCode` |
| `code_intransit_warehouse` | `IntransitWarehouse` |
| `code_container_direct` | `ContainerDirectWarehouse` |
| `is_controlled_warehouse` | `ControlledWarehouse` |
| `name_warehouse_location` | `WarehouseLocation` |
| `name_warehouse_order_group` | `WarehouseOrderGroup` |
| `is_finance_inventory_report` | `FinanceInventoryReportFlag` |
| (none) | `LoadDT` |

**Action**: None. TMDL clone maps cols.

### 4.6 `DimProduct` (v8: 89 → v10: 90)

**Severity**: 🟢 OK — content near match (1 extra: `LoadDT`).

**Verify**: v10 `vw_DimProduct` reads from `Staging_WRK.ProductEdw` (Staging, not Silver). Need to confirm staging has all 89 source cols.

**Action**: Run column-level diff (separate CSV). Likely zero gap if source mapping is preserved.

### 4.7 `FactForecastActual` (v8: 9 → v10: 10)

**Severity**: 🟢 OK — content match.

| v8 | v10 |
|---|---|
| `id_item_sku` | `ItemSKU` |
| `code_warehouse` | `WarehouseCode` |
| `code_customer_group` | `CustomerGroupCode` |
| `dt_fsc_month_first` | `FSCMonthFirst` |
| `dt_fsc_month_last` | `FSCMonthLast` |
| `code_horizon` | `HorizonCode` |
| `code_status` | `StatusCode` |
| `name_version` | `VersionName` |
| `qty` | `Qty` |
| (none) | `LoadDT` |

**Action**: None.

### 4.8 `dq_forecast_accuracy` — DROP from TMDL clone

**Severity**: 🟢 Decision: drop.

v10 separates DQ data into Processing WH `Meta` schema. Gold WH doesn't have a DQ table by design (Bob standards: Gold = serving-only).

**Action**: Remove `dq_forecast_accuracy` table + related DAX measures from TMDL clone.

## 5. Spark SQL → T-SQL Function Translation Reference

| Spark SQL (v8) | T-SQL (v10) | Notes |
|---|---|---|
| `<=>` (null-safe equal) | Use `(a = b OR (a IS NULL AND b IS NULL))` or COALESCE wrapper | T-SQL has no null-safe equal operator |
| `MAKE_DATE(y, m, d)` | `DATEFROMPARTS(y, m, d)` | T-SQL native |
| `DATE_FORMAT(d, 'yyyy.MM')` | `FORMAT(d, 'yyyy.MM')` | T-SQL native |
| `ADD_MONTHS(d, n)` | `DATEADD(MONTH, n, d)` | |
| `DATE_TRUNC('year', d)` | `DATETRUNC(YEAR, d)` | T-SQL has DATETRUNC since SQL 2022 / Fabric |
| `CURRENT_DATE()` | `CAST(GETDATE() AS DATE)` | or `CAST(GETUTCDATE() AS DATE)` for UTC |
| `CONCAT('V ', x)` | `CONCAT('V ', x)` | Same |
| `LIMIT 1` | `TOP 1` (place after SELECT) | Different syntax |
| `POWER(x, 2)` | `POWER(x, 2)` | Same |
| `LAG(x) OVER (...)` | `LAG(x) OVER (...)` | Same |
| Backtick column quotes `` `Item-Description` `` | Square bracket `[Item-Description]` | Different quote style |
| `CAST(x AS DOUBLE)` | `CAST(x AS FLOAT)` | T-SQL FLOAT = 8-byte double |
| `CAST(x AS BOOLEAN)` | `CAST(x AS BIT)` | |
| `UPPER(TRIM(x))` | `UPPER(TRIM(x))` | Same |

## 6. Phase 2 — Port Execution Plan (after approval)

### 6.1 Pre-flight checks
- [ ] Backup row counts of all 7 Gold tables (snapshot baseline)
- [ ] Backup current view DDLs (already saved in `artifacts/v8_to_v10_parity/v10_views/`)
- [ ] Verify all `Enterprise_Lakehouse.MasterData_DW.DimDate` source columns are accessible from Silver

### 6.2 Critical gap closure (in order)

**Step 1 — DimCalendar 64-col expansion** (~1h)
- Edit `ReferenceMaster_ENH.vw_Calendar` to add ~30 missing source cols
- Run: `EXEC Meta.usp_GenericLoad @table='Calendar'` to materialize Silver
- Edit `ForecastAccuracy_DW.vw_DimCalendar` to expose all 74 cols
- Run pl_sc_gold for DimCalendar
- Verify: row count = ?, col count = 74 + LoadDT

**Step 2 — FactForecastKpi 7-col expansion** (~30 min)
- Edit `ForecastAccuracy_DW.vw_FactForecastKpi` to add 7 SELECT expressions
- Run pl_sc_gold for FactForecastKpi
- Verify: col count = 18 + LoadDT, row count ≈ 36.4M (unchanged)

**Step 3 — DimForecastHorizon Rank** (~15 min)
- Add `Rank` to Silver view + table
- Add `Rank` to Gold view + table
- Reload from hardcoded values

**Step 4 — Verify DimProduct parity** (~30 min)
- Column-level diff between v8 dim_product and v10 DimProduct
- Fix any mismatches

### 6.3 Deliverables for Phase 2 → Phase 3 handoff

- [ ] All 8 Gold tables row counts logged (compare to v8)
- [ ] All 8 Gold tables col counts match TMDL expected (after PascalCase rename)
- [ ] Sample data checksum: 100 random ItemSKUs match between v8 dbo.* and v10 ForecastAccuracy_DW.*

## 7. Phase 3 — TMDL Clone Plan (after Phase 2 verified)

1. Read TMDL parts from `tool-results/bgfm13c6j.txt` (104KB, 18 parts already captured)
2. Apply column rename: snake_case → PascalCase per mapping CSV
3. Update DAX measures to reference new column names
4. Repoint Direct Lake expression: `'DirectLake - SupplyChain_Warehouse'` → `'DirectLake - SupplyChain_Gold_Warehouse'`
5. Change `schemaName: dbo` → `schemaName: ForecastAccuracy_DW` in all partition specs
6. Generate new `lineageTag` UUIDs for all parts
7. Drop `dq_forecast_accuracy` table from model
8. Deploy via Fabric `updateDefinition` API to new model `sc_forecast_control_tower`
9. Verify Direct Lake framing (no DirectQuery fallback)
10. Test all DAX measures vs original Control Tower model

## 8. Open Questions

1. **DimProduct source**: v10 reads from `Staging_WRK.ProductEdw` (Staging) — verify this is intentional (skip Silver) or oversight.
2. **Bronze Salesfile retry**: `nb_brz_SalesHistory_AFI__InvoiceDetail` failed pull HTTP 500 — retry separately. Logic likely matches v10 `vw_InvoiceDetailLineLevel` upstream Bronze ingest.
3. **dbo.SupplyChain_Warehouse sync**: How v8 Lakehouse Delta tables → v8 Warehouse `dbo` schema. Out of port scope (semantic model already moves off this), but document for archival.

## 9. References

- v8 notebooks extracted: `Enterprise_SupplyChain_Dev_architect/artifacts/v8_to_v10_parity/notebooks_extracted/` (33 .py)
- v8 dbo column inventory: `Enterprise_SupplyChain_Dev_architect/artifacts/v8_to_v10_parity/v8_dbo_columns.csv` (204 rows)
- v10 view DDLs Processing: `Enterprise_SupplyChain_Dev_architect/artifacts/v8_to_v10_parity/v10_views/` (28 SQL)
- v10 view DDLs Gold: `Enterprise_SupplyChain_Dev_architect/artifacts/v8_to_v10_parity/v10_gold_views/` (7 SQL)
- TMDL captured: `~/.claude/projects/.../5569546a-5a1b-49ee-9168-3c92e82dd4e9/tool-results/bgfm13c6j.txt` (104KB, 18 parts)
- ADR-004 maturity: `01_docs/decisions/ADR-004-architecture-maturity-assessment.md`

---

**Status as of 2026-05-05**: Investigation complete. Port plan defined. Awaiting Aric approval to execute Phase 2 (ALTER scripts).
