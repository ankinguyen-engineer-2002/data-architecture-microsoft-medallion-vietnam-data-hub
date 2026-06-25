# Context 2026-06-24 to 2026-06-25

## 2026-06-24 08:35:35 (ICT) — Removed repo-native Lineage Workbench visual experiment

**Scope lock:**
- Repo cleanup only; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Delete the repo-native Lineage Workbench visual experiment because the generated graph/UI was too visually cluttered and not useful enough.

**Actions executed:**
- Uninstalled local VS Code extension:
  - `aric-nguyen-local.supplychain-lineage-workbench`
- Deleted active experiment artifacts:
  - `05_tools/lineage_workbench/`
  - `02_marts/forecast_accuracy/05_lineage/`
  - `02_marts/inventory_health/05_lineage/`
  - `.vscode/tasks.json`
  - `01_docs/plans/2026-06-23-lineage-workbench-compiler.md`
  - `01_docs/decisions/ADR-010-lineage-workbench.md`
- Kept mart DQ evidence:
  - `02_marts/*/04_dq/`
  - `05_tools/audit_bronze_source_dq.py`
  - `05_tools/audit_all_bronze_source_dq_final.py`
- Updated active docs to remove Lineage Workbench references:
  - `README.md`
  - `02_marts/README.md`
  - `03_operations/README.md`
  - `05_tools/README.md`
  - `02_marts/*/04_dq/README.md`

**Verification:**
- Active grep across `README.md`, `AGENTS.md`, `01_docs`, `02_marts`, `03_operations`, `04_semantic`, `05_tools`, `.vscode` found no references to:
  - `lineage_workbench`
  - `SupplyChain Lineage`
  - `05_lineage`
  - `ADR-010`
  - `global_catalog`
  - `aric-nguyen-local.supplychain-lineage-workbench`
- Active mart folder surface is back to:
  - `00_source_wrk/`
  - `01_bronze/`
  - `02_silver/`
  - `03_gold/`
  - `04_dq/`
  - `99_history/`

**Next step:**
- If lineage is revisited later, use a simpler non-visual source-of-truth approach first, likely manifest/table-level dependency metadata, before attempting another graph UI.
## 2026-06-24 08:46:57 (ICT) — Cleaned `05_tools` into functional hubs

**Scope lock:**
- Repo cleanup only; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Clean up `05_tools` because the flat script list looked cluttered.

**Actions executed:**
- Reorganized root `05_tools` from flat scripts into numbered functional hubs:
  - `05_tools/01_dq/`
  - `05_tools/02_repo_maintenance/`
  - `05_tools/03_mart_sync/`
- Moved scripts:
  - `audit_bronze_source_dq.py` -> `05_tools/01_dq/`
  - `audit_all_bronze_source_dq_final.py` -> `05_tools/01_dq/`
  - `restructure_mart_layer_sql.py` -> `05_tools/02_repo_maintenance/`
  - `split_context.py` -> `05_tools/02_repo_maintenance/`
  - `sync_live_mart_layers.py` -> `05_tools/03_mart_sync/`
- Added README files for each tool hub and updated DQ README command references.
- Patched script root-path resolution after the move.
- Added `--help`/`--out-dir` CLI handling to `audit_all_bronze_source_dq_final.py` so help no longer starts a live read-only audit accidentally.

**Verification:**
- `python3 -m py_compile` passed for all five moved scripts.
- `python3 05_tools/01_dq/audit_bronze_source_dq.py --help` passed.
- `python3 05_tools/01_dq/audit_all_bronze_source_dq_final.py --help` passed and did not run live audit.
- `05_tools` root now contains only:
  - `README.md`
  - `01_dq/`
  - `02_repo_maintenance/`
  - `03_mart_sync/`
## 2026-06-24 09:07:07 (ICT) — Built DQ and catalog operating packages

**Scope lock:**
- Repo-only operating metadata; no live Fabric/Power BI/SQL mutation.
- Phase 2 remains deferred.

**User instruction:**
- Improve the repo-as-docs-and-operations system by packaging Bronze DQ and lineage/catalog properly after the visual Lineage Workbench experiment was rejected.

**Actions executed:**
- Added repeatable generator:
  - `05_tools/04_operating_package/build_operating_package.py`
  - `05_tools/04_operating_package/README.md`
- Generated Bronze DQ operating packs for both active marts:
  - `02_marts/<mart>/04_dq/contracts/bronze_sources.json`
  - `02_marts/<mart>/04_dq/contracts/rules.json`
  - `02_marts/<mart>/04_dq/contracts/exceptions.json`
  - `02_marts/<mart>/04_dq/runs/latest.json`
- Generated mart catalog/lineage registries:
  - `02_marts/<mart>/05_catalog/assets.json`
  - `02_marts/<mart>/05_catalog/lineage_edges.json`
  - `02_marts/<mart>/05_catalog/run_order.json`
  - `02_marts/<mart>/05_catalog/semantic_bindings.json`
- Generated all-mart operating rollup:
  - `03_operations/operating_registry/summary.json`
  - `03_operations/operating_registry/assets.json`
  - `03_operations/operating_registry/lineage_edges.json`
  - `03_operations/operating_registry/dq_summary.json`
  - `03_operations/operating_registry/run_order.json`
- Updated active docs:
  - `README.md`
  - `02_marts/README.md`
  - `02_marts/forecast_accuracy/README.md`
  - `02_marts/inventory_health/README.md`
  - `02_marts/*/04_dq/README.md`
  - `03_operations/README.md`
  - `05_tools/README.md`

**Generated package summary:**
- Marts packaged: `2`
- Bronze DQ sources packaged: `42`
- Repo catalog assets: `161`
- Catalog/lineage edges: `183`
- Forecast Accuracy:
  - DQ sources: `17`
  - DQ pass: `14`
  - DQ review: `3`
  - catalog assets: `73`
  - lineage edges: `74`
  - run-order steps: `13`
- Inventory Health:
  - DQ sources: `25`
  - DQ pass: `16`
  - DQ review: `9`
  - catalog assets: `88`
  - lineage edges: `109`
  - run-order steps: `18`

**Notable DQ exceptions now machine-readable:**
- Forecast Accuracy: `SalesHistory_AFI_Enh.InvoiceDetail`, `Wholesale_Codis_AFI.codatan`, `Wholesale_Codis_AFI.EXTORD`.
- Inventory Health: `Inventory_Enh_History.ItemBalance`, `ItemMaster_AFI.ITBEXT`, `ItemMaster_AFI.ITMRVA`, `Manufacturing_Inventory_AFI.TFRDTL`, `SalesHistory_AFI_Enh.InvoiceDetail`, `SupplyChain_Enh.DemandForecastSnapshotDaily`, `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`, `SupplyChain_Enh.DemandInventorySnapshotDaily`, `SupplyChain_Enh.PurchaseOrderSnapshot`.

**Verification:**
- `python3 -m py_compile 05_tools/04_operating_package/build_operating_package.py` passed.
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed.
- JSON validation passed for generated DQ contracts/runs, mart catalogs, and all-mart operating registry.
- Active grep found no stale `lineage_workbench`, `SupplyChain Lineage`, `05_lineage`, or old flat `05_tools/*.py` command paths.

**Next step:**
- Use `03_operations/operating_registry/summary.json` and `02_marts/*/04_dq/contracts/exceptions.json` as the default machine-readable audit handoff before any new mart onboarding or ad-hoc refresh work.
## 2026-06-24 09:57:36 ICT — Researched US/BOB stored-procedure orchestration pattern

