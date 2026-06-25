# Risks Register — `EnterpriseData-Dev`

> 28 risks identified by scan. Top 5 by severity.

## Critical / High (5)

| ID | Severity | Title | Description | Action |
|----|----------|-------|-------------|--------|
| C1 | 🔴 Critical | Plaintext SP secret | `MetaData-Pull` notebook **cell 1** has plaintext SP credentials in source code | **Rotate immediately**, use cell 2/3/4 with Key Vault |
| C2 | 🔴 High | Cross-env contamination | `AshleyBIApplicationProd` has Admin role on DEV workspace | Remove or downgrade Admin role |
| C3 | 🔴 High | Empty production tier | `Quality_Warehouse` PROD tier has 0 tables / 0 procs | Decide: build out or remove |
| C25 | 🔴 High | Shortcut write-back risk | `Centralized_Lakehouse` 5.92B rows are OneLake shortcuts to PROD WS — write-back affects PROD | Documentation + access control |
| C28 | 🔴 High | Broad ADLS mount | `RadarSync_Test` mounts entire ADLS trusted+raw zones (not scoped) | Restrict scope, or remove |

## Medium (~10)

- 4 clones of TableDictionary (`_clone`, `_edw_1`, `_Test`, `_Security`) + 2 `_UpdateLog*` siblings — drift risk, authority ambiguity
- 12 parquet-loader proc variants — technical debt from experimentation
- No retention policy on AuditLog — will grow indefinitely
- Many pipelines named `test` / `pipeline1` doing real PROD work — naming mismatch

## Low (~13)

- Stranded business tables in ETL_Framework (`Manufacturing_Maximo.Fedex`, `MasterData_ItemMaster_AFI.ITEMASA`, etc.) — should live in domain WHs
- Dormant pipelines (38 of 41 zero recent runs) — definition drift
- 13 parquet-loader proc variants need consolidation

## Implications for VN team

| Risk | VN team relevance |
|------|---------------------|
| C1 | VN team's pyodbc connection uses `az login` token (no plaintext). ✅ Safe |
| C2 | VN team uses dedicated identity, no cross-env Admin grants. ✅ Safe |
| C3 | VN team's Gold WH has actual data, not empty. ✅ Safe |
| C25 | VN's `Enterprise_Lakehouse` is shortcut from hub Bronze — read-only from VN side. Write-back risk minimal but should not happen via VN pipelines. ⚠️ Audit |
| C28 | Not applicable — VN team doesn't mount ADLS broadly |
| Parquet loader variants | VN has **1 generic** `usp_GenericLoad` covering 8 patterns. Better than Enterprise ETL's 12 variants. ✅ Already aligned |
| AuditLog retention | VN's AuditLog will also grow — should plan archival |

## Cross-refs

- Full risks (raw): `_external_refs/enterprisedata-dev-01_docs/docs/09-risks/`
