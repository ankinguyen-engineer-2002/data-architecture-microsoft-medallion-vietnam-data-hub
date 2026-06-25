# ADR-002: EDW Supplement Exit Strategy For v10

Date: 2026-05-01

Status: Proposed — Active (4 EDW supplement tables still in `Staging_WRK`, pending Enterprise Lakehouse data completeness)

## Context

The v9 Supply Chain Forecast Accuracy implementation still uses four temporary `_edw` supplement paths because the shortcut-backed `Enterprise_Lakehouse` sources were not equally complete or stable for all required objects.

Verified local evidence:

- `99_archive/architectures/v9_april/01_sc_forecast/README.md` documents four temporary `_edw` objects and marks two sources as `Ready`, two as `Not Ready`.
- `99_archive/architectures/v9_april/01_sc_forecast/docs/03_operations/edw_source_swap.md` documents the EDW source swap and rollback path.
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/detail_clone_v9_forecast/20260501_093155/sql/06_sp_registry.csv` confirms the live v9 registry still points four objects to `_edw`.
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/detail_clone_v9_forecast/20260501_093155/pipeline_stored_procedures.csv` confirms `pl_sc_master` still starts with `bronze.usp_refresh_edw_tables`.

Platform context:

- [Verified] Fabric shortcuts can expose data without copying it, so they are the target Bronze access pattern when source contracts are stable.
- [Verified] Fabric medallion guidance recommends clear Bronze/Silver/Gold separation, with shortcuts preferred over copies for source data already available through OneLake-compatible paths.
- [Verified] The Lakehouse SQL analytics endpoint is read-only, so Warehouse-owned persisted staging remains valid when the framework needs controlled persisted state, reconciliation, replay, or fallback.

## Decision

Initial v10 keeps all four `_edw` fallback paths active.

The objects are split by exit maturity:

| Object | Initial v10 status | Reason |
|---|---|---|
| `brz_saleshistory_afi__invoicedetail` | `EDWSupplement_ExitCandidate` | v9 note marks Enterprise Lakehouse source `Ready`, but live v9 still uses `_edw` |
| `brz_saleshistory_afi__invoiceheader` | `EDWSupplement_NotReady` | v9 note marks Enterprise Lakehouse source `Not Ready` |
| `brz_supplychain_enh_1__demandforecastsnapshotdaily` | `EDWSupplement_NotReady` | v9 note marks source `Not Ready`; grain and coverage are more important than raw row count |
| `ref_product` | `EDWSupplement_ExitCandidate` plus owner decision | v9 note marks source `Ready`, but ownership may belong to EnterpriseData if reusable |

Rules:

- No bulk switch from `_edw` to direct shortcut.
- No object moves from `EDWSupplement` to `DirectShortcut` without dual-read validation.
- No object cuts over without Bob/Rakesh or assigned technical approver sign-off.
- `_edw` fallback remains as `RetainedFallback` after cutover until the rollback window closes.
- `bronze.usp_refresh_edw_tables` is removed only after all four objects reach `RetiredFallback` and explicit destructive-operation approval is granted.

## Consequences

Positive:

- Preserves v9 operational correctness while v10 moves toward cleaner medallion alignment.
- Avoids treating all four `_edw` objects as equally ready.
- Keeps a rollback path for high-risk source swaps.
- Gives Bob/Rakesh an object-level approval model instead of a vague architecture claim.

Costs and risks:

- v10 must carry fallback routing metadata during transition.
- Reconciliation tables and validation rules must exist before any exit candidate is cut over.
- The `refresh_edw` or v10 equivalent remains in the dependency chain until all four objects exit.
- Cleanup takes longer because fallback retirement is intentionally delayed.

## Rejected Alternatives

### Immediate Full Direct Cutover

Rejected.

Reason:

- Live v9 still routes all four objects through `_edw`.
- Two objects are explicitly `Not Ready` in v9 notes.
- A direct-only switch would remove rollback before source coverage, grain, and metric parity are proven.

### Keep `_edw` Forever

Rejected as target state.

Reason:

- It keeps unnecessary duplication after sources become stable.
- It conflicts with the target medallion direction that treats shortcut-backed Enterprise access as logical Bronze.

### Delete `_edw` Immediately After First Passing Run

Rejected.

Reason:

- One passing run is not enough evidence for source stability, late-arriving changes, or downstream KPI parity.
- Fallback must remain through an approved rollback window.

### Bulk Switch All Four Objects Together