**Scope lock:**
- Read-only live Fabric/SQL scan plus repo/context review.
- No live SQL DDL/DML, Fabric mutation, or repo architecture change beyond this context note.

**User question:**
- How does US/BOB orchestration likely run when SQL Server Agent is the scheduler?
- Does the flow use final-schema stored procedures that call ETL framework operations against `_Wrk.v_<TableName>` views in ordered groups/waves?

**Evidence checked:**
- Re-read `AGENTS.md` and `00_CONTEXT/current.md`.
- Queried live workspace/warehouse metadata and stored procedure definitions via `az` token + `pyodbc`.
- Cross-checked Microsoft Learn SQL Server Agent docs: T-SQL job steps can call stored procedures; SQL Agent jobs/steps/schedules are managed in `msdb`.
- Scanned:
  - `Enterprise SupplyChain-Dev.SupplyChain_Warehouse`
  - `Enterprise SupplyChain-Dev.ETL_Framework`
  - `EnterpriseData-Dev.SupplyChain_Warehouse`
  - `EnterpriseData-Dev.Retail_Warehouse`
  - `EnterpriseData-Dev.Wholesale_Warehouse`
  - `EnterpriseData-Dev.MasterData_Warehouse`
  - `EnterpriseData-Dev.Quality_Warehouse`
  - corresponding `EnterpriseData` prod warehouses where visible.

**Key findings:**
- [Verified] `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` derives:
  - work table: `<DestinationDatabase>.<DestinationSchema>.<DestinationTable>_LOAD`
  - source view: `<DestinationDatabase>.<DestinationSchema>_Wrk.v_<DestinationTable>`
  - final table: `<DestinationDatabase>.<DestinationSchema>.<DestinationTable>`
- [Verified] `Enterprise SupplyChain-Dev.SupplyChain_Warehouse` legacy `SCP_Core` pattern has physical final tables in `SCP_Core`, matching source views in `SCP_Core_Wrk`, and wrapper procs in `SCP_Core`:
  - `usp_Update_Dimensions`
  - `usp_Update_AFISalesFacts`
  - `usp_Update_FcstAccuracy`
  - `usp_Update_LogilityData`
- [Verified] `SCP_Core.usp_Update_Dimensions` calls `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` for multiple dimension tables in explicit top-down order.
- [Verified] `SCP_Core.usp_Update_FcstAccuracy` calls `ETL_Framework.DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Warehouse','SCP_Core','FactFcstErrorCalc','Append'`.
- [Verified] `EnterpriseData-Dev.Retail_Warehouse.dbo.Usp_Refresh_Retail_Warehouse` and `EnterpriseData-Dev.Wholesale_Warehouse.dbo.Usp_Refresh_Wholesale_Warehouse` are broad wrapper procedures that call many `ETL_Framework.DW_Developer` load procedures in explicit sequence.
- [Verified] Current new Phase 1 warehouses do not yet have equivalent mart/domain wrapper procs:
  - `SupplyChain_Processing_Warehouse`: procs only in `Meta` plus old `Staging_Wrk`; no active domain `usp_Update_*` wrapper found.
  - `SupplyChain_Gold_Warehouse`: no stored procedures found.
  - `ETL_Framework`: generic BOB loader procs exist.

**Interpretation:**
- US/BOB runtime pattern is not strictly "one stored procedure per table".
- It is usually a layered pattern:
  1. final schema physical table;
  2. `_Wrk.v_<TableName>` source/work view;
  3. domain/table-group wrapper stored procedure defining ordered refresh sequence;
  4. generic ETL framework stored procedure executing the load pattern and audit/metadata logging.
- The wrapper procedure order is effectively the procedural wave/order surface when no separate DAG metadata is visible.

**Next concrete step if Aric wants stricter US parity:**
- Generate non-destructive draft SQL wrappers from `03_operations/orchestration/*/manifest.yaml`.
- Proposed target shape:
  - `SupplyChain_Processing_Warehouse.<DomainSchema>.usp_Update_<DomainOrMart>`
  - `SupplyChain_Gold_Warehouse.<DomainSchema>.usp_Update_<DomainOrMart>`
  - optional top-level `dbo.Usp_Refresh_<Mart>` wrapper calling domain wrappers.
- Do not apply live `CREATE/ALTER PROCEDURE` until Aric explicitly approves exact generated DDL.
## 2026-06-24 10:18:29 ICT — Verified BOB wrapper flow against EnterpriseData and SCP_Core

**Scope lock:**
- Read-only Fabric Warehouse metadata/procedure scan.
- No live SQL DDL/DML or Fabric mutation.

**User instruction:**
- Scan `EnterpriseData` and `Enterprise SupplyChain-Dev.SupplyChain_Warehouse` to confirm whether the inferred flow is actually the standard BOB/US pattern.

**Live evidence:**
- `Enterprise SupplyChain-Dev.SupplyChain_Warehouse`:
  - totals: `28` tables, `25` views, `13` procs.
  - `SCP_Core`: `13` physical tables, `0` views, `4` procs.
  - `SCP_Core_Wrk`: `12` views.
  - `SCP_Core` wrapper procs found:
    - `usp_Update_Dimensions`
    - `usp_Update_AFISalesFacts`
    - `usp_Update_FcstAccuracy`
    - `usp_Update_LogilityData`
  - framework call counts in wrappers: `usp_RefreshCuratedTableFromView=9`, `usp_IncrementalTableLoad=1`.
  - examples:
    - `SCP_Core.usp_Update_Dimensions` calls `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` for dimensions in explicit order.
    - `SCP_Core.usp_Update_FcstAccuracy` calls `ETL_Framework.DW_Developer.usp_IncrementalTableLoad 'SupplyChain_Warehouse','SCP_Core','FactFcstErrorCalc','Append'`.
- `EnterpriseData-Dev.Retail_Warehouse`:
  - totals: `220` tables, `42` views, `145` procs.
  - framework calls found: `usp_RefreshCuratedTableFromView=44`, `usp_UpdateTableDictionary_ModifiedDate=94`.
  - examples:
    - `dbo.Usp_Refresh_MasterData_Ent` calls framework loader for `MasterData_Ent` tables.
    - `dbo.Usp_Refresh_MasterData_Product` calls framework loader for `ProductGroup`, `ProductSeries`, `ProductInfo`.
    - `dbo.Usp_Refresh_Retail_Sales` calls framework loader for multiple `Retail_Sales` tables in explicit order.
    - `dbo.Usp_Refresh_Retail_Enh` calls schema-local `Retail_Sales_Enh.usp_Update_*` procs, which then perform custom logic and update TableDictionary.
- `EnterpriseData-Dev.Wholesale_Warehouse`:
  - totals: `209` tables, `126` views, `8` procs.
  - framework calls found: `usp_RefreshCuratedTableFromView=160`, `usp_UpdateTableDictionary_ModifiedDate=2`.
  - examples:
    - `dbo.Usp_Refresh_Wholesale_Warehouse` has `117` ordered EXEC lines calling `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView`.
    - `dbo.Usp_RefreshCustomers`, `dbo.usp_RefreshCustomerOrders_AFI`, and `dbo.usp_RefreshSalesHistory_AFI` call framework loaders by schema/table in explicit order.
