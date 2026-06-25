# v10 Object Classification Mapping

Date: 2026-04-30

Evidence source:

- Live export: `Enterprise_SupplyChain_Dev_architect/readiness_exports/20260430_230936/sql/03_sp_registry.csv`
- Pipeline definitions: `Enterprise_SupplyChain_Dev_architect/readiness_exports/20260430_230936/pipeline_definitions/`
- EDW fallback decision: `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`

Purpose: classify current v9 registry objects before any v10 build, rename, move, or physical separation.

## 1. Classification Rules

- `LogicalBronzeCandidate`: source-aligned object that should usually be read directly from `Enterprise_Access_Lakehouse`.
- `StagingException`: persisted Warehouse mirror remains justified because source is incomplete/temporary/unstable or needs persisted snapshot.
- `EDWSupplement_ExitCandidate`: live v9 still uses `_edw`, but v9 notes mark the `Enterprise_Lakehouse` source as ready enough for dual-read validation.
- `EDWSupplement_NotReady`: live v9 uses `_edw`, and v9 notes show source completeness, grain, or coverage is not ready.
- `ReferenceMaster`: reference/domain dimensions; ownership must be decided case-by-case.
- `DomainSilver`: Supply Chain-owned transformation logic.
- `EnterpriseReusableSilver`: conformed reusable object to promote to EnterpriseData only after approval.
- `GoldServing`: BI-ready physical Gold table for Direct Lake semantic model.

## 2. Current Object Mapping

