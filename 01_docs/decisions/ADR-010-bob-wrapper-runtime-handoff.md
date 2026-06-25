# ADR-010: BOB Wrapper Runtime Handoff For Phase 1

## Status
Accepted

## Context

Phase 1 replaced the old VN control-plane critical path with the local BOB-aligned `ETL_Framework` runtime in `Enterprise SupplyChain-Dev`, while preserving the existing Bronze/Silver/Gold business surface and semantic/report contract.

Final live validation on 2026-06-24 proved the active DEV runtime can refresh both current marts through four wrapper stored procedures.

## Decision

Use these wrapper procedures as the official Phase 1 SQL Agent handoff surface:

```sql
EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver;
EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold;
EXEC SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver;
EXEC SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold;
```

`Shared_DW` and `ReferenceMaster_Enh` are not standalone marts in this handoff. They are embedded prerequisite waves inside the mart wrappers:

- Silver wrappers include `ReferenceMaster_Enh` prerequisite Wave 00 where required.
- Gold wrappers include `Shared_DW` prerequisite Wave 00 where required.

## Runtime Contract

- Final tables live in the base curated schema.
- Source/work views live in `<BaseSchema>_Wrk.v_<TableName>`.
- `ETL_Framework.DW_Developer.TableDictionary` is the active registry and source mapping surface.
- `ETL_Framework.DW_Developer.AuditLog` is the execution evidence surface.
- `ETL_Framework.DW_Developer.TableDictionary_UpdateLog` tracks metadata update history.
- `SupplyChain_Processing_Warehouse.Meta.usp_GenericLoad` is fallback only, not the critical path.

## Consequences

- SQL Server Agent should call only the four wrapper procedures above for Phase 1 DEV handoff.
- Do not reintroduce separate `Usp_Refresh_SupplyChain_ReferenceMaster` or `Usp_Refresh_SupplyChain_Shared` handoff procedures unless the architecture is reopened.
- Do not run tables alphabetically. Wrapper procedure order encodes the dependency/wave order.
- Phase 2 DQ, lineage UI, alert routing, and production promotion remain deferred.

## Evidence

- Full wrapper run on 2026-06-24 passed `4/4`, total runtime `1,721.01s`.
- Live/local SQL modules matched `49/49`, with `0` missing and `0` drift.
- Active `TableDictionary` had `46` curated rows, `46` `_Wrk.v_*` references, and `0` active error rows.
- Compile smoke passed `92/92` active target/source checks.
- `AuditLog` since full run start had `56 Process Start`, `56 Process Complete`, and `0` error rows.
- `queryinsights` had `0` non-success entries since full run start.
- Semantic read-only smoke confirmed `sc_control_tower` exists and remains Direct Lake on `SupplyChain_Gold_Warehouse`.

## References

- `README.md`
- `03_operations/orchestration/main/README.md`
- `01_docs/architecture/current/final_bob_runtime_architecture.md`
- `00_CONTEXT/current.md`
