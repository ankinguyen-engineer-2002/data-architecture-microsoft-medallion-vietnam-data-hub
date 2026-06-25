# Domain team workflow — How Bob expects each value-stream team to add Silver tables

> Synthesized from observation of Wholesale + Retail patterns in `EnterpriseData-Dev`.

## The pattern

Each domain Silver warehouse is **owned by a value-stream team**:

| Domain WH | Owner team | Refresh wrapper proc |
|-----------|------------|----------------------|
| `Wholesale_Warehouse` | Wholesale team | `Wholesale_Warehouse.dbo.Usp_Refresh_Wholesale_Warehouse` |
| `Retail_Warehouse` | Retail team | `Retail_Warehouse.dbo.Usp_Refresh_Retail_Warehouse` (or similar — 146 procs) |
| `MasterData_Warehouse` | MasterData team | (loaded by ETL_Framework procs cross-WH, no internal procs) |
| `Distribution_Warehouse` | Distribution team | (incomplete) |
| `SupplyChain_Warehouse` (proposed) | **VN SC team** | `Usp_Refresh_SupplyChain_Warehouse` (to be created) |

## Adding a new Silver table — Wholesale team workflow (observed pattern)

### Step 1: Write the curated view in `_Wrk` schema
```sql
-- File: Wholesale_Warehouse/SalesHistory_AFI_Wrk/v_InvoiceDetail.sql
CREATE VIEW SalesHistory_AFI_Wrk.v_InvoiceDetail AS
SELECT
    TRIM(InvoiceID)        AS InvoiceID,
    TRIM(OrderID)          AS OrderID,
    CAST(InvoiceDate AS DATE) AS InvoiceDate,
    -- ... business logic transforms
FROM Source_Data.Wholesale_SalesHistory_AFI.InvoiceDetail_RAW
WHERE Status = 'Active';
```

### Step 2: Register the table in TableDictionary
```sql
-- One-time INSERT in ETL_Framework via PR / DBA
INSERT INTO ETL_Framework.DW_Developer.TableDictionary
    (ServerName, DatabaseName, SchemaName, TableName, ObjectType, StorageType,
     UpdateMethod, RefreshRate, ReplicatedSource, PrimaryKey)
VALUES
    ('EDW-Fabric', 'Wholesale_Warehouse', 'SalesHistory_AFI', 'InvoiceDetail', 'Table', 'Delta',
     'Insert', 24, 'SalesHistory_AFI_Wrk.v_InvoiceDetail', 'InvoiceID,OrderID');
```

### Step 3: Add the EXEC call to refresh wrapper proc
```sql
-- In Wholesale_Warehouse.dbo.Usp_Refresh_Wholesale_Warehouse:
ALTER PROCEDURE Usp_Refresh_Wholesale_Warehouse
AS
BEGIN
    -- ... existing 100+ EXEC calls ...
    EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
         'Wholesale_Warehouse', 'SalesHistory_AFI', 'InvoiceDetail';
    -- ... more EXECs ...
END;
```