- `EnterpriseData-Dev.SupplyChain_Warehouse`:
  - smaller/current dev surface: `1` table, `12` views, `1` proc.
  - `SupplyChain_Enh.usp_Refresh_ContainerPerDiem` updates TableDictionary but does not represent the broader SCP_Core wrapper pattern.
- `EnterpriseData-Dev.ETL_Framework`:
  - `TableDictionary` rows: `832`.
  - framework procs include `usp_RefreshCuratedTableFromView`, `usp_IncrementalTableLoad`, `usp_IncrementalTableLoad_CDC`, `usp_SCD2_TableLoad`, `usp_UpdateCuratedTableFromView_DateRange`, alert/audit/table-dictionary utilities.
- `EnterpriseData` prod visibility check:
  - `ETL_Framework`: `21` tables, `2` views, `0` visible procs, `TableDictionary=1079`.
  - `Retail_Warehouse`: `224` tables, `26` views, `0` visible procs.
  - `Wholesale_Warehouse`: `143` tables, `124` views, `0` visible procs.
  - `SupplyChain_Warehouse`: `20` tables, `3` views, `0` visible procs.
  - Treat prod proc absence as visibility/environment evidence only; do not use it to disprove the dev/US wrapper pattern.

**Confirmed interpretation:**
- [Verified] The BOB/US curated pattern is:
  1. final schema physical tables;
  2. `_Wrk.v_<TableName>` views for source/business SQL;
  3. wrapper stored procedures as ordered orchestration entrypoints;
  4. `ETL_Framework.DW_Developer` generic loaders for load pattern, audit, and TableDictionary updates.
- [Verified] Some EnterpriseData domains mix this with schema-local `usp_Update_*` custom procs. The broad standard is wrapper proc order plus framework calls, not necessarily one procedure per table.
- [Verified] The new Phase 1 warehouses are aligned on final table + `_Wrk` view + framework metadata, but still lack US-style wrapper procedure entrypoints.
## 2026-06-24 10:26:07 ICT — Clarified dependency/order control for future wrapper SPs

**Scope lock:**
- Repo/context review only; no live SQL/Fabric mutation.

**User question:**
- If SQL Agent / wrapper stored procedures are used for execution, how should dependency order be controlled, especially for Silver waves and Gold dependencies?

**Current repo state checked:**
- `03_operations/orchestration/main/manifest.yaml` has project-level order:
  - shared -> forecast_accuracy -> inventory_health -> smoke.
- Mart-level `manifest.yaml` files currently declare pipeline/project metadata and BOB `_Wrk` contract, but do not carry the full table-level sequence.
- Generated operating packages currently hold table-level order:
  - `02_marts/forecast_accuracy/05_catalog/run_order.json`
  - `02_marts/inventory_health/05_catalog/run_order.json`
  - `03_operations/operating_registry/run_order.json`

**Interpretation:**
- Ordered `EXEC` lines inside wrapper SPs are valid as an execution artifact, but should not become the only source of truth.
- Safer target pattern:
  1. maintain mart run DAG/order in metadata (`manifest.yaml`/run registry);
  2. validate the DAG by SQL dependency scan and topological sorting;
  3. generate wrapper stored procedures from metadata;
  4. deploy wrapper SPs only after dry-run/review;
  5. SQL Agent calls only the stable top-level wrapper entrypoint.

**Design implication:**
- Do not require one SP per table as the primary model.
- Recommended hierarchy:
  - table-level load step in metadata;
  - generated schema/wave wrapper procs;
  - generated mart wrapper proc;
  - optional all-mart wrapper proc.
- This preserves BOB compatibility while keeping dependency order machine-checkable.
## 2026-06-24 10:36:41 ICT — Forecast Accuracy wrapper-flow example researched

**Scope lock:**
- Read-only repo + live `ETL_Framework.TableDictionary` query.
- No live SQL DDL/DML or Fabric mutation.

**User question:**
- What would the Forecast Accuracy flow look like top-down if converted to BOB/US wrapper stored procedures, and would each step call the framework loader and update `TableDictionary`/audit?

**Evidence checked:**
- `02_marts/forecast_accuracy/05_catalog/run_order.json` has `13` ordered steps:
  - shared `DimCalendar`, `DimProduct`, `DimWarehouse`
  - wave `0`: `ReferenceMaster_Enh.*`
  - wave `1`: `SalesHistory_Enh.InvoiceDetailLineLevel`, `OpenOrderHistory_Enh.OpenOrderLineLevel`
  - wave `2`: `SalesHistory_Enh.ActualDemandMonthly`, `ForecastHistory_Enh.ForecastDemandMonthly`
  - `gold_dim`: `ForecastAccuracy_DW.DimCustomerGrouping`, `ForecastAccuracy_DW.DimForecastHorizon`
  - `gold_fact`: `ForecastAccuracy_DW.FactForecastActual`, `ForecastAccuracy_DW.FactForecastKpi`
  - `smoke`: semantic/row-count/freshness checks
- Live `ETL_Framework.DW_Developer.TableDictionary` lookup:
  - forecast/shared/gold objects checked are present.
  - `UpdateMethod=overwrite` for the forecast objects checked.
  - `ReferenceMaster_Enh` has `11` table rows; all checked rows use `UpdateMethod=overwrite`.

**Interpretation:**
- Forecast wrapper procs can call `ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` for the current overwrite objects.
- Framework will resolve `<Schema>_Wrk.v_<Table>` from schema/table, load `<Schema>.<Table>`, write `AuditLog`, and update table metadata/modified status through the framework proc path.
- Smoke/semantic validation remains outside the loader and should be a post-run validation step, not a curated-table load step.
## 2026-06-24 10:48:42 ICT — Checked whether `ETL_Framework.Orchestration` exists elsewhere

**Scope lock:**
- Read-only metadata scan of `ETL_Framework` warehouses.
- No live SQL DDL/DML or Fabric mutation.

**User concern:**
- Whether adding an `Orchestration` schema inside `ETL_Framework` is already a US/BOB pattern, or would be an unsupported custom addition.

**Evidence checked:**
- `Enterprise SupplyChain-Dev.ETL_Framework`:
  - active object schemas: `DW_Developer`, `queryinsights`, `sys`.
  - procedures: `10`, all in `DW_Developer`.
  - no `Orchestration` schema found.
- `EnterpriseData-Dev.ETL_Framework`:
  - active object schemas include `DW_Developer`, `Performance_Logs`, some data schemas, `queryinsights`, `sys`.
  - procedures: `35`, mostly `DW_Developer`, one `Performance_Logs`.
  - no `Orchestration` schema found.
- `EnterpriseData.ETL_Framework` prod:
  - visible object schemas include `DW_Developer`, `Performance_Logs`, `ProductKnowledge`, `sys`.
  - visible procedures: `0`.
  - no `Orchestration` schema found.

**Decision implication:**
- Do not add `ETL_Framework.Orchestration` as the default BOB-aligned design without explicit approval.
- Safer parity pattern is to keep `ETL_Framework.DW_Developer` as pure generic loader framework, and place wrapper/orchestration procedures in the target/domain warehouses (`dbo` and/or relevant business schema), matching `SCP_Core`, Retail, and Wholesale evidence.
## 2026-06-24 11:18:00 ICT — BOB-style wrapper stored procedures applied for all active marts

**Scope lock:**
- Live Fabric SQL mutation already executed before context cleanup; no full curated refresh/proc execution was run in this checkpoint.
- Business Bronze/Silver/Gold object surface preserved; operational wrapper layer added around existing BOB loader procedures.

