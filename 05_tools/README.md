# Tools

Portfolio context: [`../00_portfolio/06_evidence_matrix.md`](../00_portfolio/06_evidence_matrix.md).
These utilities are evidence-producing and repeatability tools around the platform.

## Tool families

| Family | Purpose | Typical output |
|---|---|---|
| `01_dq` | inspect source/Bronze quality and grain | DQ result and exception evidence |
| `02_repo_maintenance` | preserve context and enforce repository conventions | normalized context and maintenance checks |
| `03_mart_sync` | compare/export live DEV contracts | source-controlled runtime snapshot |
| `04_operating_package` | regenerate catalog, DQ, lineage and run-order packages | machine-readable operating registry |
| `05_sqlproj` | build deployment/handoff packages | `.dacpac`/build logs and manifests |
| `06_lineage_portal` | scan, classify and publish sanitized lineage | live/repository graph snapshot |

## Ownership boundary

These tools support DataOps; they are not a substitute for the official
enterprise scheduler or live Fabric authorization. Defaults are read-only or
dry-run. Live execution requires an explicit approved operational action.

## Proof path

Read the relevant tool README, inspect its input contract, run fixture/local
tests, review the generated evidence, then compare with live state when the
claim concerns runtime behavior.

Folder này chứa utility scripts dùng cho repo.

Các tool ở đây phục vụ audit, sync, build operating package và bảo trì repo. Chúng không nên được xem là production scheduler.

## Bản Đồ Folder

| Folder | Ý nghĩa |
|---|---|
| `01_dq/` | Script audit DQ cho Bronze/source tables, chủ yếu read-only. |
| `02_repo_maintenance/` | Script hỗ trợ restructure repo và maintain context. |
| `03_mart_sync/` | Script sync/export mart layer từ live Fabric về repo. |
| `04_operating_package/` | Generator tạo DQ/catalog/lineage/run-order package. |
| `05_sqlproj/` | Generator hỗ trợ SQLPROJ package. |
| `06_lineage_portal/` | GitHub Actions scanner + GitHub Pages lineage portal cho Enterprise ETL runtime. |

## Script Chính

| Script | Dùng để làm gì? |
|---|---|
| `01_dq/audit_bronze_source_dq.py` | Audit DQ Bronze/source có CLI options. |
| `01_dq/audit_all_bronze_source_dq_final.py` | Scanner DQ toàn bộ source trong audit trước. |
| `02_repo_maintenance/restructure_mart_layer_sql.py` | Hỗ trợ restructure SQL theo mart/layer. |
| `02_repo_maintenance/prune_context.py` | Maintain the single retained `CONTEXT.md` handoff. |
| `03_mart_sync/sync_live_mart_layers.py` | Export/sync live mart layer về repo. |
| `04_operating_package/build_operating_package.py` | Build `04_dq/contracts`, `04_dq/runs`, `05_catalog`, `03_operations/operating_registry`. |
| `05_sqlproj/build_sqlproj_package.py` | Build/generate SQLPROJ package từ repo/live metadata. |
| `06_lineage_portal/scanner/cli.py` | Build live/static lineage snapshot cho GitHub Pages portal. |

## Ghi Chú An Toàn

```text
Ưu tiên dry-run/read-only.
Không live write nếu script không nói rõ.
Live write cần approval rõ trong cùng conversation.
Output quan trọng nên được log vào context.
```

Bronze DQ outputs nằm dưới:

```text
02_marts/<mart>/04_dq/
```
