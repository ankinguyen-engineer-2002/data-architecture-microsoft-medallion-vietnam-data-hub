# Supply Chain Load Pattern Live Validation Results

Date: 2026-07-09

Scope:

- Workspace: Enterprise SupplyChain-Dev
- Warehouses tested:
  - SupplyChain_Processing_Warehouse
  - SupplyChain_Gold_Warehouse
- ETL framework procedure tested:
  - ETL_Framework.DW_Developer.usp_UpdateCuratedTableFromView_DateRange
- Test mode:
  - Controlled direct DateRange execution only.
  - Full refresh pipelines and full wave stored procedures were not executed.
  - Existing business transformation views were not changed.

## Why This Test Was Needed

The production load pattern was changed for the heaviest forecast-related physical tables from full overwrite to DateRange delete and insert. The main risk was not only whether the procedure could run, but whether the physical target still matched the working view after the load.

The validation checked:

- Source view row count versus physical target row count.
- Business quantity sums.
- Missing keys from target.
- Extra keys in target.
- Duplicate target grain.
- Active user requests after the test.
- Query Insights duration, row count, and scan signals.

## Objects Tested

| Target | Source view | Window column | Window |
|---|---|---:|---:|
| SupplyChain_Processing_Warehouse.ForecastHistory_Enh.ForecastDemandMonthly | ForecastHistory_Enh_Wrk.v_ForecastDemandMonthly | Snapshot | 30 days |
| SupplyChain_Processing_Warehouse.InventoryHistory_Enh.ForecastSnapshotWeekly | InventoryHistory_Enh_Wrk.v_ForecastSnapshotWeekly | SnapshotDate | 30 days |
| SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi | ForecastAccuracy_DW_Wrk.v_FactForecastKpi | Snapshot | 30 days |

The DateRange procedure resolved the runtime lower bound to `2026-06-09` during this test.

## Validation Summary

| Object | Load result | Source rows | Target rows | Row diff | Keyset diff | Duplicate grain | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| ForecastDemandMonthly | Succeeded | 6,878,400 | 6,878,400 | 0 | 0 missing / 0 extra | 0 | PASS |
| ForecastSnapshotWeekly | Succeeded | 11,055,852 | 11,055,852 | 0 | 0 missing / 0 extra | 0 | PASS |
| FactForecastKpi | Succeeded | 1,535,020 | 1,535,020 | 0 | 0 missing / 0 extra | 0 | PASS |

## Business Sum Checks

### ForecastDemandMonthly

| Metric | Source | Target | Diff |
|---|---:|---:|---:|
| QtyForecast | 43,771,712.000000 | 43,771,712.000000 | 0.000000 |

Snapshot range:

- Source: 2026-06-15 to 2026-06-15
- Target: 2026-06-15 to 2026-06-15

### ForecastSnapshotWeekly

| Metric | Source | Target | Diff |
|---|---:|---:|---:|
| ForecastQty | 302,830,662.000000 | 302,830,662.000000 | 0.000000 |
| PromoLiftQty | 2,158,432.000000 | 2,158,432.000000 | 0.000000 |

Snapshot range:

- Source: 2026-06-13 to 2026-07-04
- Target: 2026-06-13 to 2026-07-04

### FactForecastKpi

| Metric | Source | Target | Diff |
|---|---:|---:|---:|
| QtyForecast | 43,771,712.000000 | 43,771,712.000000 | 0.000000 |
| QtyActual | 4,416,203.000000 | 4,416,203.000000 | 0.000000 |
| QtyNaiveForecast | 5,269,355.000000 | 5,269,355.000000 | 0.000000 |
| QtyFcstError | 39,355,509.000000 | 39,355,509.000000 | 0.000000 |
| QtyAbsFcstError | 40,799,177.000000 | 40,799,177.000000 | 0.000000 |

Snapshot range:

- Source: 2026-06-15 to 2026-06-15
- Target: 2026-06-15 to 2026-06-15

## Query Insights Evidence

The following records came from `ETL_Framework.queryinsights.exec_requests_history`.

| Object | Operation | Rows affected | Duration ms | Remote scan MB | Status |
|---|---:|---:|---:|---:|---|
| ForecastDemandMonthly | DELETE | 6,878,400 | 2,303 | 1.393 | Succeeded |
| ForecastDemandMonthly | INSERT | 6,878,400 | 35,528 | 38,389.587 | Succeeded |
| ForecastSnapshotWeekly | DELETE | 11,055,852 | 3,286 | 1,012.233 | Succeeded |
| ForecastSnapshotWeekly | INSERT | 11,055,852 | 18,111 | 37,543.484 | Succeeded |
| FactForecastKpi | DELETE | 1,535,020 | 2,082 | 43.166 | Succeeded |
| FactForecastKpi | INSERT | 1,535,020 | 25,324 | 757.356 | Succeeded |

## Final Runtime State

After the controlled live test:

| Database | Active user requests |
|---|---:|
| SupplyChain_Processing_Warehouse | 0 |
| SupplyChain_Gold_Warehouse | 0 |
| ETL_Framework | 0 |

