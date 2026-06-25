# 20 — Silver Layer

> Scanned: 2026-05-06 · Updated 2026-06-01 after ProcessingSeed cleanup and live run-log audit.
> **Warehouse:** `SupplyChain_Processing_Warehouse` (`c0262cef-b8a7-495f-bccc-53b098c7948c`)
> **Schemas:** `Staging_Wrk`, `ReferenceMaster_Enh`, `SalesHistory_Enh`, `ForecastHistory_Enh`, `OpenOrderHistory_Enh`, `Meta`

## Summary

| Schema | Tables | Views | Total rows |
|--------|-------:|------:|-----------:|
| `Staging_Wrk` | 4 | 4 | 156,120,911 |
| `ReferenceMaster_Enh` | 10 | 11 | 637,360 |
| `SalesHistory_Enh` | 4 | 4 | 136,442,343 |
| `ForecastHistory_Enh` | 2 | 2 | 44,454,578 |
| `OpenOrderHistory_Enh` | 2 | 2 | 269,015 |
| `Meta` | 23 | 4 | (control plane — added `TableDictionary`, `TableDictionary_UpdateLog`, `AuditLog` per Bob alignment 2026-05-10) |

> ETL DDL for all views: see [`etl/staging_ddl.sql`](etl/staging_ddl.sql) and [`etl/silver_views.sql`](etl/silver_views.sql).

## 2026-06-01 Live Run-Log Override

The historical summary below is retained for baseline context. Current live `Meta.RunLog` / SQL audit shows these key row counts:

| Table | Rows loaded | Latest successful load |
|---|---:|---|
| `ReferenceMaster_Enh.ForecastCycle` | 43 | 2026-06-01 |
| `ReferenceMaster_Enh.ForecastHorizon` | 8 | 2026-06-01 |
| `ReferenceMaster_Enh.Warehouse` | 53 | 2026-05-29 |
| `SalesHistory_Enh.InvoiceDetailLineLevel` | 128,572,413 | 2026-05-29 |
| `SalesHistory_Enh.ActualDemandMonthly` | 297,257 | 2026-05-29 |
| `SalesHistory_Enh.ActualDemandWeekly` | 616,274 | 2026-05-29 |
| `SalesHistory_Enh.InvoiceWeekly` | 15,644,636 | 2026-05-29 |
| `ForecastHistory_Enh.ForecastDemandMonthly` | 138,004,165 | 2026-05-29 |
| `ForecastHistory_Enh.NaiveForecastMonthly` | 208,492 | 2026-05-29 |

---

## `Staging_Wrk` — Raw EDW Projection

**Pattern:** TRIM strings, TRY_CONVERT dates, rename to PascalCase. No JOIN. No business logic.

| Table | Rows | Cols | Source | Load | Freq |
|-------|-----:|-----:|--------|------|------|
| `InvoiceDetailEdw` | 88,373,614 | — | `SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoicedetail_ver2` | overwrite | daily |
| `InvoiceHeaderEdw` | 24,961,791 | — | `SupplyChain_Lakehouse.dbo.brz_saleshistory_afi__invoiceheader_ver2` | overwrite | daily |
| `DemandForecastSnapshotDailyEdw` | 42,406,201 | — | `SupplyChain_Lakehouse.dbo.brz_supplychain_enh_1__demandforecastsnapshotdaily_ver2` | overwrite | daily |
| `ProductEdw` | 379,305 | — | `SupplyChain_Lakehouse.dbo.ref_product_ver2` | overwrite | monthly |

**Views (1-to-1 with EDW source tables, plus 4 `v_<Codis>` for direct shortcut access):**

| View | Maps from | Notes |
|------|-----------|-------|
| `v_Codatan` | `Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan` | Direct shortcut read; TRIM all strings |
| `v_Comast` | `Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST` | Direct shortcut |
| `v_Extord` | `Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD` | Direct shortcut; BIGINT date → TRY_CONVERT |
| `v_Extorit` | `Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT` | Direct shortcut |

**Refresh SP:** `Staging_Wrk.usp_RefreshEdwTables` performs DROP + CTAS for all 4 EDW supplement tables in one call.

---

## `ReferenceMaster_Enh` — Domain Reference Data (Shared)