| Current object | Layer | Current source | v10 class | Access mode | Target location | Decision note |
|---|---|---|---|---|---|---|
| `bronze.brz_saleshistory_afi__invoicedetail` | `BRZ` | `["bronze.brz_saleshistory_afi__invoicedetail_edw"]` | StagingException / `EDWSupplement_ExitCandidate` | `EDWSupplement` initially; candidate for `DirectShortcut` | `SupplyChain_Processing_Warehouse.Staging` until cutover approved | V9 note marks EL `Ready`, but live v9 still uses `_edw`; run dual-read validation before cutover |
| `bronze.brz_saleshistory_afi__invoiceheader` | `BRZ` | `["bronze.brz_saleshistory_afi__invoiceheader_edw"]` | StagingException / `EDWSupplement_NotReady` | `EDWSupplement` | `SupplyChain_Processing_Warehouse.Staging` | V9 note marks EL `Not Ready`; keep staged until date coverage/SLA validated |
| `bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily` | `BRZ` | `["bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily_edw"]` | StagingException / `EDWSupplement_NotReady` | `EDWSupplement` | `SupplyChain_Processing_Warehouse.Staging` | V9 note marks EL `Not Ready`; row count alone is misleading because grain/coverage differs |
| `bronze.brz_wholesale_codis_afi__codatan` | `BRZ` | `["Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan"]` | LogicalBronzeCandidate / DirectReadCandidate | `DirectShortcut` | `Enterprise_Access_Lakehouse` shortcut, no default persistence | Evaluate whether casts/aliases should move to Silver |
| `bronze.brz_wholesale_codis_afi__comast` | `BRZ` | `["Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST"]` | LogicalBronzeCandidate / DirectReadCandidate | `DirectShortcut` | `Enterprise_Access_Lakehouse` shortcut, no default persistence | Evaluate whether casts/aliases should move to Silver |
| `bronze.brz_wholesale_codis_afi__extord` | `BRZ` | `["Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD"]` | LogicalBronzeCandidate / DirectReadCandidate | `DirectShortcut` | `Enterprise_Access_Lakehouse` shortcut, no default persistence | Evaluate whether casts/aliases should move to Silver |
| `bronze.brz_wholesale_codis_afi__extorit` | `BRZ` | `["Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT"]` | LogicalBronzeCandidate / DirectReadCandidate | `DirectShortcut` | `Enterprise_Access_Lakehouse` shortcut, no default persistence | Evaluate whether casts/aliases should move to Silver |
| `gold.gld_fact_flat_forecast_actual` | `GLD` | `["silver.slv_actual_demand_monthly","silver.slv_forecast_demand_monthly","silver.slv_naive_forecast_monthly"]` | GoldServing / BIServing | `GoldPublish` | `SupplyChain_Gold_Warehouse.ForecastAccuracy` | Physical Gold table for Direct Lake semantic model |
| `gold.gld_fact_forecast_kpi` | `GLD` | `["silver.slv_actual_demand_monthly","silver.slv_forecast_demand_monthly","silver.slv_naive_forecast_monthly","bronze.ref_forecast_horizon"]` | GoldServing / BIServing | `GoldPublish` | `SupplyChain_Gold_Warehouse.ForecastAccuracy` | Physical Gold table for Direct Lake semantic model |
| `bronze.ref_calendar` | `REF` | `["Enterprise_Lakehouse.MasterData_DW.DimDate"]` | ReferenceMaster / NeedOwnerDecision | `DirectShortcutOrEnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | Likely reusable/reference; needs Bob/Rakesh ownership decision |
| `bronze.ref_customer_account` | `REF` | `["Enterprise_Lakehouse.Customers.AccountMaster"]` | ReferenceMaster / NeedOwnerDecision | `DirectShortcutOrEnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | Likely reusable/reference; needs Bob/Rakesh ownership decision |
| `bronze.ref_customer_account_group` | `REF` | `["Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping"]` | ReferenceMaster / NeedOwnerDecision | `DirectShortcutOrEnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | Likely reusable/reference; needs Bob/Rakesh ownership decision |
| `bronze.ref_customer_grouping` | `REF` | `["Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping"]` | ReferenceMaster / NeedOwnerDecision | `DirectShortcutOrEnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | Likely reusable/reference; needs Bob/Rakesh ownership decision |
| `bronze.ref_customer_shipping_location` | `REF` | `["Enterprise_Lakehouse.Customers.ShippingLocations"]` | ReferenceMaster / NeedOwnerDecision | `DirectShortcutOrEnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | Likely reusable/reference; needs Bob/Rakesh ownership decision |
| `bronze.ref_forecast_cycle` | `REF` | `["SupplyChain_Lakehouse.dbo.ref_forecast_cycle"]` | ReferenceMaster / DomainReference | `DirectShortcut` | `SupplyChain_Processing_Warehouse.ReferenceMaster` | Keep domain reference if not enterprise reusable |
| `bronze.ref_forecast_horizon` | `REF` | `["manual"]` | ReferenceMaster / DomainReference | `ManualSeed` | `SupplyChain_Processing_Warehouse.ReferenceMaster` | Keep domain reference if not enterprise reusable |
| `bronze.ref_item_master` | `REF` | `["Enterprise_Lakehouse.MasterData_DW.DimItemMaster"]` | ReferenceMaster / NeedOwnerDecision | `DirectShortcutOrEnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | Likely reusable/reference; needs Bob/Rakesh ownership decision |
| `bronze.ref_order_type` | `REF` | `["Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP"]` | ReferenceMaster / DomainReference | `DirectShortcut` | `SupplyChain_Processing_Warehouse.ReferenceMaster` | Keep domain reference if not enterprise reusable |
| `bronze.ref_product` | `REF` | `["bronze.ref_product_edw"]` | ReferenceMaster / `EDWSupplement_ExitCandidate` / NeedOwnerDecision | `EDWSupplement` initially; candidate for `DirectShortcut` or `EnterpriseSilver` | EnterpriseData if reusable, else `SupplyChain_Processing_Warehouse.ReferenceMaster` | V9 note marks EL `Ready`, but live v9 still uses `_edw`; requires dual-read validation and Bob/Rakesh ownership decision |
| `bronze.ref_warehouse` | `REF` | `["Enterprise_Lakehouse.SupplyChain_DW.DimAFIWarehouses"]` | ReferenceMaster / DomainReference | `DirectShortcut` | `SupplyChain_Processing_Warehouse.ReferenceMaster` | Keep domain reference if not enterprise reusable |
| `silver.slv_actual_demand_monthly` | `SLV` | `["silver.slv_invoice_detail_line_level","silver.slv_open_order_line_level","bronze.ref_calendar","bronze.ref_customer_account_group"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.SalesHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_actual_demand_weekly` | `SLV` | `["silver.slv_invoice_detail_line_level","silver.slv_open_order_line_level","bronze.ref_calendar","bronze.ref_customer_account_group"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.SalesHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_forecast_demand_monthly` | `SLV` | `["bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily","bronze.ref_forecast_cycle","bronze.ref_calendar"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.ForecastHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_invoice_detail_line_level` | `SLV` | `["bronze.brz_saleshistory_afi__invoicedetail","bronze.brz_saleshistory_afi__invoiceheader","bronze.ref_customer_account_group"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.SalesHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_invoice_weekly` | `SLV` | `["silver.slv_invoice_detail_line_level","bronze.ref_calendar"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.SalesHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_naive_forecast_monthly` | `SLV` | `["silver.slv_actual_demand_monthly","bronze.ref_calendar"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.ForecastHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_open_order_line_level` | `SLV` | `["bronze.brz_wholesale_codis_afi__codatan","bronze.brz_wholesale_codis_afi__comast","bronze.brz_wholesale_codis_afi__extord","bronze.brz_wholesale_codis_afi__extorit","bronze.ref_item_master","bronze.ref_order_type"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.OpenOrderHistory` | Promote only if conformed/reusable across domains |
| `silver.slv_open_order_monthly` | `SLV` | `["silver.slv_open_order_line_level","bronze.ref_calendar","bronze.ref_customer_account_group"]` | DomainSilver / SupplyChainSpecific | `WarehouseTransform` | `SupplyChain_Processing_Warehouse.OpenOrderHistory` | Promote only if conformed/reusable across domains |