**User instruction:**
- Apply the US/BOB stored-procedure orchestration pattern to all active marts, not just Forecast Accuracy.
- Audit ETL framework log/metadata tables afterward for stale object names.

**BOB/US pattern verified:**
- Wrapper procedures are schema-local/top-level operational entrypoints in target warehouses, commonly `dbo.Usp_Refresh_*` or schema-local `usp_Update_*`.
- No separate `ETL_Framework.Orchestration` schema was found in scanned EnterpriseData / SCP_Core patterns.
- Target standard for this repo: keep `ETL_Framework.DW_Developer` as pure loader framework; keep mart wrapper procedures in `dbo` of the relevant Processing/Gold warehouse.

**Live wrapper procedures applied:**
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared`
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster`
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`

**Wrapper flow contract:**
- SQL Agent / external scheduler should run cross-warehouse order explicitly:
  1. `EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared;`
  2. `EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster;`
  3. `EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver;`
  4. `EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold;`
  5. `EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver;`
  6. `EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold;`
  7. run smoke/DQ/semantic checks.
- Inside each wrapper, table calls are sequential and follow current manifest/wave order.

**ETL framework metadata update:**
- Updated `ETL_Framework.DW_Developer.TableDictionary` for `41` wrapper-managed objects.
- `ReplicatedSource` now maps to canonical `_Wrk.v_<TableName>` for each final table.
- `UpdateQuery` maps to `[DW_Developer].[usp_RefreshCuratedTableFromView]` for overwrite objects and `[DW_Developer].[usp_IncrementalTableLoad]` for the two incremental Inventory snapshots.
- `JobName`/`JobServer` were not fabricated because the real US SQL Agent job/server names are not known yet.

**Audit evidence captured:**
- Processing table/view/top0 audit: `28` objects, `0` failures.
- Gold table/view/top0 audit: `13` objects, `0` failures.
- `TableDictionary` mismatch audit: `0` mismatches.
- Stale active-name audit for `PurchaseOrderSnapshotDaily`, `InventorySnapshotWeeklyFactBase`, `LastInvoiceHelper`, `MovementFlagHelper`, `CogsRollingHelper`, `FactInventoryRiskForward`: `0` rows in current `TableDictionary`, `0` recent rows in `AuditLog`, `0` recent rows in `TableDictionary_UpdateLog` since `2026-06-23`.

**Repo updates:**
- Added wrapper SQL files under `03_operations/orchestration/*/sql/`.
- Added `wrapper_procedures` metadata to `forecast_accuracy`, `inventory_health`, and `main` orchestration manifests.
- Updated Inventory Health manifest to current live object names: `PurchaseOrderSnapshotHistorical`, `LastInvoiceWeekly`, `Cogs52WWeekly`, `ProjectedInventoryHealthSubStatus`, `FactInventoryHealthFutureWeekEnding`, etc.
- Regenerated operating package: `mart_count=2`, `dq_source_count=42`, `forecast run_step_count=13`, `inventory run_step_count=24`.

**Verification:**
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed after manifest updates.
- Active generated package JSON parse passed except two pre-existing empty semantic artifact response files under `01_docs/runbook/artifacts/2026-06-15_sc_control_tower/`, unrelated to orchestration/DQ/catalog.
- Active grep found no stale Inventory object names in `03_operations/orchestration`, `03_operations/operating_registry`, `02_marts/*/05_catalog`, or `02_marts/*/04_dq`.

**Next step:**
- When ready to validate runtime behavior, execute wrapper procedures in the SQL Agent order above or dry-run/ad-hoc equivalent. Do not trigger a full curated refresh unless Aric explicitly asks.
## 2026-06-24 11:31:00 ICT — Normalized context chunks after wrapper work

**Scope lock:**
- Repo context cleanup only; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Stop further live work for now; log and organize context files in the right order because the handoff history looked messy.

**Actions executed:**
- Preserved pre-cleanup active context at `00_CONTEXT/_source/current_before_reorder_20260624.md`.
- Recovered missing `2026-06-23` entries from the old active `current.md` into `00_CONTEXT/2026-06-21_to_2026-06-23.md` under a clearly labeled recovered section.
- Created/updated `00_CONTEXT/2026-06-24_to_2026-06-24.md` as the clean day-specific active chunk.
- Rewrote `00_CONTEXT/current.md` to mirror only the `2026-06-24` chunk.
- Updated `00_CONTEXT/README.md` chunk index.

**Next step:**
- Resume from wrapper orchestration checkpoint; use wave order from `03_operations/orchestration/*/manifest.yaml` and wrapper procedures from `03_operations/orchestration/*/sql/`.

## 2026-06-24 12:14:32 ICT — Surfaced wrapper procedure order in runner + docs

**Scope lock:**
- Repo-only docs/tooling alignment; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- Read `AGENTS.md` + scan repo + resume from latest `00_CONTEXT` checkpoint.

**Actions executed:**
- Updated `03_operations/tools/run_refresh.py` to print `wrapper_procedures` (database context + `EXEC [schema].[procedure]`).
- Added `wrapper_procedures` to `03_operations/orchestration/main/manifest.yaml` and `03_operations/orchestration/main/manifest.json` so the full SQL Agent order is machine-readable.
- Updated docs:
  - `03_operations/README.md`
  - `03_operations/orchestration/*/README.md`

**Verification:**
- `python3 -m py_compile 03_operations/tools/run_refresh.py` passed.
- Dry-run prints show wrapper procedure order for:
  - `03_operations/orchestration/main/manifest.json`
  - `03_operations/orchestration/forecast_accuracy/manifest.json`
  - `03_operations/orchestration/inventory_health/manifest.json`

**Repo state note:**
- Local `main` is behind `origin/main` by `1` commit (`1e82342c`), and `git status` is still large due to the ongoing repo restructure checkpoint.

**Next step:**
- If we want a runtime validation checkpoint, decide whether to:
  1) execute wrapper procedures (live), or
  2) smoke-test the parameterized `pl_sc_mart(project_name)` REST trigger first.
- Live execution requires explicit approval.

## 2026-06-24 12:58:41 ICT — Re-aligned orchestration manifests to wave-first (Silver -> Gold)

**Scope lock:**
- Repo-only manifest/docs/package alignment; no live Fabric/Power BI/SQL mutation.

**User instruction:**
- “Lấy đúng thứ tự wave: Silver wave 0,1,2… rồi mới tới Gold; scan lại cái nào trước/sau và apply setup.”

**Actions executed:**
- Updated mart orchestration manifests to be wave-first:
  - `03_operations/orchestration/forecast_accuracy/manifest.json`
  - `03_operations/orchestration/inventory_health/manifest.json`
  - moved shared dims into `wave=gold_shared` and placed after Silver waves.
- Added missing Silver prerequisite into Inventory flow:
  - `ReferenceMaster_Enh.*` added as `wave=0` in Inventory manifest sequence (required by multiple Inventory Silver views).
- Re-ordered SQL wrapper procedure order to match wave model:
  - `03_operations/orchestration/main/manifest.json`
  - `03_operations/orchestration/*/manifest.json`
- Made YAML manifests mirror JSON sequences for both marts:
  - `03_operations/orchestration/forecast_accuracy/manifest.yaml`
  - `03_operations/orchestration/inventory_health/manifest.yaml`
- Updated orchestration READMEs to describe “Silver waves then Gold waves”:
  - `03_operations/orchestration/*/README.md`
- Regenerated operating packages (DQ/catalog/run-order) from updated manifests:
  - `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .`

**Verification:**
- Dry-run printer shows wave-first ordering:
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/forecast_accuracy/manifest.json`
  - `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/inventory_health/manifest.json`
