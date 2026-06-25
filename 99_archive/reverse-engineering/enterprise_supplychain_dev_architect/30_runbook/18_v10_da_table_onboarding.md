# v10 DA Table Onboarding Runbook
> Step-by-step cho DA/Data Analyst muốn ETL 1 bảng mới vào luồng `pl_sc_master` / `pl_sc_mart` v10.
>
> Scope: SupplyChain v10, Warehouse-native, Pure T-SQL, metadata-driven qua `Meta.AssetRegistry` + `Meta.usp_GenericLoad`.
> Last updated: 2026-05-26.

## 0. Mental model

[Verified] v10 không thêm bảng bằng cách sửa trực tiếp pipeline JSON. Pipeline đọc metadata từ `Meta.AssetRegistry`, sau đó gọi generic loader.

```text
DA request
  -> define source + target + grain
  -> create T-SQL view
  -> insert Meta.AssetRegistry row
  -> recompute DAG / lineage
  -> run one-table test
  -> activate in pl_sc_master / pl_sc_mart via is_active=1
```

Repo evidence:

- `projects/inventory_health/etl/registry_inserts.sql` shows the deploy order: views -> registry -> `usp_ComputeSilverWaves` -> `usp_BuildLineage` -> DQ.
- `projects/forecast/etl/meta_sps.sql` implements `Meta.usp_GenericLoad`, `Meta.usp_ComputeSilverWaves`, `Meta.usp_BuildLineage`, and run logging.
- `projects/forecast/40_pipelines.md` documents `pl_sc_master` reading `DISTINCT project` from `Meta.AssetRegistry`.

Microsoft docs context:

- [Verified] Fabric Lookup activity can return query results and pass them to ForEach/control-flow activities: <https://learn.microsoft.com/fabric/data-factory/lookup-activity>
- [Verified] Fabric ForEach can iterate items and can run items in parallel when not sequential: <https://learn.microsoft.com/fabric/data-factory/foreach-activity>
- [Verified] Fabric Data Warehouse supports CTAS (`CREATE TABLE AS SELECT`) for creating a table from query output: <https://learn.microsoft.com/fabric/data-warehouse/ingest-data-tsql#create-a-new-table-with-the-result-of-a-query>
- [Verified] Fabric Data Factory supports Data Warehouse Lookup, Script, and Stored Procedure activities: <https://learn.microsoft.com/fabric/data-factory/connector-data-warehouse-overview>

## 1. DA intake checklist

Before writing SQL, capture these fields in the ticket/design note:

```text
Business name:
Owner DA:
Project/mart: forecast_accuracy | inventory_health | <new_mart>
Target layer: ReferenceMaster | DomainSilver | Gold
Target schema.table:
Source object(s):
Expected grain:
Primary key:
Watermark/date key:
Expected rows:
Expected refresh frequency:
DQ expectation:
Downstream Power BI table/measure:
Rollback expectation:
```

Naming rule (do not mix these up):

- `project` = mart/control-plane tag, for example `forecast_accuracy`, `inventory_health`, `shared`
- `physical_schema` = actual warehouse schema, for example `ForecastHistory_Enh`, `InventoryHistory_Enh`, `Shared_DW`
- [Verified] 2026-06-15 live cleanup normalized Mart B so no active row should use a schema-like value such as `inventoryHistory_Enh` in the `project` column

Do not proceed to `is_active=1` if any of these are unknown:

- Grain is not defined.
- Primary key or duplicate tolerance is unknown.
- Source is stale or incomplete.
- DA cannot provide at least one row-count or business reconciliation check.
- New table feeds Gold/semantic model but relationships/measures are not reviewed.

## 2. DA responsibility boundary

[Verified] For a normal v10 onboarding request, DA should only need to prepare the SQL-facing artifacts and registry metadata. DA should not edit pipeline JSON.

DA-owned work:

```text
1. Define source, target, grain, primary key, refresh frequency.
2. Create/modify the T-SQL transform view.
3. Add the registry row in Meta.AssetRegistry with is_active=0.
4. Add optional DQ rules.
5. Provide validation evidence: row count, duplicate check, null check, business reconciliation.
```