## 3. Summary Counts

| Target class | Count | Notes |
|---|---:|---|
| StagingException / EDWSupplement | 4 total: 2 ExitCandidate + 2 NotReady | EDW-backed objects should not move to direct-only until validation and approval pass |
| LogicalBronzeCandidate / DirectReadCandidate | 4 BRZ | Direct by default if source contracts/performance pass |
| ReferenceMaster / NeedOwnerDecision | 7 REF | Likely reusable or shared; Bob/Rakesh decision required |
| ReferenceMaster / DomainReference | 3 REF | Keep local unless EnterpriseData wants ownership |
| DomainSilver | 8 SLV | Keep in SupplyChain unless approved as reusable/conformed |
| GoldServing | 2 GLD | Move/publish to dedicated Gold Warehouse physical tables |

## 4. Open Decisions

- Exact Silver schema naming: `SalesHistory`, `ForecastHistory`, `OpenOrderHistory` vs suffix forms such as `SalesHistory_ENH`.
- Which reference objects become Enterprise reusable Silver/reference assets.
- Whether `ref_product` becomes EnterpriseData-owned reference after source validation.
- Whether current Bronze direct-read candidates contain transformations that must be moved into Silver.

## 5. EDW Supplement Exit Strategy

Detailed cutover and rollback rules are defined in `Enterprise_SupplyChain_Dev_architect/30_runbook/15_v10_edw_supplement_exit_strategy.md` and formalized in `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`.

Initial build rule:

- Keep all four `_edw` objects active as `EDWSupplement`.
- Enable dual-read validation first for `brz_saleshistory_afi__invoicedetail` and `ref_product` because v9 notes mark them `Ready`.
- Keep `brz_saleshistory_afi__invoiceheader` and `brz_supplychain_enh_1__demandforecastsnapshotdaily` as `EDWSupplement_NotReady`.
- Do not remove `bronze.usp_refresh_edw_tables` until all four objects have completed cutover and fallback retention.

## 6. Dataflow-To-v10 Mapping

These dataflows are not v9 cleanup candidates. They load `SupplyChain_Lakehouse`, and v8 currently depends on those Lakehouse tables.

| Dataflow | v10 source-feed class | v10 mapping rule |
|---|---|---|
| `df_brz_SalesHistory_AFI_InvoiceDetail` | `LegacyDataflowBridge` | Keep feed; register downstream Lakehouse table as source dependency for EDW supplement/direct validation |
| `df_brz_SalesHistory_AFI_InvoiceHeader` | `LegacyDataflowBridge` | Keep feed; register downstream Lakehouse table as source dependency for EDW supplement/direct validation |
| `df_brz_SupplyChain_Enh_1_DemandForecastSnapshotDaily_copy1` | `LegacyDataflowBridge` | Keep feed; register downstream Lakehouse table as source dependency for EDW supplement/direct validation |
| `df_ref_product` | `LegacyDataflowBridge` | Keep feed; register downstream Lakehouse table as source dependency for reference/product validation |

v10 should not own deletion of these dataflows. Long-term retirement requires a separate v8 dependency review and a replacement EnterpriseData/shortcut source contract.