- Generated run-order registry updated accordingly:
  - `02_marts/*/05_catalog/run_order.json`
  - `03_operations/operating_registry/run_order.json`

**Next step:**
- If Aric wants a runtime validation checkpoint, choose:
  1) wrapper SP execution (SQL Agent surface), or
  2) `pl_sc_mart(project_name)` REST smoke-test.
- Live execution requires explicit approval.

## 2026-06-24 14:40:00 ICT — BOB wrapper runtime validation completed and mart-local wrapper contract finalized

**Scope lock:**
- Live Fabric SQL wrapper execution + repo orchestration metadata cleanup.
- No business SQL/view/table contract redesign.
- No destructive operations.

**User instruction:**
- Continue and finish the apply/run.
- Keep only the two active marts in the operational mental model.
- Silver and Gold wrappers must show the correct wave/table order; shared/reference dependencies should not look like a third mart.

**Live execution completed:**
- Ran SQL wrapper refresh path against `Enterprise SupplyChain-Dev` in order:
  1. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared`
  2. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster`
  3. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  4. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  5. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  6. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
- Result: `6/6` wrapper steps completed, `0` wrapper failures.
- Runtime:
  - Shared: `25.34s`
  - ReferenceMaster: `46.87s`
  - Forecast Silver: `332.02s`
  - Forecast Gold: `88.78s`
  - Inventory Silver: `1133.11s`
  - Inventory Gold: `438.12s`

**Post-run audit:**
- Processing warehouse compile check: `28` objects, `56` table/view `SELECT TOP 0` checks, `0` failures.
- Gold warehouse compile check: `13` objects, `26` table/view `SELECT TOP 0` checks, `0` failures.
- `ETL_Framework.DW_Developer.TableDictionary` wrapper scope: `41` rows, `41` `_Wrk.v_*` refs, `39` overwrite loader refs, `2` incremental loader refs.
- Stale active Inventory names are absent from `TableDictionary`:
  - `PurchaseOrderSnapshotDaily`
  - `InventorySnapshotWeeklyFactBase`
  - `LastInvoiceHelper`
  - `MovementFlagHelper`
  - `CogsRollingHelper`
  - `FactInventoryRiskForward`
- Recent non-succeeded query history contained one earlier canceled diagnostic/select-style Inventory query, not a wrapper step failure.

**Final wrapper contract after user correction:**
- Active operational surface is two marts only:
  - `forecast_accuracy`
  - `inventory_health`
- Each mart has exactly two active wrapper procedures:
  - `Usp_Refresh_<Mart>_Silver`
  - `Usp_Refresh_<Mart>_Gold`
- Mart Silver wrappers are self-contained and include `ReferenceMaster_Enh` prerequisite Wave 00.
- Mart Gold wrappers are self-contained and include `Shared_DW` prerequisite Wave 00.
- Shared/reference helper procedures may remain available, but they are not modeled as a third active mart.

**Live wrapper definitions redeployed after runtime validation:**
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  - `15` refresh calls, `0` incremental calls, `11` ReferenceMaster calls.
- `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  - `23` refresh calls, `2` incremental calls, `11` ReferenceMaster calls.
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  - `7` refresh calls, `3` Shared_DW calls.
- `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
  - `9` refresh calls, `3` Shared_DW calls.

**Repo updates:**
- Updated mart SQL wrapper files under:
  - `03_operations/orchestration/forecast_accuracy/sql/`
  - `03_operations/orchestration/inventory_health/sql/`
- Updated wrapper procedure lists in:
  - `03_operations/orchestration/main/manifest.json`
  - `03_operations/orchestration/main/manifest.yaml`
  - `03_operations/orchestration/forecast_accuracy/manifest.json`
  - `03_operations/orchestration/forecast_accuracy/manifest.yaml`
  - `03_operations/orchestration/inventory_health/manifest.json`
  - `03_operations/orchestration/inventory_health/manifest.yaml`
- Updated orchestration READMEs so `main` means all-mart runner, not a `shared` project.
- Regenerated operating package:
  - `mart_count=2`
  - `dq_source_count=42`
  - `forecast_accuracy.run_step_count=13`
  - `inventory_health.run_step_count=25`

**Verification:**
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed.
- JSON parse passed for active orchestration manifests and operating registry.
- `python3 -m py_compile` passed for operating package and DQ tools.

**Next step:**
- Treat the wrapper procedure model as the current SQL Agent handoff:
  - all-mart: `Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold`
  - single mart: run that mart's Silver wrapper, then Gold wrapper.

## 2026-06-24 14:58:00 ICT — Removed shared/reference helper wrapper procs from active operating surface

**Scope lock:**
- Live Fabric SQL cleanup + repo operating docs cleanup.
- Destructive operation explicitly approved by Aric in this conversation: clean up the lingering `ReferenceMaster` and `Shared` helper wrapper procs so only the two mart surfaces remain.

**Live changes:**
- Dropped helper procedures:
  - `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster`
  - `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared`
- Live verification now shows only:
  - Processing `dbo`: `Usp_Refresh_ForecastAccuracy_Silver`, `Usp_Refresh_InventoryHealth_Silver`
  - Gold `dbo`: `Usp_Refresh_ForecastAccuracy_Gold`, `Usp_Refresh_InventoryHealth_Gold`

**Repo changes:**
- Removed helper SQL files:
  - `03_operations/orchestration/main/sql/SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_SupplyChain_ReferenceMaster.sql`
  - `03_operations/orchestration/main/sql/SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_SupplyChain_Shared.sql`
- Removed now-empty `03_operations/orchestration/main/sql/` folder.
- Updated active operation docs/rules:
  - `AGENTS.md`
  - `README.md`
  - `03_operations/orchestration/main/README.md`
- Regenerated operating package after cleanup.

**Verification:**
- Active grep across `AGENTS.md`, `README.md`, `03_operations/orchestration`, `03_operations/operating_registry`, and mart catalogs found no stale `Usp_Refresh_SupplyChain_ReferenceMaster`, `Usp_Refresh_SupplyChain_Shared`, `project: shared`, or `shared/reference first`.
- `python3 05_tools/04_operating_package/build_operating_package.py --repo-root .` passed.
- `python3 -m py_compile 05_tools/04_operating_package/build_operating_package.py 03_operations/tools/run_refresh.py` passed.
- `python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json` now prints exactly four wrapper procs:
  1. `Usp_Refresh_ForecastAccuracy_Silver`
  2. `Usp_Refresh_ForecastAccuracy_Gold`
  3. `Usp_Refresh_InventoryHealth_Silver`
  4. `Usp_Refresh_InventoryHealth_Gold`

**Current handoff:**
- SQL Agent all-mart flow is now exactly four steps:
  - Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold.
- Shared/reference dependencies exist only as Wave 00 calls inside the mart wrappers.

## 2026-06-24 15:43:30 ICT — Full 4-wrapper BOB runtime rerun passed after DA live-code sync

**Scope lock:**
- Live Fabric SQL runtime validation and full all-mart refresh.
- No business layer redesign.
- Follow DA's latest live SQL contract where they reduced/changed columns.