Rejected.

Reason:

- The four objects have different readiness states and risk profiles.
- `DemandForecastSnapshotDaily` needs grain and coverage validation that total row-count checks cannot prove.

## Validation Gates

Each object must pass these gates before cutover:

| Gate | Required evidence |
|---|---|
| Schema parity | Column presence, type compatibility, nullability compatibility |
| Grain parity | Business grain and key duplicate pattern match expected downstream behavior |
| Date coverage | Min/max date and required history window match v9 needs |
| Row-count parity | Counts by day/month/business slice, not just total rows |
| Key coverage | Anti-join missing keys checked in both directions |
| Metric parity | Critical Silver/Gold metrics remain within approved threshold |
| DQ parity | Existing v9 DQ rules remain green or approved as warning |
| Performance | Direct shortcut read is stable enough for pipeline SLA |
| Lineage | Direct logical source and fallback source remain traceable |
| Approval | Bob/Rakesh or assigned approver signs off object-by-object |

## Live Audit (2026-05-04)

### Enterprise Lakehouse Equivalents — Verified

All 4 Enterprise Lakehouse tables **exist** with **exact column count match**:

| EDW Supplement (Staging_WRK) | Enterprise Lakehouse Direct | Cols | Status |
|---|---|---|---|
| `InvoiceDetailEdw` | `Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail` | 80 = 80 | **EXISTS** — pending data completeness |
| `InvoiceHeaderEdw` | `Enterprise_Lakehouse.SalesHistory_AFI.InvoiceHeader` | 40 = 40 | **EXISTS** — pending data completeness |
| `ProductEdw` | `Enterprise_Lakehouse.SupplyChain_DW.DimCurrentProductDetails` | 89 = 89 | **EXISTS** — pending data completeness |
| `DemandForecastSnapshotDailyEdw` | `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily` | 23 = 23 | **EXISTS** — pending data completeness |

### Current Path (đường vòng — temporary)

```
Enterprise EDW → Bob team Dataflow → SupplyChain_Lakehouse._ver2 → usp_RefreshEdwTables → Staging_WRK tables
```

### Target Path (khi Enterprise Lakehouse đủ data)

```
Enterprise_Lakehouse.{schema}.{table} → view trực tiếp → usp_GenericLoad → Silver tables
```

### Exit Action Plan

Khi Bob team confirm data completeness cho từng bảng:

1. Tạo view mới đọc trực tiếp từ Enterprise_Lakehouse (giống 12 views hiện tại đã làm)
2. Update `AssetRegistry`: `access_mode` từ `EDWSupplement` → `DirectShortcut`
3. **Chuyển load pattern** cho bảng lớn:

| Table | Rows | Current Pattern | Target Pattern | Watermark | Rationale |
|---|---|---|---|---|---|
| `InvoiceDetail` | 88M | overwrite | **`incremental`** | `InvoiceDate` | Invoice cũ không đổi, daily delta ~50K << 88M full |
| `InvoiceHeader` | 24M | overwrite | **`incremental`** | `InvoiceDate` | Tương tự invoice detail |
| `Product` | 379K | overwrite | **`overwrite`** (giữ) | — | Nhỏ, full refresh OK |
| `DemandForecastSnapshot` | 42M | overwrite | **`incremental`** | `SnapshotTS` | Append-only daily snapshots, delta ~50K << 42M full |

4. Xóa `usp_RefreshEdwTables` (không cần nữa — `usp_GenericLoad` xử lý tất cả)
5. Bỏ 4 Dataflow feeds trong SupplyChain_Lakehouse
6. Xóa 4 bảng `_ver2` trong SupplyChain_Lakehouse

**Khi exit hoàn thành**: `usp_GenericLoad` thực sự xử lý 100% tables ở tất cả layers (Bronze → Silver). Load patterns `incremental` sẽ được prove live lần đầu.

---

## Implementation Linkage

Detailed implementation rules are maintained in:

- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/30_runbook/15_v10_edw_supplement_exit_strategy.md`
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/20_proposals/12_v10_object_classification_mapping.md`
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/30_runbook/14_v10_step_by_step_implementation_runbook.md`
- `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md`

## References

- Microsoft Fabric shortcuts: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-shortcuts
- Microsoft Fabric medallion architecture: https://learn.microsoft.com/en-us/fabric/onelake/onelake-medallion-lakehouse-architecture
- Lakehouse SQL analytics endpoint: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-sql-analytics-endpoint
