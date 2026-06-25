# v10 EDW Supplement Exit Strategy

Date: 2026-05-01

Purpose: preserve the v9 temporary EDW supplement pattern while defining a clean, auditable path back to `Enterprise_Lakehouse` direct access when the shortcut-backed sources become complete and governed.

## 1. Evidence

Local v9 evidence:

- `99_archive/architectures/v9_april/01_sc_forecast/README.md`: documents four temporary `_edw` objects and marks two as `Ready`, two as `Not Ready`.
- `99_archive/architectures/v9_april/01_sc_forecast/docs/03_operations/edw_source_swap.md`: documents the EDW source swap, rollback flow, and the reason for `_edw`.
- `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/sql/06_sp_registry.csv`: confirms the live v9 registry still points four objects to `_edw`.
- `Enterprise_SupplyChain_Dev_architect/detail_clone_v9_forecast/20260501_093155/pipeline_stored_procedures.csv`: confirms `pl_sc_master` still starts with `bronze.usp_refresh_edw_tables`.
- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`: records the formal v10 decision for fallback retention, dual-read validation, and retirement.

Platform evidence:

- Microsoft Fabric shortcuts are the target direct-access pattern because they expose data without copying it: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-shortcuts
- Lakehouse SQL analytics endpoint is read-only, so persisted staging remains valid when the framework needs Warehouse-owned persisted state: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint

## 2. Current Object Status

| Object | Current v9 source | V9 source readiness note | v10 status | Initial v10 access mode |
|---|---|---|---|---|
| `bronze.brz_saleshistory_afi__invoicedetail` | `bronze.brz_saleshistory_afi__invoicedetail_edw` | `Ready` | `EDWSupplement_ExitCandidate` | `EDWSupplement` until validation passes |
| `bronze.brz_saleshistory_afi__invoiceheader` | `bronze.brz_saleshistory_afi__invoiceheader_edw` | `Not Ready` | `EDWSupplement_NotReady` | `EDWSupplement` |
| `bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily` | `bronze.brz_supplychain_enh_1__demandforecastsnapshotdaily_edw` | `Not Ready`; EL row count alone is misleading because grain/coverage differs | `EDWSupplement_NotReady` | `EDWSupplement` |
| `bronze.ref_product` | `bronze.ref_product_edw` | `Ready` | `EDWSupplement_ExitCandidate` plus ownership decision | `EDWSupplement` until validation and owner sign-off pass |

Important interpretation:

- `Ready` does not mean "switch immediately".
- `Ready` means eligible for dual-read validation and controlled cutover.
- Live v9 still uses `_edw`, so v10 must preserve fallback until cutover is proven over multiple runs.

## 3. Target Lifecycle

```text
EDWSupplement_NotReady
  -> source completeness/grain/SLA confirmed
  -> EDWSupplement_ExitCandidate
  -> dual-read validation passes for N runs
  -> DirectShortcut_CutoverPendingApproval
  -> DirectShortcut_Active
  -> RetainedFallback
  -> RetiredFallback
