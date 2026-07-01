# Operations

Folder này là trạm vận hành mini của repo.

Nó không thay thế official enterprise scheduler. Nó giúp DE/Aric/agent hiểu thứ tự chạy, dry-run luồng refresh, chạy ad-hoc khi được approve, build SQLPROJ package và lưu evidence vận hành.

## Đọc Trước

- [DE onboarding](../01_docs/onboarding/de_onboarding.md)
- [Glossary](../01_docs/glossary.md)
- [SQLPROJ CI/CD guide](../01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md)

## Operations Làm Gì?

```text
inspect refresh order
dry-run luồng sẽ chạy
trigger approved ad-hoc refresh
build SQLPROJ package
regenerate DQ/catalog operating package
giữ dependency order và auditability
```

## Safety Model

- Script mặc định nên chạy dry-run.
- Live execution cần `--execute`.
- Live execution cũng cần approval rõ trong cùng conversation.
- Không assume full refresh. Dùng manifest load type và `TableDictionary` contract hiện tại.
- Không bypass dependency order.

## Cấu Trúc Folder

| Folder | Ý nghĩa |
|---|---|
| `orchestration/main/` | Thứ tự chạy tổng cho các mart. |
| `orchestration/forecast_accuracy/` | Run order riêng cho Forecast Accuracy. |
| `orchestration/inventory_health/` | Run order riêng cho Inventory Health. |
| `operating_registry/` | Rollup DQ/catalog/lineage/run-order dạng JSON cho toàn repo. |
| `deployment/sqlproj/` | Build-only `.sqlproj`/`.dacpac` package cho handoff CI/CD. |
| `tools/` | Python helper cho dry-run, list jobs, approved trigger. |

## Lệnh Hay Dùng

Default approved ad-hoc mart refresh method: [Manifest Table Runner](operating_registry/manifest_table_runner.md).

Dry-run two active marts table-by-table:

```bash
python3 03_operations/tools/run_mart_tables.py \
  --manifest 03_operations/orchestration/forecast_accuracy/manifest.json \
  --manifest 03_operations/orchestration/inventory_health/manifest.json
```

Approved live two-mart table refresh:

```bash
python3 03_operations/tools/run_mart_tables.py \
  --manifest 03_operations/orchestration/forecast_accuracy/manifest.json \
  --manifest 03_operations/orchestration/inventory_health/manifest.json \
  --execute
```

Wave wrapper dry-run toàn bộ:

```bash
python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json
```

Wave wrapper dry-run một mart:

```bash
python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/forecast_accuracy/manifest.json
```

Wave wrapper live trigger:

```bash
python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json --execute
```

Current SQL Agent handoff uses 10 wrapper SP job steps: 2 shared prerequisite SPs, 3 Forecast Silver SPs, 3 Inventory Silver SPs, and 2 unchanged Gold SPs.

List recent jobs:

```bash
python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json --list-jobs
```

Regenerate DQ/catalog operating package:

```bash
python3 05_tools/04_operating_package/build_operating_package.py --repo-root .
```

Build SQLPROJ package:

```bash
cd 03_operations/deployment/sqlproj
./build_all.sh
```

## Wrapper Stored Procedures

Wrapper procedures là execution surface mà SQL Agent hoặc scheduler có thể gọi.

Chúng có nhiệm vụ:

```text
nhóm table theo mart/layer
sắp thứ tự dependency/wave
gọi đúng Enterprise ETL loader procedure
để AuditLog và TableDictionary ghi evidence
```

Chạy wrapper procedure là live Warehouse mutation. Cần approval rõ trong cùng conversation.

## Fabric REST Reference

Khi cần trigger Fabric Data Pipeline on-demand, Microsoft Fabric dùng endpoint:

```text
POST /v1/workspaces/{workspaceId}/dataPipelines/{dataPipelineId}/jobs/execute/instances
```

Job history:

```text
GET /v1/workspaces/{workspaceId}/dataPipelines/{dataPipelineId}/jobs/execute/instances
```

Với runtime hiện tại, wrapper procedures và Enterprise ETL loader contract là handoff chính. Fabric pipeline IDs vẫn được giữ làm context và fallback/legacy reference khi cần.
