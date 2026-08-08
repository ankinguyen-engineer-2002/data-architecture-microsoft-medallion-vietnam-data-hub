# DE Onboarding - Vận Hành Repo Và Fabric Runtime

Tài liệu này dành cho DE / Platform Operator, tức người giữ repo khớp với live Fabric và biến business logic thành luồng vận hành được.

DE là cầu nối giữa hai nguồn sự thật:

```text
Repo = nơi giải thích, lưu logic, manifest, DQ, SQLPROJ, runbook.
Fabric live = nơi object thật đang chạy và dữ liệu thật đang được load.
```

![Chu kỳ vận hành DE](de_operating_cycle.svg)

Mermaid source: [de_operating_cycle.mmd](de_operating_cycle.mmd)

## DE Sở Hữu Phần Nào?

| Khu vực | DE cần chịu trách nhiệm |
|---|---|
| Context discipline | Đọc và cập nhật `CONTEXT.md` sau thay đổi có ý nghĩa. |
| Live scan | Kiểm tra workspace, lakehouse, warehouse, SQL endpoint, semantic model, stored procedure khi cần. |
| Repo sync | Giữ `02_marts`, `03_operations`, `04_semantic`, JSON packages khớp với live truth. |
| Runtime contract | Bảo đảm `_Wrk.v_<TableName>` map đúng vào final table và wrapper procedure. |
| SQLPROJ package | Build và validate `.sqlproj` / `.dacpac` trước khi handoff deployment. |
| Orchestration handoff | Giữ manifest và wrapper order rõ ràng cho SQL Agent hoặc approved trigger. |
| DQ/catalog | Regenerate operating package và quản lý exception. |
| Smoke checks | Kiểm tra compile, loader log, DQ evidence, semantic/report compatibility. |
| Documentation | Giữ README, onboarding, architecture, runbook và context nhất quán. |

## Cách Nghĩ Nhanh Cho DE

```text
Repo là operating notebook.
Fabric là hệ thống thật.
SQLPROJ là package triển khai SQL object.
Enterprise ETL Framework là runtime loader.
Manifest và wrapper procedure định nghĩa thứ tự chạy.
AuditLog và TableDictionary chứng minh runtime đã làm gì.
```

## Workflow Chuẩn Cho DE

### Step 1 - Đọc Context Trước

Đọc theo thứ tự:

```text
AGENTS.md
CONTEXT.md
README.md
01_docs/glossary.md
01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md
03_operations/orchestration/main/manifest.yaml
```

Không lấy file archive làm current truth nếu tài liệu hiện tại không link rõ.

### Step 2 - Phân Loại Công Việc

Trước khi làm, phân loại request:

```text
documentation-only
DA SQL change
new mart onboarding
source/Bronze DQ audit
live Fabric scan
semantic compatibility check
wrapper/runtime change
SQLPROJ package update
approved ad-hoc refresh
```

Phân loại này quyết định có cần live scan, build SQLPROJ, regenerate DQ package, hay chuẩn bị scheduler handoff không.

### Step 3 - Scan Live Fabric Khi Cần Trạng Thái Hiện Tại

Live scan cần thiết khi câu hỏi phụ thuộc vào trạng thái hiện tại:

```text
workspace item IDs
lakehouse / warehouse tồn tại hay không
schema/table/view/procedure definition
TableDictionary mapping
AuditLog runtime evidence
semantic model bindings
pipeline/job status
```

Thứ tự tool ưu tiên:

```text
repo artifacts
Fabric/Power BI MCP tools nếu có
az rest
pyodbc với Entra token
repo scripts dưới 03_operations/tools và 05_tools
```

Không dùng tài liệu cũ để khẳng định live state nếu user đang hỏi "hiện tại".

### Step 4 - Sync Mart Package Trong Repo

Mỗi mart phải giữ cấu trúc:

```text
02_marts/<mart_name>/
  00_source_wrk/
  01_bronze/
  02_silver/
  03_gold/
  04_dq/
  05_catalog/
  99_history/
```

Khi DA đổi SQL:

```text
kiểm tra source tables
kiểm tra target final table schema
kiểm tra _Wrk view naming
kiểm tra load pattern cần dùng
kiểm tra semantic/report impact
update SQL file đúng layer
update DQ/catalog metadata
```

### Step 5 - Regenerate Operating Package

Sau khi sửa mart SQL/DQ/catalog:

```bash
python3 05_tools/04_operating_package/build_operating_package.py --repo-root .
```

Review output:

```text
02_marts/<mart>/04_dq/contracts/*.json
02_marts/<mart>/04_dq/runs/latest.json
02_marts/<mart>/05_catalog/*.json
03_operations/operating_registry/*.json
```