```

No object should jump directly from `EDWSupplement` to `DirectShortcut_Active`.

## 4. Required Metadata

Add or represent these attributes in `Meta.AssetRegistryV10` or a child table such as `Meta.SourceContract` / `Meta.ReconciliationRule`:

| Attribute | Purpose |
|---|---|
| `access_mode` | Current execution route: `EDWSupplement`, `DirectShortcut`, `WarehouseTransform`, etc. |
| `edw_exit_status` | `NotReady`, `ExitCandidate`, `CutoverPendingApproval`, `DirectActive`, `RetainedFallback`, `RetiredFallback` |
| `logical_source_reference` | Intended target source in `Enterprise_Lakehouse` |
| `fallback_source_reference` | Current `_edw` source or staging source |
| `source_contract_status` | `Unknown`, `NotReady`, `Stable`, `Approved` |
| `coverage_status` | Completeness and date-range coverage status |
| `grain_status` | Confirms row grain is compatible with v9 logic |
| `schema_status` | Confirms columns/types/nullability are compatible |
| `performance_status` | Confirms direct shortcut read is acceptable |
| `cutover_approved_by` | Bob/Rakesh/assigned owner approval |
| `cutover_approved_at` | Approval timestamp |
| `fallback_retention_until` | Date/time to retain `_edw` fallback after cutover |

## 5. Dual-Read Validation Gates

Before changing any object from `EDWSupplement` to `DirectShortcut`, run these checks against both the current `_edw` source and the target `Enterprise_Lakehouse` source.

| Gate | Required check | Notes |
|---|---|---|
| Schema parity | Column presence, compatible data types, nullability changes | Type widening may be acceptable only if downstream SQL is safe |
| Grain parity | Business key uniqueness and expected duplicate pattern | Mandatory for `DemandForecastSnapshotDaily` because row count can be misleading |
| Date coverage | Min/max dates and required historical windows | Especially important for invoice header and forecast snapshots |
| Row count parity | Count by day/month/business slice | Use aggregate windows, not only total rows |
| Key coverage | Anti-join missing keys in both directions | Use stable business keys per table |
| Metric parity | Critical downstream counts/sums after Silver transform | Validates impact, not just raw input |
| DQ parity | Existing v9 DQ rules still pass | Preserve v9 DQ control-plane behavior |
| Performance | Direct shortcut read duration and query plan/runtime stability | If direct read is unstable, keep staging |
| Lineage | Logical source and fallback source are both visible | Avoid hiding temporary bridge/fallback |

## 6. Cutover Procedure

Use this sequence per object, not as a bulk switch.

1. Keep the object in `EDWSupplement`.
2. Add the target `Enterprise_Lakehouse` source reference to metadata as `logical_source_reference`.
3. Run dual-read validation and store results in `Meta.ReconciliationResult`.
4. If validation fails, keep `_edw` as active and log the failed gate.
5. If validation passes for the agreed number of runs, mark `edw_exit_status = CutoverPendingApproval`.
6. Ask Bob/Rakesh/assigned approver for object-level sign-off.
7. Change only metadata routing to `DirectShortcut`; do not delete `_edw`.
8. Run Bronze/Silver/Gold side-by-side or shadow validation for the affected downstream chain.
9. Keep `_edw` as `RetainedFallback` through the agreed retention window.
10. Only after retention and explicit approval, retire fallback objects and remove `refresh_edw` dependency if all four objects have exited.

## 7. Rollback Procedure

Rollback should be metadata-first:

1. Change the object back from `DirectShortcut` to `EDWSupplement`.
2. Re-run `refresh_edw` or the v10 equivalent staging refresh.
3. Re-run the affected downstream chain.
4. Record the rollback reason in `Meta.ApprovalLog` or `Meta.ReconciliationResult`.
5. Do not delete direct-source metadata; mark it as failed or paused for later review.

## 8. Object-Specific Notes

### `brz_saleshistory_afi__invoicedetail`

- V9 note marks EL as `Ready`.
- Live v9 still uses `_edw`.
- v10 should treat this as first cutover candidate, but only after dual-read validation.

### `brz_saleshistory_afi__invoiceheader`

- V9 note marks EL as `Not Ready`.
- Keep `EDWSupplement`.
- Primary validation gate should focus on missing date range coverage.

### `brz_supplychain_enh_1__demandforecastsnapshotdaily`

- V9 note marks EL as `Not Ready`.
- EL row count can be higher but still wrong if snapshot grain/coverage differs.
- Grain, snapshot-date coverage, and metric parity are mandatory.

### `ref_product`

- V9 note marks EL as `Ready`.
- Because Bob's pattern treats reusable/reference data as Enterprise-owned when cross-domain, this object needs both source validation and ownership decision.
- Do not force it into local SupplyChain direct mode if EnterpriseData should own the reference contract.

## 9. Build Rule For v10

Initial v10 build should preserve all four `_edw` fallback paths. The difference from v9 is that v10 makes the route metadata-driven:

- `EDWSupplement_NotReady`: active fallback, no cutover attempt.
- `EDWSupplement_ExitCandidate`: active fallback plus dual-read validation enabled.
- `DirectShortcut_Active`: target after validation and approval.
- `RetainedFallback`: fallback preserved for rollback, not part of normal execution.

This prevents both risks:

- Losing v9 operational correctness by cutting over too early.
- Keeping Bronze duplication forever after `Enterprise_Lakehouse` becomes stable.

## 10. Related Documents

- `01_docs/decisions/ADR-002-edw-supplement-exit-strategy.md`
- `Enterprise_SupplyChain_Dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`
