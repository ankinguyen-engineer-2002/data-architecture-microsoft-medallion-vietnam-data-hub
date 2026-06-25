# ADR-009: Enterprise `_Wrk` View Contract For Curated Warehouses

## Status
Accepted

## Context

Live scan on 2026-06-23 showed that `SupplyChain_Warehouse.SCP_Core` uses physical final tables in the base schema and `SCP_Core_Wrk.v_<TableName>` work views as the ETL source.

`ETL_Framework.DW_Developer.usp_RefreshCuratedTableFromView` derives the work view from the final schema and table contract:

```sql
@ViewName = @DestinationDatabase + '.' + @DestinationSchema + '_Wrk.v_' + @DestinationTable
```

EnterpriseData curated/domain warehouses such as `Retail_Warehouse` and `Wholesale_Warehouse` follow the same broad pattern: base schemas are final table surfaces, `_Wrk` schemas hold work views or work objects. `Source_Data` is different because it is a source/staging estate where `_Wrk` can be physical landing/work tables.

## Decision

For SupplyChain Silver/Processing and Gold/Serving warehouses, use one canonical contract:

```text
<BaseSchema>.<TableName>        = physical final table
<BaseSchema>_Wrk.v_<TableName>  = work/source view used by ETL_Framework
```

Bronze/source documentation may list source shortcuts and source tables without forcing the curated `_Wrk` view convention.

## Consequences

- Base-schema duplicate `v_*` views are legacy compatibility artifacts only.
- New Silver/Gold work should not introduce base-schema `v_*` views.
- No business table, semantic model, or report contract changes are intended.
- Cleanup of duplicate base views requires dependency audit, rollback scripts, and explicit approval.

## 2026-06-23 Implementation Note

Stage A aligned the repo/docs and removed two stale `TableDictionary` rows for live-missing Gold tables.

Stage B completed the live cleanup:

- Rewrote `32` Processing/Silver `_Wrk` views and `13` Gold `_Wrk` views to inline source/business SQL directly.
- Dropped the corresponding `45` duplicate base-schema `v_*` views.
- Fixed the live `ReferenceMaster_Enh_Wrk.v_ItemMaster` contract bug by aligning it to the 36-column final `ReferenceMaster_Enh.ItemMaster` table contract instead of the stale 174-column wrapper.
- Strict post-clean verification passed with base-schema views disallowed.

## Evidence

- `01_docs/runbook/artifacts/20260623_scp_core_pattern_scan/fabric_workspace_inventory.json`
- `01_docs/runbook/artifacts/20260623_scp_core_pattern_scan/warehouse_catalog_scan.json`
- `01_docs/runbook/artifacts/20260623_scp_core_pattern_scan/scp_core_wrk_table_view_mapping.json`
- `01_docs/runbook/artifacts/20260623_scp_core_pattern_scan/relevant_proc_definitions.json`
- `01_docs/runbook/artifacts/20260623_scp_core_pattern_scan/enterprise_data_base_wrk_pair_scan.json`
- `01_docs/runbook/artifacts/20260623_scp_core_pattern_scan/current_processing_gold_wrk_pattern_scan.json`
- `01_docs/runbook/artifacts/20260623_2153_enterprise_wrk_contract_migration/pre_cleanup_verification_allow_base_views.json`
- `01_docs/runbook/artifacts/20260623_2153_enterprise_wrk_contract_migration/wrk_view_rewrite_package_summary.json`
- `01_docs/runbook/artifacts/20260623_2153_enterprise_wrk_contract_migration/wrk_view_rewrite_package_static_qc.json`
- `01_docs/runbook/artifacts/20260623_2153_enterprise_wrk_contract_migration/post_cleanup_verification_strict.json`
- `01_docs/runbook/artifacts/20260623_2153_enterprise_wrk_contract_migration/16_wrk_top0_smoke_after_base_view_drop.json`
- `01_docs/runbook/artifacts/20260623_2153_enterprise_wrk_contract_migration/18_legacy_base_view_reference_scan_after_cleanup.json`