DE/Ops-owned approval and execution:

```text
1. Review source freshness, load_type, primary key, and dependency graph.
2. Run or approve one-table materialization.
3. Recompute Silver DAG and lineage.
4. Approve is_active=1.
5. Trigger mart/master pipeline or schedule activation.
6. Review semantic model impact for Gold/user-facing tables.
```

Important boundary:

- If the table is ReferenceMaster or DomainSilver, DA normally creates a view and registry row; `Meta.usp_GenericLoad` creates/materializes the physical table.
- If staging is required, a physical staging table may be needed, but that is an exception path and should be reviewed by DE/Ops.
- If the table is Gold, use the `pl_sc_gold` path because Gold publish is cross-DB CTAS from pipeline.

## 3. Choose the target path

Use this decision tree:

```text
Is the table only a reusable master/reference lookup?
  -> ReferenceMaster layer

Is it a process/domain table used by one mart?
  -> DomainSilver layer

Is it directly consumed by Power BI as dim/fact/helper?
  -> Gold layer

Is the Enterprise_Lakehouse source missing/stale but DA needs data now?
  -> Staging exception or SC_LH workaround
  -> Keep is_active=0 unless fallback source is validated
```

Recommended file placement:

```text
Enterprise_SupplyChain_Dev_architect/projects/<mart>/etl/
  staging_ddl.sql       optional staging tables only
  silver_views.sql      ReferenceMaster + DomainSilver views
  gold_views.sql        Gold serving views
  registry_inserts.sql  Meta.AssetRegistry rows
  dq_rules_inserts.sql  optional DQ rules
```

## 4. Case A: ETL lại 1 bảng đã có trong registry

Use case:

```text
DA nói: "Bảng đã tồn tại rồi, chạy lại ETL riêng bảng này giúp tôi."
```

### Step 1: Confirm registry state

```sql
SELECT
    asset_id,
    project,
    canonical_layer,
    physical_schema,
    physical_object,
    legacy_view_name,
    load_type,
    primary_key,
    watermark_column,
    date_key,
    depends_on,
    is_active,
    next_run_time,
    access_mode
FROM Meta.AssetRegistry
WHERE asset_id = '<Schema>.<TableName>'
   OR (physical_schema = '<Schema>' AND physical_object = '<TableName>');
```

Pass condition:

- Exactly one row is returned.
- `legacy_view_name` points to the expected view.
- `load_type` matches the intended reload behavior.
- For `incremental` / `datekey` / `daterange`, watermark/date metadata is present.

### Step 2: Smoke-test the source view

```sql
SELECT TOP 100 *
FROM <Schema>.v_<TableName>;

SELECT COUNT(*) AS view_row_count
FROM <Schema>.v_<TableName>;
```

If this fails, fix the view/source first. Do not trigger the loader against a broken view.

### Step 3: Run the one-table load

For ReferenceMaster or DomainSilver tables in `SupplyChain_Processing_Warehouse`:

```sql
EXEC Meta.usp_GenericLoad
    @target_schema = '<Schema>',
    @target_table  = '<TableName>';
```

For Gold tables:

- [Verified] Use `pl_sc_gold` / mart pipeline path when possible, because current project docs state Gold publish is cross-DB CTAS from pipeline, not the Silver generic SP path.
- If testing manually, run the same CTAS pattern in the Gold Warehouse connection only after checking the target is safe to recreate.

Gold CTAS pattern:

```sql
-- Run in SupplyChain_Gold_Warehouse only.
-- Do not run this for an existing production-facing table without approval.
CREATE TABLE <GoldSchema>.<GoldTable> AS
SELECT *
FROM <GoldSchema>.v_<GoldTable>;
```

### Step 4: Verify run result