**Preflight findings/fixes before run:**
- Initial strict preflight blocked the run because live Fabric differed from local for:
  - `SupplyChain_Processing_Warehouse.InventoryHistory_Enh_Wrk.v_AwdHelper`
  - `SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimProduct`
  - `SupplyChain_Gold_Warehouse.Shared_DW_Wrk.v_DimWarehouse`
- Aric confirmed DA intentionally changed these live definitions, so local repo SQL was synced to the live Fabric definitions.
- `ETL_Framework.DW_Developer.TableDictionary` active rows were cleaned:
  - 4 stale `ReplicatedSource` refs changed from old `*_ENH.vw_*` names to `_Wrk.v_*`
  - 8 stale active `ErrorMsg` values cleared after verifying current `_Wrk` contracts.

**Preflight verification after cleanup:**
- Live/local SQL modules matched: `49/49`.
- Missing live modules: `0`.
- Live/local drift: `0`.
- Active wrapper proc surface:
  - Processing `dbo`: `Usp_Refresh_ForecastAccuracy_Silver`, `Usp_Refresh_InventoryHealth_Silver`
  - Gold `dbo`: `Usp_Refresh_ForecastAccuracy_Gold`, `Usp_Refresh_InventoryHealth_Gold`
- Active `TableDictionary` curated rows: `46`.
- Active `TableDictionary` `_Wrk.v_*` refs: `46/46`.
- Active `TableDictionary` error rows: `0`.
- Compile check: `92/92` table/view `SELECT TOP 0` checks passed.

**Full flow executed in SQL-Agent-equivalent order:**
1. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver` — succeeded, `382.81s`.
2. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold` — succeeded, `94.07s`.
3. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver` — succeeded, `804.16s`.
4. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold` — succeeded, `439.97s`.

**Post-run verification:**
- Full flow result: `4/4` succeeded.
- Post-run live/local SQL modules: `49/49` matched, no missing, no drift.
- Post-run compile: `92/92` passed.
- Post-run active `TableDictionary`: `46` rows, `46` `_Wrk.v_*` refs, `0` error rows, `43` refresh loader refs, `3` incremental loader refs.
- `AuditLog` since run start: `56` `Process Start` + `56` `Process Complete`, `0` error rows.
- `queryinsights` since run start: no non-success entries.
- Semantic model read-only smoke: `sc_control_tower` (`f06a2361-15fd-4f91-9d37-941fefe62aaf`) exists in `Enterprise SupplyChain-Dev`; description remains Direct Lake on `SupplyChain_Gold_Warehouse`.
- Representative post-run direct rowcounts:
  - `ForecastHistory_Enh.ForecastDemandMonthly`: `156,160,392`
  - `SalesHistory_Enh.InvoiceDetailLineLevel`: `288,031,871`
  - `InventoryHistory_Enh.AwdHelper`: `2,409,242`
  - `InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit`: `30,166,450`
  - `Shared_DW.DimProduct`: `780,848`
  - `InventoryHealth_DW.FactInventoryHealthSnapshot`: `3,220,912`
  - `ForecastAccuracy_DW.FactForecastKpi`: `122,773,185`

**Current handoff:**
- The BOB-aligned runtime is validated for the two active marts.
- Final run order remains:
  - Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold.
- Shared/reference dependencies remain embedded inside mart wrappers as Wave 00.

## 2026-06-24 20:34:30 ICT — Final closeout audit passed and repo docs updated

**Scope lock:**
- Final read-only live Fabric/SQL audit + repo documentation updates.
- No live data mutation.
- No business SQL redesign.

**User instruction:**
- Audit one last time, confirm whether data + operations are complete, then update repo/docs/README carefully.

**Final live audit result:**
- Overall: `final_pass=true`.
- Wrapper proc surface:
  - `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  - `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  - `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  - `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
- Live/local SQL modules: `49/49` matched, `0` missing, `0` drift.
- Active `TableDictionary`: `46` curated rows, `46` `_Wrk.v_*` refs, `0` active bad/error rows.
- Compile smoke: `92/92` active target/source checks, `0` failures.
- `AuditLog` since full run start: `56 Process Start`, `56 Process Complete`, `0` errors; `56` paired object durations.
- `queryinsights`: `0` non-success entries since full run start.
- Semantic smoke: `sc_control_tower` exists and remains Direct Lake on `SupplyChain_Gold_Warehouse`.

**Slowest object durations from AuditLog:**
- `ForecastHistory_Enh.ForecastDemandMonthly`: `225s`
- `InventoryHealth_DW.ProjectedInventoryHealthSubStatus`: `209s`
- `InventoryHistory_Enh.SupplyPlanDetail`: `163s`
- `InventoryHistory_Enh.LastInvoiceWeekly`: `84s`
- `InventoryHistory_Enh.ItemBalanceHistorical_WithInTransit`: `83s`

**Docs updated:**
- `README.md`
  - added final runtime closeout table
  - added SQL Agent 4-step handoff
  - added BOB view-to-table mapping contract
  - added wave detail for all four wrapper procs
  - added AuditLog duration query
- `03_operations/orchestration/main/README.md`
  - added current status and SQL Agent handoff
  - added monitoring query and `TableDictionary` usage notes
- `01_docs/README.md`
  - added current verified operating state and handoff pointers
- `01_docs/architecture/current/README.md`
  - added 2026-06-24 full wrapper validation status
- `01_docs/architecture/current/final_bob_runtime_architecture.md`
  - updated final runtime architecture, mart map, execution order, and Phase 1 evidence