| Table | Rows | Source | Load | Freq |
|-------|-----:|--------|------|------|
| `Calendar` | 21,551 | `Enterprise_Lakehouse.MasterData_DW.DimDate` (extended +64 cols vs v8) | overwrite | monthly |
| `CustomerAccount` | 35,617 | `Enterprise_Lakehouse.Customers.AccountMaster` | overwrite | monthly |
| `CustomerAccountGroup` | 35,617 | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping` | overwrite | monthly |
| `CustomerGrouping` | 35,617 | `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping` | overwrite | monthly |
| `CustomerShippingLocation` | 127,660 | `Enterprise_Lakehouse.Customers.ShippingLocations` | overwrite | monthly |
| `ForecastCycle` | 43 | `ProcessingSeed.ForecastCycle` | overwrite | monthly |
| `ForecastHorizon` | 8 | `ProcessingSeed.ForecastHorizon` | overwrite | monthly |
| `ItemMaster` | 381,163 | `Enterprise_Lakehouse.MasterData_DW.DimItemMaster` | overwrite | monthly |
| `OrderType` | 29 | seeded reference | overwrite | monthly |
| `Warehouse` | 53 | `Enterprise_Lakehouse.CustomerOrders_AFI.WarehouseMaster` | overwrite | daily |

**11 paired views** in same schema map raw sources → PascalCase business columns.

> **2026-06-01 reference cleanup:** the former passthrough `SELECT *` views for `CustomerAccount`, `CustomerShippingLocation`, `ForecastCycle`, `ItemMaster`, and `OrderType` were replaced with explicit, contract-preserving projections. Text columns are `TRIM` + `CAST`; numeric/date/bit columns are cast back to the live view contract. `LoadDT` remains a materialization column appended by `Meta.usp_GenericLoad`, not part of the source views.

> **2026-06-01 ProcessingSeed cleanup:** `ForecastCycle` and `ForecastHorizon` now source from Processing Warehouse seed tables under `ProcessingSeed`. `ForecastCycle` remains fed by the existing SharePoint Dataflow Gen2, but the destination is Processing-owned instead of the SupplyChain Lakehouse staging table. The Silver view aliases raw ProcessingSeed column names back to the existing business contract (`ForecastSnapshot`, etc.) so downstream forecast joins remain stable.

> **Smart skip:** Most ReferenceMaster_Enh assets are `freq=monthly` — pipeline `Lookup` step filters by `next_run_time`, skipping these on daily runs.

---

## `SalesHistory_Enh` — Demand & Invoice (Wave 0 + 1)

| Table | Rows | Wave | Source | ETL summary |
|-------|-----:|:----:|--------|------------|
| `InvoiceDetailLineLevel` | 88,373,617 | 0 | `Staging_Wrk.InvoiceDetailEdw` + `InvoiceHeaderEdw` + `ReferenceMaster_Enh.CustomerAccountGroup` | LEFT JOIN header on InvoiceID+Date+OrderID; LEFT JOIN CG on Customer; UPPER+TRIM CustomerGroupCode |
| `ActualDemandMonthly` | 2,651,115 | 1 | `InvoiceDetailLineLevel` + `OpenOrderHistory_Enh.OpenOrderLineLevel` + `Calendar` | GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthFirst/Last; UNION historical + open |
| `ActualDemandWeekly` | 7,860,043 | 1 | (same sources, week grain) | Week-grain demand |
| `InvoiceWeekly` | 37,557,568 | 1 | `InvoiceDetailLineLevel` + `Calendar` | Aggregated invoice lines per week |

---

## `ForecastHistory_Enh` — Forecast Demand (Wave 0 + 2)

| Table | Rows | Wave | Source | ETL summary |
|-------|-----:|:----:|--------|------------|
| `ForecastDemandMonthly` | 42,406,201 | 0 | `Staging.DemandForecastSnapshotDaily` + `ReferenceMaster_Enh.ForecastCycle` | Latest snapshot per cycle; JOIN ForecastCycle for HorizonCode |
| `NaiveForecastMonthly` | 2,048,377 | 2 | `SalesHistory_Enh.ActualDemandMonthly` | Lag-based naive forecast (depends on Wave 1) |

---

## `OpenOrderHistory_Enh` — Open Orders (Wave 0 + 1)

| Table | Rows | Wave | Source | ETL summary |
|-------|-----:|:----:|--------|------------|
| `OpenOrderLineLevel` | 189,591 | 0 | `Staging_Wrk.v_Extord` + `v_Extorit` + `v_Codatan` + `Calendar` | 4-way JOIN on CODIS open-order tables; INNER JOIN Calendar on CurrentRequest |
| `OpenOrderMonthly` | 79,424 | 1 | `OpenOrderLineLevel` + `Calendar` + `CustomerAccountGroup` | GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonth; SUM Qty+Amt, COUNT lines |

---

## DAG Wave Assignment (live from `Meta.SilverDagWaveRuntime`)

```
Wave 0  (no Silver deps — read from Staging + Reference + Lakehouse)
   ├── SalesHistory_Enh.InvoiceDetailLineLevel
   ├── ForecastHistory_Enh.ForecastDemandMonthly
   └── OpenOrderHistory_Enh.OpenOrderLineLevel