```sql
SELECT COUNT(*) AS physical_row_count
FROM <Schema>.<TableName>;

SELECT TOP 20
    run_id,
    asset_id,
    object_name,
    layer_name,
    status,
    rows_loaded,
    error_message,
    start_time_utc,
    end_time_utc
FROM Meta.RunLog
WHERE asset_id = '<Schema>.<TableName>'
ORDER BY start_time_utc DESC;
```

### Step 5: Rebuild lineage only if source metadata changed

```sql
EXEC Meta.usp_BuildLineage;
```

If only re-running the same table with unchanged registry metadata, lineage rebuild is optional.

## 5. Case B: add one new Silver or Reference table into ETL flow

Example target:

```text
Project: inventory_health
Layer: DomainSilver
Target: InventoryHistory_Enh.SupplierLeadTime
Source: Enterprise_Lakehouse.Purchasing_AFI.SupplierLeadTime
View: InventoryHistory_Enh.v_SupplierLeadTime
Load type: overwrite
Frequency: daily
```

### Step 1: Create or extend the SQL view

Add a view to `projects/<mart>/etl/silver_views.sql`.

```sql
CREATE VIEW InventoryHistory_Enh.v_SupplierLeadTime AS
SELECT
    CAST(TRIM(s.VendorNumber) AS VARCHAR(50))       AS VendorNumber,
    CAST(TRIM(s.ItemSku) AS VARCHAR(50))            AS ItemSku,
    CAST(s.LeadTimeDays AS INT)                     AS LeadTimeDays,
    CAST(s.EffectiveDate AS DATE)                   AS EffectiveDate,
    CAST('Purchasing_AFI' AS VARCHAR(64))           AS SourceSystem,
    CAST('SupplierLeadTime' AS VARCHAR(128))        AS SourceTable
FROM [Enterprise_Lakehouse].[Purchasing_AFI].[SupplierLeadTime] s
WHERE s.VendorNumber IS NOT NULL
  AND TRIM(s.VendorNumber) <> ''
  AND s.ItemSku IS NOT NULL
  AND TRIM(s.ItemSku) <> '';
```

Rules:

- Use explicit casts, not implicit type inference.
- Normalize business keys with `TRIM`.
- Preserve source tracing columns such as `SourceSystem` / `SourceTable` when useful.
- Do not add `LoadDT`; `Meta.usp_GenericLoad` injects `LoadDT` during CTAS/insert.

### Step 2: Smoke-test the view before registry insert

Run in `SupplyChain_Processing_Warehouse`:

```sql
SELECT TOP 100 *
FROM InventoryHistory_Enh.v_SupplierLeadTime;

SELECT COUNT(*) AS row_count
FROM InventoryHistory_Enh.v_SupplierLeadTime;

SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT CONCAT(VendorNumber, '|', ItemSku, '|', EffectiveDate)) AS distinct_key_count
FROM InventoryHistory_Enh.v_SupplierLeadTime;
```

Pass condition:

- Query compiles.
- Row count is not unexpectedly zero.
- `row_count = distinct_key_count` if the selected primary key is supposed to be unique.

### Step 3: Insert `Meta.AssetRegistry` row

Add a row to `projects/<mart>/etl/registry_inserts.sql`.

```sql
DECLARE @ws VARCHAR(128) = 'c8d9fc83-18b6-4e1d-8264-0b49eed36fe0';
DECLARE @wh_proc VARCHAR(128) = 'SupplyChain_Processing_Warehouse';

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES (
    'InventoryHistory_Enh.SupplierLeadTime',
    'inventory_health',
    'DomainSilver',
    @ws,
    @wh_proc,
    'InventoryHistory_Enh',
    'SupplierLeadTime',
    'InventoryHistory_Enh.v_SupplierLeadTime',
    'overwrite',
    'VendorNumber,ItemSku,EffectiveDate',
    '["Enterprise_Lakehouse.Purchasing_AFI.SupplierLeadTime"]',
    NULL,
    'daily',
    '0 2 * * *',
    0,
    'WarehouseTransform'
);
```

Start with `is_active=0` until the one-table test passes. Flip to `1` only after validation.

