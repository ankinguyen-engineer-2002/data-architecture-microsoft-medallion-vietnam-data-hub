# Supply Chain Load Pattern Bench Results

**Date:** 2026-07-09

**Execution scope:** Phase -1 framework pattern bench test only.

**Live mart impact:** none.

No existing Forecast Accuracy or Inventory Health business ETL SQL logic was changed. No existing production mart table DDL was changed. Bench objects were created under isolated `LoadPatternBench` schemas and then removed.

---

## 1. Patterns Tested

Two enterprise framework patterns were tested with tiny isolated objects:

```text
1. ETL_Framework.DW_Developer.usp_UpdateCuratedTableFromView_DateRange
2. ETL_Framework.DW_Developer.usp_IncrementalTableLoad with UpdateMethod = DateRange
```

Test database:

```text
SupplyChain_Processing_Warehouse
```

Supporting metadata database:

```text
ETL_Framework
```

Gold warehouse was audited for active/query history impact, but no bench load was executed against Gold.

---

## 2. Happy-Path Result

### `usp_UpdateCuratedTableFromView_DateRange`

Sample setup:

```text
Target rows:
  old outside-window row
  inside-window row to update
  inside-window row to delete
  boundary-date row

Source rows:
  updated inside-window row
  new inside-window row
  boundary-date row
  outside-window source row
```

Observed result:

```text
outside_window_preserved  PASS
inside_update_replaced    PASS
inside_delete_removed     PASS
inside_new_inserted       PASS
boundary_included         PASS
source_outside_not_inserted PASS
rerun_idempotent_business_values PASS
```

Interpretation:

```text
The pattern behaves correctly for delete-and-insert date-window replacement on a clean source window.
```

### `usp_IncrementalTableLoad DateRange`

Sample setup:

```text
Target rows:
  old outside-window row
  inside-window row to update
  inside-window row to delete
  boundary-date row

Source rows:
  updated inside-window row
  new inside-window row
  boundary-date row
  outside-window source row
```

Observed result:

```text
outside_window_preserved  PASS
inside_update_replaced    PASS
inside_delete_removed     PASS
inside_new_inserted       PASS
boundary_included         PASS
source_outside_not_inserted PASS
rerun_idempotent_business_values PASS
temp_table_cleanup        PASS
```

Interpretation:

```text
The pattern behaves correctly for key/date-driven update/delete/insert on a clean source window.
```

---

## 3. Risk-Case Result

### Empty Source Window

Observed result:

```text
DateRange empty source:
  outside row preserved
  inside window was wiped
  result = OBSERVED_RISK

Incremental DateRange empty source:
  outside row preserved
  inside window was deleted
  result = OBSERVED_RISK
```

Interpretation:

```text
Both raw framework procedures need a source-window pre-check before production use.
If source window is unexpectedly empty, do not run delete/insert/update logic.
```

Required production control:

```text
Before load:
  SELECT COUNT_BIG(*) FROM source_window

If count = 0 and non-empty is expected:
  stop the load
  do not delete target rows
```

### Duplicate Source Grain

Observed result:

```text
DateRange duplicate source:
  duplicate target rows were created
  result = OBSERVED_RISK

Incremental DateRange duplicate source:
  duplicate target rows were created
  result = OBSERVED_RISK
```

Interpretation:

```text
Both raw framework procedures assume the source window is already unique at the target grain.
They do not protect the target from duplicate source grain.
```

Required production control:

```text
Before load:
  run grain duplicate DQ on the source window

If duplicate grain exists:
  stop the load
  fix source/dedupe logic first
```

---

## 4. Query Insights Audit

### Processing Warehouse

`queryinsights.exec_requests_history` captured the bench statements.

Relevant observations:

```text
usp_UpdateCuratedTableFromView_DateRange happy-path calls:
  status = Succeeded
  elapsed approx 2.7s and 7.8s
  data scanned remote/memory/disk = 0 MB on bench objects

usp_IncrementalTableLoad risk/happy-path calls:
  status = Succeeded
  elapsed approx 4.1s to 4.8s for risk cases
  data scanned remote/memory/disk = 0 MB on bench objects

Validation SELECTs:
  succeeded
  small row counts
```

Note:

Some Query Insights inspection queries themselves scanned query history metadata. These are not mart data scans.

### ETL Framework

`queryinsights.exec_requests_history` captured the dynamic SQL inside framework procedures.

Important finding for `usp_IncrementalTableLoad`:

```text
It performs:

CREATE TABLE <target>_Temp AS
SELECT columns
FROM source
```

For the bench object, this scanned 0 MB because the source was tiny.

For real 10B-row sources, this is the main risk. If source is not already window-filtered, the procedure can still scan too much data before applying DateRange logic.

### Gold Warehouse

Gold warehouse was checked.

Observed:

```text
No bench load ran in Gold.
No active user request was found during the audit.
```

Gold still needs Query Insights audit when the Gold shadow pilot starts, especially for:

```text
ForecastAccuracy_DW.FactForecastKpi
ForecastAccuracy_DW.FactForecastActual
```

---

## 5. Cleanup Verification

All bench objects were removed after the test.

Verified:

```text
Remaining LoadPatternBench objects: 0
Remaining LoadPatternBench TableDictionary rows: 0
```

Persistent evidence left intentionally:

```text
ETL_Framework.DW_Developer.AuditLog entries
queryinsights.exec_requests_history records
this result document
```

---

## 6. Decision

Both US framework patterns are usable, but not safe to call raw against production mart objects without guardrails.

Recommended next step:

```text
Build a controlled shadow pilot for ForecastHistory_Enh.ForecastDemandMonthly.
Use date-window replacement.
Add source-window non-empty check.
Add source grain duplicate check.
Compare candidate output to full-overwrite baseline.
Audit Query Insights before extending to staging/gold.
```

Preferred downstream pattern:

```text
usp_UpdateCuratedTableFromView_DateRange
```

Reason:

```text
It is simpler and easier to reason about for aggregate/snapshot window replacement.
It matches the expected behavior for downstream tables with a real date column.
```

Use `usp_IncrementalTableLoad DateRange` only when:

```text
source and target columns match
source and target grain are stable
source window is already filtered or proven cheap
TableDictionary metadata is correct
```

Do not apply either pattern directly to the large staging source until filter-before-dedupe is proven.