- `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
  - added 2026-06-24 closeout block
  - converted Phase 1 acceptance checklist from `[Need-verify]` to verified/deferred status based on final audit

**Current handoff:**
- Phase 1 runtime is operationally complete and validated.
- DE orchestration should call only the four wrapper procedures in this order:
  1. Forecast Accuracy Silver
  2. Forecast Accuracy Gold
  3. Inventory Health Silver
  4. Inventory Health Gold
- Phase 2 remains deferred.

## 2026-06-24 20:47:00 ICT — Final repo/doc verification after closeout edits

**Scope lock:**
- Repo docs/readme cleanup only.
- No live Fabric/SQL mutation.

**Actions/evidence:**
- Clarified `01_docs/Enterprise_Framework_Migration_Master_Plan.md` so 2026-06-21/2026-06-22 baseline notes are explicitly historical and superseded by the 2026-06-24 closeout.
- Clarified `01_docs/architecture/current/final_bob_runtime_architecture.md` mart map wording from `Current hub` to `Current folder`.
- Markdown fence sanity passed for `README.md`, `03_operations/orchestration/main/README.md`, `01_docs/README.md`, `01_docs/architecture/current/README.md`, `01_docs/architecture/current/final_bob_runtime_architecture.md`, `01_docs/Enterprise_Framework_Migration_Master_Plan.md`, and `00_CONTEXT/current.md`.
- Python compile verification passed for current operation tools under `03_operations/tools/` and `05_tools/`.
- Stale proc grep found only historical entries in context and baseline history, not active handoff docs.

**Current handoff:**
- Final user-facing docs/readme are aligned with the 4-wrapper BOB runtime closeout.

## 2026-06-24 21:12:00 ICT — ADR-010 persisted and SQLPROJ/CI-CD research started

**Scope lock:**
- Documentation/research only.
- No `.sqlproj` created.
- No CI/CD workflow created.
- No live Fabric/SQL mutation.

**User instruction:**
- Persist the Phase 1 closeout/runtime handoff decision into docs/context, then research Bob's `sqlproj` docs and CI/CD model.

**Actions/evidence:**
- Added `01_docs/decisions/ADR-010-bob-wrapper-runtime-handoff.md`.
- Added `01_docs/runbook/guides/sqlproj_cicd_research.md`.
- Updated `README.md`, `01_docs/README.md`, and `01_docs/bob-framework/README.md` with links to ADR-010 and the SQLPROJ/CI-CD research guide.
- Reviewed Bob docs:
  - `01_docs/bob-framework/source/SQLPROJ_BEST_PRACTICES.md`
  - `01_docs/bob-framework/source/FABRIC_ARCHITECTURE_AND_STANDARDS.md`
  - `99_archive/reverse-engineering/enterprise_data_architect/30_runbook/02_domain_team_workflow.md`
- Reviewed Microsoft Learn official docs:
  - Fabric Warehouse projects in VS Code
  - SQL projects automation
  - target platform overview

**Current finding:**
- `.sqlproj` / `.dacpac` should own schema/object deployment, not daily refresh execution.
- Daily refresh execution remains SQL Agent calling the four Phase 1 wrapper procedures.
- Bob guide version note `Microsoft.Build.Sql 0.1.12-preview` conflicts with current Microsoft Fabric docs examples using `Microsoft.Build.Sql 2.0.0` plus `Microsoft.SqlServer.Dacpacs.FabricDw 170.0.2`; package versions must be verified against EnterpriseData actual repo or NuGet before implementation.
- Recommended next path is local build-only `.sqlproj` packaging first, not automated publish.

## 2026-06-24 21:46:48 ICT — Implemented build-only SQLPROJ package and docs cleanup

**Scope lock:**
- Repo/local files only.
- Read-only live SQL metadata was used by the generator.
- No `SqlPackage /Action:Publish`, no CI/CD workflow, no live Fabric/SQL mutation, no destructive cleanup.

**User instruction:**
- Proceed with the SQLPROJ handoff work, write full docs, and clean the repo structure as much as safely possible.

**Actions/evidence:**
- Added build-only SQLPROJ generator:
  - `05_tools/05_sqlproj/build_sqlproj_package.py`
  - `05_tools/05_sqlproj/README.md`
- Generated package:
  - `03_operations/deployment/sqlproj/ETL_Framework/`
  - `03_operations/deployment/sqlproj/Enterprise_Lakehouse_Reference/`
  - `03_operations/deployment/sqlproj/SupplyChain_Processing_Warehouse/`
  - `03_operations/deployment/sqlproj/SupplyChain_Gold_Warehouse/`
- Added SQLPROJ implementation plan:
  - `01_docs/plans/2026-06-24-sqlproj-build-only-package.md`
- Updated docs:
  - `README.md`
  - `03_operations/README.md`
  - `03_operations/deployment/sqlproj/README.md`
  - `01_docs/runbook/guides/sqlproj_cicd_research.md`
  - `05_tools/05_sqlproj/README.md`
- Added generated package evidence:
  - `03_operations/deployment/sqlproj/package_summary.json`
  - `03_operations/deployment/sqlproj/_package/build_summary.json`
  - `03_operations/deployment/sqlproj/_package/build_logs/*.log`
- Added `.gitignore` coverage for SQL project `bin/` and `obj/` local outputs.

**Build verification:**
- `python3 -m py_compile 05_tools/05_sqlproj/build_sqlproj_package.py` passed.
- `dotnet build` passed for all four generated projects:
  - `ETL_Framework`: 0 warnings, 0 errors
  - `Enterprise_Lakehouse_Reference`: 0 warnings, 0 errors
  - `SupplyChain_Processing_Warehouse`: 0 warnings, 0 errors
  - `SupplyChain_Gold_Warehouse`: 0 warnings, 0 errors

**Current handoff:**
- Repo now has a BOB-compatible build-only `.sqlproj`/`.dacpac` handoff package.
- The package is safe for local validation and US/BOB review.
- It must not be used for live publish until deployment ownership, publish profiles, service connection, and destructive-change gates are explicitly approved.

## 2026-06-24 22:29:38 ICT — Added DA-facing SQLPROJ CI/CD operating guide

**Scope lock:**
- Documentation only.
- No live Fabric/SQL mutation.
- No CI/CD publish workflow created.

**User instruction:**
- Write a detailed, easy-to-understand guide for SQLPROJ CI/CD with definitions, data-specific CI/CD terms, real operating logic, and a practical example.

**Actions/evidence:**
- Added `01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md`.
- Linked the guide from:
  - `README.md`
  - `01_docs/README.md`
  - `01_docs/runbook/guides/sqlproj_cicd_research.md`
  - `03_operations/deployment/sqlproj/README.md`
- Guide covers:
  - CI, CD, CI/CD, branch, commit, PR, merge
  - build, compile, `.sqlproj`, `.dacpac`, artifact, DacFx, SqlPackage
  - DeployReport, deploy script, publish, environment, gate/approval
  - data-loss guard, smoke test, wrapper procedure, `_Wrk` view, final table
  - `AuditLog`, `TableDictionary`, semantic smoke
  - practical `ForecastBiasPct` / `FactForecastKpi` end-to-end example
  - distinction between SQL object deployment and BOB ETL runtime execution

**Verification:**
- Markdown fence sanity passed for the new guide and linked docs.
- Grep confirmed the new guide is discoverable from main SQLPROJ and docs entrypoints.

## 2026-06-24 22:40:40 ICT — Rebuilt root README as the single operating entrypoint

**Scope lock:**
- Repo documentation and local verification only.
- No live Fabric/SQL mutation.
- No destructive cleanup.

**User instruction:**
- Make the root `README.md` the single polished master index for repo knowledge, architecture, operations, CI/CD, and current BOB runtime.
- Add generated Mermaid/SVG diagrams for the current operating flow.
- Keep the README useful as a template-style handoff while still documenting the current wrapper contract.
- Keep the repo lean without unsafe deletion.

**Actions executed:**
- Rebuilt root `README.md` as the main repo handbook and link hub.
- Added and linked generated diagram sources/assets:
  - `01_docs/architecture/current/readme_operating_map.mmd`
  - `01_docs/architecture/current/readme_operating_map.svg`
  - `01_docs/architecture/current/readme_cicd_to_runtime_flow.mmd`
  - `01_docs/architecture/current/readme_cicd_to_runtime_flow.svg`
  - `01_docs/architecture/current/readme_bob_loader_contract.mmd`
  - `01_docs/architecture/current/readme_bob_loader_contract.svg`
- Updated `01_docs/architecture/current/README.md` to index the new root README support diagrams.
- Root README now links the current docs system:
  - context, architecture, master plan, BOB guide, mart packages, operations, SQLPROJ CI/CD, semantic, tools, and archive.
- Root README now documents the template CI/CD-to-runtime flow:
  - PR/commit -> `.sqlproj` build -> `.dacpac` -> DeployReport/Script -> approval -> publish -> scheduler/wrapper -> BOB loader -> `_Wrk` view -> final table -> AuditLog/TableDictionary/DQ/semantic smoke.
- Root README keeps the current operational wrapper handoff:
  - Forecast Accuracy Silver
  - Forecast Accuracy Gold
  - Inventory Health Silver
  - Inventory Health Gold

**Verification:**
- Markdown fence sanity passed:
  - `README.md`
  - `01_docs/architecture/current/README.md`
  - `00_CONTEXT/current.md`
- Root README local link check passed:
  - `50` local links checked
  - `0` missing links
- Mermaid render verification passed for all three root README support diagrams using `mmdc`.
- Diagram asset existence check passed:
  - `readme_operating_map.svg`: `31620` bytes
  - `readme_cicd_to_runtime_flow.svg`: `31089` bytes
  - `readme_bob_loader_contract.svg`: `23502` bytes
- SQLPROJ build verification passed via `03_operations/deployment/sqlproj/build_all.sh`:
  - `ETL_Framework`: `0` warnings, `0` errors
  - `Enterprise_Lakehouse_Reference`: `0` warnings, `0` errors
  - `SupplyChain_Processing_Warehouse`: `0` warnings, `0` errors
  - `SupplyChain_Gold_Warehouse`: `0` warnings, `0` errors

**Lean cleanup note:**
- Active top-level repo surface remains numbered and compact:
  - `00_CONTEXT`, `01_docs`, `02_marts`, `03_operations`, `04_semantic`, `05_tools`, `99_archive`.
- Physical generated/cache folders found but not deleted because deletion needs explicit approval:
  - SQLPROJ `bin/` and `obj/`
  - Python `__pycache__/`
- These are already covered by `.gitignore`, so they should not pollute commits.

**Current handoff:**
- Use root `README.md` as the only start page for repo onboarding and operations.
- Use `01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md` for full CI/CD definitions and operating explanation.
- Use `03_operations/orchestration/main/manifest.json` and wrapper procedures for runtime handoff.

## 2026-06-24 23:08:31 ICT — Converted root README into visual template handbook and added role onboarding

**Scope lock:**
- Repo documentation and local verification only.
- No live Fabric/SQL mutation.
- No destructive cleanup.

**User instruction:**
- Remove report-style closeout metrics from the root README because it should be a reusable knowledge/setup guide, not an evidence report.
- Make README more visual and easier for DA/DE readers.
- Add step-by-step onboarding guides for DA and DE.
- Show architecture, repo structure, CI/CD, runtime, and combined CI/CD-to-runtime workflow with diagrams.

**Actions executed:**
- Rewrote root `README.md` as a visual template handbook.
  - Metrics and one-time run numbers now point to context/artifacts instead of being embedded in the root guide.
  - README now emphasizes role navigation, architecture, mart package anatomy, BOB loader contract, CI/CD workflow, ETL runtime workflow, full lifecycle, DA onboarding, DE onboarding, DQ/catalog, source-of-truth order, and safety.
- Added onboarding hub:
  - `01_docs/onboarding/README.md`
  - `01_docs/onboarding/da_onboarding.md`
  - `01_docs/onboarding/de_onboarding.md`
- Added new Mermaid/SVG diagrams:
  - `01_docs/architecture/current/readme_mart_package_anatomy.mmd`
  - `01_docs/architecture/current/readme_mart_package_anatomy.svg`
  - `01_docs/architecture/current/readme_full_lifecycle.mmd`
  - `01_docs/architecture/current/readme_full_lifecycle.svg`
  - `01_docs/onboarding/da_onboarding_flow.mmd`
  - `01_docs/onboarding/da_onboarding_flow.svg`
  - `01_docs/onboarding/de_operating_cycle.mmd`
  - `01_docs/onboarding/de_operating_cycle.svg`
- Updated doc indexes:
  - `01_docs/README.md`
  - `01_docs/architecture/current/README.md`
  - `02_marts/README.md`
  - `03_operations/README.md`

**Verification:**
- Markdown fence sanity passed for:
  - `README.md`
  - `01_docs/README.md`
  - `01_docs/architecture/current/README.md`
  - `01_docs/onboarding/README.md`
  - `01_docs/onboarding/da_onboarding.md`
  - `01_docs/onboarding/de_onboarding.md`
  - `02_marts/README.md`
  - `03_operations/README.md`
- Local link check passed:
  - `93` local links checked
  - `0` missing links
- Mermaid render verification passed for `8` diagrams:
  - `readme_operating_map`
  - `final_bob_runtime_architecture`
  - `readme_mart_package_anatomy`
  - `readme_bob_loader_contract`
  - `readme_cicd_to_runtime_flow`
  - `readme_full_lifecycle`
  - `da_onboarding_flow`
  - `de_operating_cycle`
- New SVG existence check passed:
  - `readme_mart_package_anatomy.svg`: `25910` bytes
  - `readme_full_lifecycle.svg`: `32917` bytes
  - `da_onboarding_flow.svg`: `21826` bytes
  - `de_operating_cycle.svg`: `20745` bytes

**Current handoff:**
- Root `README.md` is now the learning/operating map.
- Detailed numeric evidence remains in context, runbook artifacts, generated JSON packages, and live framework tables.
- DA onboarding is the default entry for business SQL/mart changes.
- DE onboarding is the default entry for live scan, repo sync, SQLPROJ, orchestration, DQ/catalog, semantic smoke, and context logging.

## 2026-06-25 00:00:00 ICT — Rewrote front-door docs in Vietnamese for cross-functional onboarding

**Scope lock:**
- Repo documentation and local verification only.
- No live Fabric/SQL mutation.
- No destructive cleanup.

**User instruction:**
- Assess whether the repo feels senior/professional enough.
- Make the root README more professional and easier for non-technical readers.
- Rewrite README in Vietnamese.
- Make README-linked front-door docs Vietnamese as well.
- Explain the story top-down instead of overwhelming users with unexplained technical terms.

**Actions executed:**
- Rewrote root `README.md` in Vietnamese with a narrative flow:
  - why the repo exists
  - how roles should read it
  - how data flows from source to semantic/report
  - how mart packages are structured
  - how BOB runtime maps `_Wrk` view to final table
  - how CI/CD differs from ETL runtime
  - how DA and DE should work with the repo
  - where DQ/catalog evidence lives
  - source-of-truth and safety rules
- Added `01_docs/glossary.md` to explain common terms for DA and non-platform readers.
- Rewrote front-door docs in Vietnamese:
  - `01_docs/README.md`
  - `01_docs/onboarding/README.md`
  - `01_docs/onboarding/da_onboarding.md`
  - `01_docs/onboarding/de_onboarding.md`
  - `01_docs/architecture/current/README.md`
  - `01_docs/bob-framework/README.md`
  - `02_marts/README.md`
  - `03_operations/README.md`
  - `03_operations/deployment/sqlproj/README.md`
  - `04_semantic/README.md`
  - `05_tools/README.md`
  - `99_archive/README.md`
  - `01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md`
- Updated Mermaid diagram labels to be more Vietnamese/user-friendly while keeping object names intact:
  - `readme_operating_map`
  - `final_bob_runtime_architecture`
  - `readme_mart_package_anatomy`
  - `readme_bob_loader_contract`
  - `readme_cicd_to_runtime_flow`
  - `readme_full_lifecycle`
  - `da_onboarding_flow`
  - `de_operating_cycle`

**Verification:**
- Local link check passed:
  - `87` local links checked
  - `0` missing links
- Mermaid render verification passed:
  - `8` diagrams rendered successfully.
- Markdown fence sanity passed for front-door docs before context update.
- Grep for major English onboarding headings returned no active hits in front-door docs.

**Current handoff:**
- Root README and front-door docs now target DA/DE/cross-functional readers first.
- Deep technical object names remain in English for grep/live Fabric alignment.
- Detailed numeric evidence remains in context/artifacts, not in the root handbook.