### Step 4: Recompute Silver DAG if this is DomainSilver

```sql
EXEC Meta.usp_ComputeSilverWaves;

SELECT *
FROM Meta.SilverDagWaveRuntime
WHERE asset_id = 'InventoryHistory_Enh.SupplierLeadTime';
```

Expected:

- New asset appears in `Meta.SilverDagWaveRuntime`.
- Wave number is correct based on `depends_on`.
- If `depends_on IS NULL`, it should usually land in Wave 0.

### Step 5: Build lineage

```sql
EXEC Meta.usp_BuildLineage;

SELECT source_asset, target_asset, edge_type, transform_type
FROM Meta.LineageEdge
WHERE target_asset = 'InventoryHistory_Enh.SupplierLeadTime';
```

Expected:

- Each object in `source_objects` creates a lineage edge.
- `target_asset` equals the registry `asset_id`.

### Step 6: Run one-table materialization manually

```sql
EXEC Meta.usp_GenericLoad
    @target_schema = 'InventoryHistory_Enh',
    @target_table  = 'SupplierLeadTime';
```

Then verify:

```sql
SELECT COUNT(*) AS physical_row_count
FROM InventoryHistory_Enh.SupplierLeadTime;

SELECT TOP 50 *
FROM Meta.RunLog
WHERE asset_id = 'InventoryHistory_Enh.SupplierLeadTime'
ORDER BY start_time_utc DESC;
```

Pass condition:

- Physical table exists.
- Row count matches view expectation.
- Latest `Meta.RunLog.status = 'success'`.

### Step 7: Add DQ rules

Add to `projects/<mart>/etl/dq_rules_inserts.sql` if the mart has this file.

```sql
INSERT INTO Meta.DQRule (
    rule_name, target_schema, target_table, layer,
    check_type, column_name, severity, threshold, is_active
) VALUES
('SupplierLeadTime VendorNumber completeness', 'InventoryHistory_Enh', 'SupplierLeadTime', 'DomainSilver',
 'completeness', 'VendorNumber', 'CRITICAL', 100.0, 1),
('SupplierLeadTime row count minimum', 'InventoryHistory_Enh', 'SupplierLeadTime', 'DomainSilver',
 'row_count', NULL, 'CRITICAL', 1, 1);
```

Run:

```sql
EXEC Meta.usp_CheckDqSingle @rule_id = <new_rule_id>;
```

### Step 8: Activate in the ETL flow

After view, registry, lineage, DAG, load, and DQ are green:

```sql
UPDATE Meta.AssetRegistry
SET is_active = 1
WHERE asset_id = 'InventoryHistory_Enh.SupplierLeadTime';

EXEC Meta.usp_ComputeSilverWaves;
EXEC Meta.usp_BuildLineage;
```

[Verified] Once active, `pl_sc_master` / `pl_sc_mart` can pick it up through registry-driven lookup. No pipeline JSON change is expected for a normal ReferenceMaster/DomainSilver/Gold table.

## 6. Case C: add one new Gold table into ETL flow

Gold table example:

```text
Target: InventoryHealth_DW.DimSupplierLeadTime
View: InventoryHealth_DW.v_DimSupplierLeadTime
Source: InventoryHistory_Enh.SupplierLeadTime
Load type: overwrite
```

### Step 1: Create Gold view

Add to `projects/<mart>/etl/gold_views.sql`.

```sql
CREATE VIEW InventoryHealth_DW.v_DimSupplierLeadTime AS
SELECT
    VendorNumber,
    ItemSku,
    EffectiveDate,
    LeadTimeDays,
    SourceSystem,
    SourceTable
FROM [SupplyChain_Processing_Warehouse].[InventoryHistory_Enh].[SupplierLeadTime];
```

### Step 2: Register Gold asset