Wave 1  (depends on Wave 0)
   ├── SalesHistory_Enh.ActualDemandMonthly
   ├── SalesHistory_Enh.ActualDemandWeekly
   ├── SalesHistory_Enh.InvoiceWeekly
   └── OpenOrderHistory_Enh.OpenOrderMonthly

Wave 2  (depends on Wave 1)
   └── ForecastHistory_Enh.NaiveForecastMonthly  ← needs ActualDemandMonthly
```

Waves computed dynamically by `Meta.usp_ComputeSilverWaves` based on `Meta.AssetRegistry.depends_on` JSON arrays. Pipeline `pl_sc_silver` reads `Meta.SilverDagWaveRuntime` and dispatches each wave to `pl_sc_silver_wave` with parallel batch=8 inside the wave.

---

## `Meta` Schema — Control Plane (20 tables, 5 views, 14 SPs, 3 functions)

### Tables

| Table | Purpose |
|-------|---------|
| `AssetRegistry` | Master registry — 33 active assets across Staging + Reference + Silver + Gold |
| `AssetAccessPolicy` | Access decisions: DirectShortcut / EDWSupplement / WarehouseTransform |
| `ObjectClassification` | Physical classification per asset |
| `SourceFeed` | Source feed metadata (52 entries — feeds describe upstream sources) |
| `SourceContract` | Column-level schema contracts (674 columns) |
| `SourceContractRun` | Contract validation runs |
| `DQRule` | DQ rules — 54 active rules (completeness, row_count, uniqueness, freshness) |
| `DQGateRun` | Per-rule DQ execution result |
| `ReconciliationRule` | Source-target row count reconciliation rules (6 active) |
| `ReconciliationResult` | Reconciliation run results |
| `LineageEdge` | Auto-built lineage graph (60 edges live) |
| `SilverDagWaveRuntime` | Computed wave assignments (8 entries: 3+4+1) |
| `RunLog` | Per-table execution log (UTC + CST timestamps, rows, status) |
| `PipelineRunLog` | Pipeline-level audit trail |
| `PerformanceBaseline` | Performance benchmark baselines |
| `PipelineCostLog` | Per-pipeline-run cost log |
| `SecurityPolicy` | Workspace/item security policies |
| `SemanticModelContract` | Gold → semantic model edge contracts |
| `ApprovalLog` | Approvals for sensitive ops |
| `DeploymentChecklist` | Deployment readiness items |

### Views

| View | Purpose |
|------|---------|
| `v_AccessDecision` | Computed access mode per asset |
| `v_RegistryCompat` | v9 backward-compat view for old code |
| `v_SilverWaveRuntime` | Pretty wave assignment query |
| `TableDictionary` | 63-column Enterprise-compatible adapter |
| `v_sp_registry` | v9 compat — sp/view/table mapping |

### Stored Procedures (14)

| SP | Role |
|----|------|
| `usp_GenericLoad` | Single SP for 8 load patterns (overwrite, incremental, upsert, datekey, daterange, identity, cdc, scd2) |
| `usp_RunSilverDag` | Manual fallback to run Silver DAG via SP (when pipeline unavailable) |
| `usp_ComputeSilverWaves` | Compute wave assignments from `depends_on` JSON, write to `SilverDagWaveRuntime` |
| `usp_BuildLineage` | Auto-build lineage edges from `source_objects` registry JSON |
| `usp_LogPipelineRun` | Pipeline start log |
| `usp_FinalizePipeline` | Pipeline end log + lineage rebuild |
| `usp_LogRun` | Per-table run log (with 3x retry for snapshot conflicts) |
| `usp_CheckDq` | Run DQ for a target table |
| `usp_CheckDqSingle` | Run a single DQ rule |
| `usp_RunDQGate` | Severity-gated DQ run (CRITICAL=throw, WARNING=log) |
| `usp_RunReconciliation` | Source-target row count reconciliation |
| `usp_ValidateSourceContract` | Schema contract validation |
| `usp_ResolveAccessMode` | Resolve access mode per asset |
| `usp_DebugLoop` | Debug helper for ForEach loops |

### Scalar Functions (3)

| Function | Purpose |
|----------|---------|
| `ufn_cron_is_due` | 5-field cron expression parser — returns 1 if cron is due NOW |
| `ufn_should_run` | Asset due check — combines cron + last_run + frequency |
| `ufn_utc_to_cst` | DST-aware UTC → CST timezone conversion |

> Full DDL: see [`etl/meta_sps.sql`](etl/meta_sps.sql).