## Decision

The DateRange load pattern is validated for the three changed physical targets. The tested 30-day window preserved the full target history outside the window and made the in-window physical tables match their source working views.

The next safe step is not to run the full pipeline immediately. The next step should be a monitored pipeline run during a controlled window, with Query Insights watched for:

- Any unexpected full overwrite still running on large snapshot tables.
- Any long-running DQ query.
- Any foreground user request left active after the pipeline finishes.
- Row count and keyset mismatch in the daily DQ checks.

## Guardrails Still Active

- Do not change business transformation view logic as part of this load-pattern optimization.
- Do not run heavy DQ inside the Gold forecast refresh procedure.
- Do not run the full refresh pipeline from local testing without a controlled window.
- If source view window returns zero rows, DateRange will delete the matching target window. This is accepted as an operational risk and should be handled by daily DQ plus adhoc recovery if it occurs.
- If source view returns duplicate grain, DateRange will insert those duplicates. Duplicate detection remains a DQ responsibility.

## Staging Light Test

Additional light testing was run for `SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily`.

This was read-only testing. The staging physical table was not reloaded.

### Metadata Finding

Live `TableDictionary` currently shows:

| Object | Date key | Update method | Date range | Primary key |
|---|---|---|---:|---|
| Staging.DemandForecastSnapshotDaily | dfcSnapshot | DateRange | 30 | dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups |
| Staging_Wrk.v_DemandForecastSnapshotDaily | dfcSnapshot | null | null | dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups, dfcFCSTTypeCode, dfcMgmtCode |

This means the staging table is configured for DateRange in metadata, but source and target primary key metadata do not match. That is a blocker for safely calling `DW_Developer.usp_IncrementalTableLoad`, because that procedure builds its update and insert matching logic from source and destination primary key metadata.

### Runtime Procedure Finding

Live `dbo.Usp_Refresh_Shared_Staging` still calls:

```sql
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
    'SupplyChain_Processing_Warehouse', 'Staging', 'DemandForecastSnapshotDaily';
```

That wrapper performs full refresh behavior and does not use the `DateRange` metadata above.

### Exact Snapshot Light Test

For `dfcSnapshot = 2026-06-15`, source view and physical staging target matched.

| Check | Source view | Physical target | Status |
|---|---:|---:|---|
| Row count | 12,381,120 | 12,381,120 | PASS |
| Resultant forecast sum | 75,040,438.000000 | 75,040,438.000000 | PASS |
| Promotional lift sum | 528,558.000000 | 528,558.000000 | PASS |
| Target 7-grain duplicate groups | n/a | 0 | PASS |
| Source 5-grain duplicate groups | 0 | n/a | PASS |
| Source 7-grain duplicate groups | 0 | n/a | PASS |

Query Insights signals:

| Query | Duration ms | Remote scan MB |
|---|---:|---:|
| Target exact snapshot summary | 10,098 | 18,533.742 |
| Source exact snapshot summary | 6,750 | 889.540 |
| Source 5-grain duplicate check | 4,957 | 0.000 remote / 889.540 memory |
| Source 7-grain duplicate check | 3,327 | 0.000 remote / 889.540 memory |

### 30-Day Window Light Test

For the same window the DateRange metadata would use during this test (`2026-06-09` through `2026-07-10`), target and source did not match.

| Check | Source view | Physical target | Difference |
|---|---:|---:|---:|
| Row count | 322,308,000 | 297,803,484 | 24,504,516 |
| Resultant forecast sum | 1,953,660,039.000000 | 1,802,654,769.000000 | 151,005,270.000000 |
| Promotional lift sum | 13,602,110.000000 | 12,587,774.000000 | 1,014,336.000000 |
| Min snapshot | 2026-06-09 | 2026-06-09 | n/a |
| Max snapshot | 2026-07-08 | 2026-07-06 | n/a |

The source 30-day summary took about 90 seconds. The following duplicate checks for the full 30-day window were cancelled to avoid extra CU use.

### Staging Decision

Do not run the staging 30-day write during ad-hoc testing.

Recommended next step:

1. Do not run full PL yet.
2. Fix staging runtime separately in a controlled window.
3. Decide between two safe patterns:
   - Replace-window pattern using `usp_UpdateCuratedTableFromView_DateRange`, which gives exact source-window to target-window parity but deletes and reinserts hundreds of millions of rows.
   - Metadata-driven `usp_IncrementalTableLoad`, which follows the existing TableDictionary setup but requires source/target primary key metadata to be aligned first and may not remove stale target rows that disappeared from the source.
4. Because this staging table is a physical cache of source data, exact window replacement is safer for data parity. Metadata-driven incremental is more aligned with the current TableDictionary setup but needs a separate stale-row risk decision.

### 15-Day Staging Follow-Up

The staging window was reduced from 30 days to 15 days for this specific table.

Read-only 15-day test:

| Check | Source view | Physical target | Difference |
|---|---:|---:|---:|
| Row count | 161,221,968 | 136,717,452 | 24,504,516 |
| Resultant forecast sum | 979,213,391.000000 | 828,208,121.000000 | 151,005,270.000000 |
| Promotional lift sum | 6,689,276.000000 | 5,674,940.000000 | 1,014,336.000000 |
| Min snapshot | 2026-06-24 | 2026-06-24 | n/a |
| Max snapshot | 2026-07-08 | 2026-07-06 | n/a |

This confirms the target is behind the source in the recent window, but the 15-day write volume is materially smaller than 30 days.

The staging dedupe grain was also aligned to the `TableDictionary` grain:

```text
dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups
```

Read-only tests before the view change showed the current 15-day source had:

- 0 duplicate groups at 5-grain.
- 0 duplicate groups at 7-grain.

After deploying the 5-grain staging view:

| Check | Result |
|---|---:|
| 15-day duplicate groups at 5-grain | 0 |
| 15-day source row count | 161,221,968 |
| 15-day resultant forecast sum | 979,213,391.000000 |
| 15-day promotional lift sum | 6,689,276.000000 |
| 15-day source min snapshot | 2026-06-24 |
| 15-day source max snapshot | 2026-07-08 |

Live updates applied:

- `SupplyChain_Processing_Warehouse.Staging_Wrk.v_DemandForecastSnapshotDaily` now dedupes at 5-grain.
- `ETL_Framework.DW_Developer.TableDictionary` source and target primary keys now match at 5-grain.
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_Shared_Staging` now calls `usp_UpdateCuratedTableFromView_DateRange` with `-15`.

Important: the staging physical table was still not reloaded during this validation.

### Raw Enterprise Lakehouse Grain Check

Raw source checked:

```text
Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily
```

Grain checked:

```text
dfcItem, dfcWarehouse, dfcFiscalMonth, dfcSnapshot, DfcCustomerGroups
```

Selected snapshot source row counts:

| Snapshot | Raw source rows | Distinct items | Distinct warehouses | Resultant forecast sum | Promotional lift sum |
|---|---:|---:|---:|---:|---:|
| 2026-06-15 | 12,381,120 | 13,560 | 8 | 75,040,438.000000 | 528,558.000000 |
| 2026-07-06 | 12,246,336 | 13,495 | 8 | 75,577,258.000000 | 499,609.000000 |
| 2026-07-08 | 12,254,364 | 13,494 | 8 | 75,424,354.000000 | 513,753.000000 |

Duplicate checks:

| Scope | Duplicate 5-key groups | Extra rows | Max rows per 5-key |
|---|---:|---:|---:|
| Selected snapshots: 2026-06-15, 2026-07-06, 2026-07-08 | 0 | 0 | 0 |
| 15-day source window | 0 | 0 | 0 |

Because full-row duplicates would necessarily duplicate the 5-key as well, the zero 5-key duplicate result also means no full-row duplicates were present in these tested scopes.

This supports using the 5-key grain as the canonical raw-source grain for the current 15-day staging DateRange wrapper.

### Raw Source Full-History Check From 2023-01-01

The raw Enterprise Lakehouse source was also checked from `2023-01-01` through the latest available snapshot in the source.

Overall result:

| Scope | Raw rows checked | Duplicate 5-key groups | Extra rows | Max rows per 5-key | Min snapshot | Max snapshot |
|---|---:|---:|---:|---:|---|---|
| 2023-01-01 through 2026-07-08 | 7,253,113,436 | 1,512 | 1,512 | 2 | 2023-01-01 | 2026-07-08 |

The duplicates are isolated to one historical window:

| Window | Raw rows | Duplicate 5-key groups | Extra rows | Max rows per 5-key | Min snapshot | Max snapshot |
|---|---:|---:|---:|---:|---|---|
| 2023-04-16 through 2023-05-01 exclusive | 36,265,752 | 1,512 | 1,512 | 2 | 2023-04-17 | 2023-04-29 |
| 2023-05-01 through 2026-07-10 exclusive | 6,886,436,409 | 0 | 0 | 1 | 2023-05-01 | 2026-07-08 |

Drill result for the duplicate April 2023 window:

| Check | Result |
|---|---:|
| Distinct full rows across duplicated 5-key groups | 3,024 |
| Raw rows across duplicated 5-key groups | 3,024 |
| Exact full-row duplicate groups | 0 |
| Exact full-row extra rows | 0 |
| Max rows per exact full row | 1 |

This means the historical issue is not exact duplicated rows. It is same 5-key with different payload values. For example, duplicate rows had the same item, warehouse, fiscal month, snapshot, and customer group, but different forecast type and forecast values such as `dfcFCSTTypeCode = M` versus `dfcFCSTTypeCode = I`.

Decision from this audit:

- The 5-key grain is clean for the current operational 15-day source window.
- The 5-key grain is clean from `2023-05-01` forward.
- If a full historical rebuild from `2023-01-01` is required, the April 2023 exception needs a confirmed business rule before deduping at 5-key.
- The current 15-day DateRange staging change is not blocked by the April 2023 exception because the operational window does not touch that historical period.