```sql
DECLARE @ws VARCHAR(128) = 'c8d9fc83-18b6-4e1d-8264-0b49eed36fe0';
DECLARE @wh_gold VARCHAR(128) = 'SupplyChain_Gold_Warehouse';

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES (
    'InventoryHealth_DW.DimSupplierLeadTime',
    'inventory_health',
    'Gold',
    @ws,
    @wh_gold,
    'InventoryHealth_DW',
    'DimSupplierLeadTime',
    'InventoryHealth_DW.v_DimSupplierLeadTime',
    'overwrite',
    'VendorNumber,ItemSku,EffectiveDate',
    '["InventoryHistory_Enh.SupplierLeadTime"]',
    'InventoryHistory_Enh.SupplierLeadTime',
    'daily',
    '0 5 * * *',
    0,
    'GoldPublish'
);
```

### Step 3: Manual load and verify

[Verified] Current v10 project docs describe Gold publish as `pl_sc_gold`: lookup active Gold registry rows for the project, then ForEach dynamic `DROP TABLE IF EXISTS` + `CREATE TABLE AS SELECT * FROM <legacy_view_name>` in `SupplyChain_Gold_Warehouse`.

For normal onboarding, validate by running the project/mart Gold path after the row is reviewed. Do not assume `Meta.usp_GenericLoad` is the Gold path; it is the ReferenceMaster/DomainSilver path in the Processing Warehouse.

Gold manual CTAS is only for an isolated test table or approved reload:

```sql
-- Run in SupplyChain_Gold_Warehouse.
CREATE TABLE InventoryHealth_DW.DimSupplierLeadTime AS
SELECT *
FROM InventoryHealth_DW.v_DimSupplierLeadTime;
```

Verification SQL:

```sql
SELECT COUNT(*) AS row_count
FROM InventoryHealth_DW.DimSupplierLeadTime;

SELECT source_asset, target_asset
FROM Meta.LineageEdge
WHERE target_asset = 'InventoryHealth_DW.DimSupplierLeadTime';
```

Only then set `is_active=1`.

## 7. Load type decision guide

Use this as the first-pass choice, then validate with row counts and runtime.

| load_type | Use when | Required metadata | Risk |
|---|---|---|---|
| `overwrite` | Table is small/medium, or source view is already scoped to current snapshot | `legacy_view_name`, `primary_key` recommended | Recreates target table; review downstream impact |
| `incremental` | Source has reliable increasing timestamp/date | `watermark_column` | Late-arriving data can be missed |
| `datekey` | Daily snapshot table; rerun should replace one day | `date_key` or `watermark_column` | Predicate must match the view's date semantics |
| `daterange` | Late-arriving window needs rolling reload | `date_key`/`watermark_column`, `date_range_days` | Higher runtime/cost |
| `upsert` | Source emits changed full rows by key | `primary_key` | Multi-column PK handling must be tested carefully |
| `identity` | Append-only source with increasing numeric key | `primary_key` | Reopened/corrected old rows are missed |
| `cdc` | CDC-style changed rows | `primary_key`, optional `watermark_column` | Depends on source CDC correctness |
| `scd2` | Need history of dimension changes | `primary_key` | Validate current/expired record logic before activation |

## 8. Validation checklist before DA sign-off

Run this checklist for every new table:

- [ ] View compiles.
- [ ] View row count is expected.
- [ ] Primary key duplicate check passes or duplicate tolerance is documented.
- [ ] Null checks pass for business-critical columns.
- [ ] Registry row has correct `project`, `canonical_layer`, `access_mode`, and `is_active`.
- [ ] `source_objects` contains all real upstream sources.
- [ ] `depends_on` contains intra-pipeline dependencies only, not every external source.
- [ ] `Meta.usp_ComputeSilverWaves` is rerun for DomainSilver.
- [ ] `Meta.usp_BuildLineage` is rerun.
- [ ] `Meta.usp_GenericLoad` succeeds manually.
- [ ] `Meta.RunLog` shows success and expected row count.
- [ ] DQ rules exist or the reason for no DQ is documented.
- [ ] Gold/semantic impact is reviewed if the table is user-facing.
- [ ] Only after all checks, set `is_active=1`.

## 9. Common failure modes

### Duplicate primary key

Symptom:

