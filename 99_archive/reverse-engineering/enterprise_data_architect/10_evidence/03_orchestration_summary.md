# Orchestration Summary — `EnterpriseData-Dev` pipelines

> 22 pipelines + 18 notebooks + Mounted ADF + Databricks Mirror.

## Pipeline inventory

| Pipeline | Status | Frequency | Purpose |
|----------|--------|-----------|---------|
| `Source_EDW_Check_Test` | ✅ ACTIVE | Daily 03:50 UTC | Count + aggregate reconciliation EDW vs Fabric → email diff via Office365 |
| `EDW2FabricLoader` | ⚠️ Active (sporadic) | Manual | Reads `ASHLEY_EDW_DEV.dw_developer.FabricMapping` (Flag=1) → row-by-row Copy into Source_Data |
| `Fabric Migration ADF` | ⚠️ Active (sporadic) | Manual | Ports table definitions Synapse `Ashley_Edw.dw_developer.tabledictionary` → Fabric |
| `MetaData-Pull` (notebook) | ✅ Active | Daily | Cross-WH JDBC sync, populates Centralized_Warehouse |
| `Mirror Databricks edw_dev` | ✅ Active | autoSync | Live mirror Databricks UC → OneLake |
| 16-18 other pipelines | ❌ DORMANT | None | Definitions exist, no recent runs |

**Active rate: 3-5 of 22 pipelines** (~20%). Workspace is primarily a **definition store**, not active runner.

## Orchestration patterns observed

### Pattern 1: Daily reconciliation (`Source_EDW_Check_Test`)
```
1. Trigger 03:50 UTC daily
2. Lookup tables to check from DW_Developer.Source_EDW_CountCheck/AggCheck
3. ForEach table:
   - Run COUNT/aggregate in Fabric
   - Run COUNT/aggregate in EDW (linked service)
   - Compare delta
   - INSERT diff row
4. After loop: EXEC usp_GenerateEmailHTML_DimAggregateDiffer
5. Trigger Office365 connector (Logic App) to send email
```

### Pattern 2: Metadata-driven copy (`EDW2FabricLoader`)
```
1. Lookup config from ASHLEY_EDW_DEV.dw_developer.FabricMapping WHERE Flag=1
   → returns N rows: source/target table mappings
2. ForEach row (concurrency=N):
   - Copy activity: source linked service → Fabric Source_Data WH
   - Pre-copy: TRUNCATE target
   - Post-copy: EXEC usp_UpdateTableDictionary_ModifiedDate
3. Logs to AuditLog throughout
```

### Pattern 3: Domain refresh wrapper (e.g., `Usp_Refresh_Wholesale_Warehouse`)
```sql
-- This is a STORED PROC, not a pipeline activity
-- Wraps 100+ EXEC calls sequentially
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView 'Wholesale_Warehouse', 'CustomerOrders_AFI', 'OpenOrderHeader';
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView 'Wholesale_Warehouse', 'CustomerOrders_AFI', 'OpenOrderDetail';
EXEC ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView 'Wholesale_Warehouse', 'SalesHistory_AFI', 'InvoiceDetail';
-- ... 100+ more
```
→ Sequential, non-parallel. Each refresh updates TableDictionary.Modified via sub-proc call.

### Pattern 4: Cross-WS Copy (`test`, `pipeline1`)
```
1. Source: PROD workspace EnterpriseData (cross-WS shortcut)
2. Sink: SQLDatabase Commissions_Prototype
3. Misnamed but real production pipeline
```

## Comparison with VN team's pattern

| Aspect | Bob hub (`EnterpriseData-Dev`) | VN team (`Enterprise SupplyChain-Dev`) |
|--------|----------------------------------|------------------------------------------|
| Pipelines | 22 (3 active) | **7 active** (pl_sc_master orchestrates all) |
| Orchestration | Mix of pipeline ForEach + SP wrappers (sequential) | Pipeline ForEach + DAG waves (3-wave parallel batch=8) |
| Concurrency | Sequential per domain SP | **Parallel** within wave |
| Trigger | Daily 03:50 UTC for reconciliation | Daily 02:00 UTC for full master pipeline |
| Cross-domain dependency | Manual (in proc body) | **Automatic** (DAG computed from `depends_on` in AssetRegistry) |
| Multi-mart | Per-domain wrapper procs | `pl_sc_mart` ForEach DISTINCT project |
| Smart skip | None (everything refreshes) | **Active** (next_run_time filter in Lookup) |
| Audit chain | INSERT AuditLog at start/end of each proc | `usp_LogRun v2` chains 5 sinks (RunLog + AssetRegistry + AuditLog + UpdateLog + TableDictionary) |

## Notebooks (18 total)

Key notebook: **`MetaData-Pull`** — populates `Centralized_Warehouse.MetaData.*` tables from cross-WH probing. ⚠️ Cell 1 has plaintext SP secret. Use cell 2/3/4 with Key Vault.

Other notebooks: data quality validators, ad-hoc analysis. Most dormant.

## Mounted ADF + Databricks Mirror

- **Mounted ADF** `ashleyv2datafactory` (RG `IoT_Hub`) — legacy ADF still alive. Pipelines for SaaS feeds: UKG, AFI, Maximo, ServiceNow, Google Analytics. Surfaces inside Fabric workspace.
- **Mirror Databricks** catalog `edw_dev` — Full / autoSync mode. Live read-only mirror to Fabric OneLake. Last sync 2026-05-08 05:57 Success.

## Risks

- **38 of 41 orchestration items dormant** — definition drift risk. Many pipelines may not work if triggered (untested).
- **No central trigger** — each domain has its own refresh proc, manual sequencing.
- **Pipeline names misleading** (`test`, `pipeline1` are real cross-WS Copy operations).
- **Plaintext SP secret** in MetaData-Pull cell 1.

## Cross-refs

- Pipeline detail (raw): `_external_refs/enterprisedata-dev-01_docs/docs/04-orchestration/`
- Risks register: [`04_risks.md`](04_risks.md)
- VN comparison: [`../20_proposals/01_etl_framework_alignment.md`](../20_proposals/01_etl_framework_alignment.md)