### Step 4: PR review + merge
- Push PR to ADO `Enterprise Data Services/Fabric-EnterpriseData`
- Senior reviewer (per Bob's email — Rakesh/Ankit at his org) reviews
- Merge → auto-deploy via Fabric Git sync

### Step 5: Verify
- Run `Usp_Refresh_Wholesale_Warehouse` manually first time
- Check `AuditLog` for Process Start / Process End rows
- Check `TableDictionary.Modified` updated

## Refresh execution flow (per-table)

```
Pipeline trigger / manual EXEC
   ↓
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
     'WH', 'Schema', 'Table'
   │
   ├─→ INSERT AuditLog ('Process Start', SYSTEM_USER, fn_GetDate())
   │
   ├─→ Lookup TableDictionary row by (DatabaseName, SchemaName, TableName)
   │
   ├─→ DECLARE @SQL = build dynamic CTAS:
   │     SET @SQL = 'CREATE TABLE WH.Schema.Table_LOAD AS SELECT * FROM WH.Schema_Wrk.v_Table'
   │   EXEC sp_executesql @SQL
   │
   ├─→ DROP existing live table (if exists)
   │
   ├─→ sp_rename @WorkTable, @LiveTable
   │
   ├─→ EXEC usp_UpdateTableDictionary_ModifiedDate
   │     ├─→ INSERT TableDictionary_UpdateLog (DatabaseName, SchemaName, TableName, LastUpdated)
   │     └─→ INSERT AuditLog ('Process Start' for UpdateModifiedDate)
   │
   └─→ INSERT AuditLog ('Process End', SYSTEM_USER, fn_GetDate())
```

End of batch (separate trigger, e.g., end of day):
```
EXEC ETL_Framework.DW_Developer.usp_UpdateTableDictionaryModified
   └─→ UPDATE TableDictionary
       SET Modified = MAX(LastUpdated)
       FROM TableDictionary_UpdateLog
       WHERE Modified IS NULL OR Modified < MAX(LastUpdated)
```

## How VN team will adapt this for `SupplyChain_Warehouse`

### Difference: VN uses 1 generic proc, not per-table EXECs

VN's `Usp_Refresh_SupplyChain_Warehouse` (when created) will be:
```sql
CREATE PROCEDURE Usp_Refresh_SupplyChain_Warehouse
AS
BEGIN
    -- Read VN's AssetRegistry for assets with physical_workspace = hub WS ID
    -- Iterate via cross-DB call back to VN's pipeline orchestrator
    -- Or simpler: chain EXEC calls (Bob style) for hub-side execution

    EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
         'SupplyChain_Warehouse', 'Forecast_Enh', 'ForecastDemandMonthly';
    EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
         'SupplyChain_Warehouse', 'Forecast_Enh', 'NaiveForecastMonthly';
    EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
         'SupplyChain_Warehouse', 'Forecast_Enh', 'ForecastCycle';
    EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView
         'SupplyChain_Warehouse', 'Forecast_Enh', 'ForecastHorizon';
END;
```

### How VN's pipeline calls it
```
🇻🇳 pl_sc_master (VN workspace)
   ├─→ pl_sc_silver_wave (existing — for SC-specific Silver in VN WS)
   │      └─→ Meta.usp_GenericLoad (registry-driven, 1 generic SP)
   │
   └─→ NEW: pl_sc_hub_silver (NEW activity)
          └─→ Cross-DB call:
              EXEC EnterpriseData-Dev.<WS>.dbo.Usp_Refresh_SupplyChain_Warehouse
              (or per-table via ForEach loop reading from VN AssetRegistry filtered by physical_workspace=hub)
```

## Code review process

Bob's email 2026-05-09 confirms:

> "When checking in code to the repo, there will be a code review and approval process by a senior person before the pull request can be merged into the main branch. And there should be a design signed off by Rakesh before it gets built."

Translation:
1. **Design phase**: Rakesh approves design (e.g., "we're adding ForecastDemandMonthly as Silver shared cross-team")
2. **Build phase**: Engineer writes code in feature branch
3. **PR review**: Rakesh or Ankit (senior at Bob's org) reviews PR
4. **Merge**: After approval, merge to `main` → Fabric Git sync auto-deploys

VN team needs:
- ADO access to `Enterprise Data Services/Fabric-EnterpriseData` repo (pending Q4 unblock)
- Pull request workflow established with Rakesh/Ankit

## Cross-refs

- Cross-WS consumption: [`01_cross_workspace_consumption.md`](01_cross_workspace_consumption.md)
- Proposal for SupplyChain_Warehouse creation: [`../20_proposals/02_supply_chain_warehouse_proposal.md`](../20_proposals/02_supply_chain_warehouse_proposal.md)
- ETL framework alignment: [`../20_proposals/01_etl_framework_alignment.md`](../20_proposals/01_etl_framework_alignment.md)