Các file này phục vụ cả người và AI agent. Đừng biến chúng thành ghi chú prose khó parse.

### Step 6 - Giữ Runtime Order Rõ Ràng

Thứ tự chạy đến từ:

```text
03_operations/orchestration/main/manifest.json
03_operations/orchestration/<mart_name>/manifest.json
03_operations/operating_registry/run_order.json
wrapper procedure SQL under 03_operations/orchestration/*/sql/
```

Thứ tự Enterprise ETL runtime nên rõ theo wave:

```text
shared/reference prerequisite wave
mart Silver waves
mart Gold dimensions/shared tables
mart Gold facts/serving tables
DQ và semantic smoke
```

Không đoán thứ tự theo alphabet.

### Step 7 - Build SQLPROJ Package

Build local trước khi handoff:

```bash
cd 03_operations/deployment/sqlproj
./build_all.sh
```

Build này validate SQL project packaging và sinh `.dacpac`. Nó không refresh dữ liệu và không tự publish lên Fabric.

Đọc thêm:

```text
01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md
03_operations/deployment/sqlproj/README.md
```

### Step 8 - Validate Runtime Bằng Evidence

Chọn check nhẹ nhất nhưng đủ chứng minh:

```text
local SQL diff
compile smoke
dry-run manifest
TableDictionary mapping check
AuditLog check
DQ package validation
semantic smoke
targeted row/grain validation khi user yêu cầu
```

Live refresh cần approval rõ:

```bash
python3 03_operations/tools/run_refresh.py --manifest 03_operations/orchestration/main/manifest.json --execute
```

Nếu chưa có approval, chỉ dry-run.

### Step 9 - Cập Nhật Docs Và Context

Mọi thay đổi có ý nghĩa cần để lại handoff:

```text
đã đổi gì
vì sao đổi
file nào thay đổi
live object nào đã scan hoặc mutate
verification đã chạy
rủi ro hoặc blocker
next step
```

Default context target:

```text
CONTEXT.md
```

Không tạo context song song hoặc dated context files.

## Checklist DE Cho Mart Mới

```text
[ ] DA handoff có source, grain, key, SQL, DQ, semantic impact.
[ ] Source tables tồn tại ở live source surface.
[ ] Mart folder tồn tại dưới 02_marts/<mart_name>.
[ ] Bronze source contract được document.
[ ] Silver và Gold SQL theo _Wrk view contract.
[ ] DQ rules và exceptions ở dạng machine-readable.
[ ] Catalog assets, lineage edges, run order được generate.
[ ] Wrapper procedure order rõ ràng.
[ ] SQLPROJ package build pass locally.
[ ] Deployment/publish owner và gate đã rõ trước khi publish.
[ ] Runtime smoke plan có trước live refresh.
[ ] Context và README links được cập nhật.
```

## Checklist DE Cho Operational Refresh

```text
[ ] Request nêu rõ mart/layer/scope.
[ ] Manifest dry-run đã được xem.
[ ] Live approval rõ trong cùng conversation.
[ ] Refresh chạy theo manifest/wrapper order.
[ ] AuditLog được kiểm tra sau execution.
[ ] TableDictionary không có bad/error mapping ngoài dự kiến.
[ ] DQ và semantic smoke chạy khi liên quan.
[ ] Context được cập nhật với kết quả và next step.
```

## Checklist DE Cho CI/CD Handoff

```text
[ ] SQL object changes nằm trong repo.
[ ] SQLPROJ build pass locally.
[ ] DeployReport/Script được review trước publish.
[ ] Destructive change risk được review rõ.
[ ] Target environment rõ.
[ ] Wrapper smoke plan sẵn sàng.
[ ] AuditLog/TableDictionary checks sẵn sàng.
[ ] Rollback hoặc fix-forward approach được ghi lại.
```

## Lỗi Hay Gặp

| Lỗi | Cách phòng tránh |
|---|---|
| README biến thành báo cáo số liệu | Đưa metrics vào context/artifacts, giữ README là guide. |
| DA đổi SQL nhưng thiếu DQ contract | Bắt buộc có grain, key, not-null, duplicate, freshness expectation. |
| `_Wrk` view và final table lệch tên | Validate `<SchemaName>_Wrk.v_<TableName>` trước build/handoff. |
| Nhầm SQLPROJ publish với refresh dữ liệu | CI/CD chỉ deploy object; runtime là wrapper + Enterprise ETL loader. |
| Manual refresh bỏ qua dependency order | Chỉ dùng manifest/wrapper order. |
| Dùng docs cũ để kết luận live state | Scan live Fabric khi current truth quan trọng. |