```text
row_count > distinct_key_count
```

Action:

- Confirm grain with DA.
- Add missing key columns.
- If duplicates are valid, do not call it a primary key; document grain and DQ tolerance.

### Table does not appear in pipeline

Check:

```sql
SELECT asset_id, project, canonical_layer, is_active, next_run_time
FROM Meta.AssetRegistry
WHERE asset_id = '<asset_id>';
```

Likely causes:

- `is_active=0`.
- Wrong `project`.
- Smart skip: `next_run_time` is in the future.
- Wrong layer filter in the relevant pipeline lookup.

### Lineage missing

Check:

```sql
SELECT source_objects
FROM Meta.AssetRegistry
WHERE asset_id = '<asset_id>';

EXEC Meta.usp_BuildLineage;
```

Likely causes:

- `source_objects` is empty or malformed.
- Source object list does not match the actual SQL view.
- The row was inserted after the last lineage rebuild.

### Incremental misses records

Action:

- Recheck `watermark_column`.
- Validate late-arriving source behavior.
- Consider `daterange` or `overwrite` if source volume allows.

## 10. PR checklist

Minimum files for a normal table:

```text
projects/<mart>/etl/silver_views.sql
projects/<mart>/etl/registry_inserts.sql
projects/<mart>/etl/dq_rules_inserts.sql   optional but recommended
```

Minimum files for a Gold table:

```text
projects/<mart>/etl/gold_views.sql
projects/<mart>/etl/registry_inserts.sql
projects/<mart>/04_semantic/                 if model needs table/relationship/measure update
```

PR description should include:

```text
What:
- Added <schema.table> to <project> as <canonical_layer>.

Why:
- <business reason>

Validation:
- View row count:
- Physical table row count:
- PK duplicate check:
- DQ checks:
- Lineage check:
- RunLog status:

Risk:
- Source freshness:
- Load type:
- Downstream semantic impact:
```

## 11. Do not do these

- Do not edit pipeline JSON for a normal new table.
- Do not set `is_active=1` before manual one-table load succeeds.
- Do not use `incremental` without proving watermark behavior.
- Do not hide staging/workaround sources; put them in `source_objects`.
- Do not add a Gold table without checking semantic model impact.
- Do not run destructive cleanup or table drops outside the approved loader path without explicit approval.

## 12. Quick template

Copy this block and replace values:

```sql
-- 1) View smoke test
SELECT COUNT(*) AS view_row_count
FROM <schema>.v_<TableName>;

-- 2) Registry insert starts inactive
INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES (
    '<Schema>.<TableName>',
    '<project>',
    '<ReferenceMaster|DomainSilver|Gold>',
    'c8d9fc83-18b6-4e1d-8264-0b49eed36fe0',
    '<SupplyChain_Processing_Warehouse|SupplyChain_Gold_Warehouse>',
    '<Schema>',
    '<TableName>',
    '<Schema>.v_<TableName>',
    '<overwrite|incremental|datekey|daterange|upsert|identity|cdc|scd2>',
    '<PrimaryKey>',
    '["<SourceObject1>","<SourceObject2>"]',
    '<DependencyAssetOrNULL>',
    '<daily|weekly|monthly>',
    '<cron>',
    0,
    '<WarehouseTransform|GoldPublish>'
);

-- 3) Recompute operational metadata
EXEC Meta.usp_ComputeSilverWaves;
EXEC Meta.usp_BuildLineage;

-- 4) Manual one-table run
EXEC Meta.usp_GenericLoad
    @target_schema = '<Schema>',
    @target_table  = '<TableName>';

-- 5) Verify
SELECT COUNT(*) AS physical_row_count
FROM <Schema>.<TableName>;

SELECT TOP 20 *
FROM Meta.RunLog
WHERE asset_id = '<Schema>.<TableName>'
ORDER BY start_time_utc DESC;

-- 6) Activate only after all checks pass
UPDATE Meta.AssetRegistry
SET is_active = 1
WHERE asset_id = '<Schema>.<TableName>';
```
