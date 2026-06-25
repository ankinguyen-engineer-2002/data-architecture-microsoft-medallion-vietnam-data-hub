# SQLPROJ CI/CD Operating Guide

> Người đọc: DA, Analytics Engineer, DE, Enterprise ETL/US reviewer  
> Phạm vi: cách triển khai SQL object cho Microsoft Fabric Warehouse trong repo SupplyChain  
> Trạng thái repo: build-only validation package, không live publish mặc định

Tài liệu này giải thích CI/CD theo ngôn ngữ dễ hiểu. Mục tiêu là để DA/DE/reviewer hiểu: SQL code đi từ repo lên Fabric như thế nào, và vì sao việc đó khác với refresh dữ liệu.

## Tóm Tắt 1 Phút

Trong repo này có 2 luồng khác nhau:

```text
Luồng 1 - CI/CD:
  kiểm tra và deploy SQL object như schema, table, view, stored procedure

Luồng 2 - ETL runtime:
  chạy wrapper procedure và Enterprise ETL loader để nạp dữ liệu vào final table
```

Nói cách khác:

```text
CI/CD trả lời:
  "Object trong warehouse nên trông như thế nào?"

ETL runtime trả lời:
  "Dữ liệu trong object đó đã được load đúng chưa?"
```

## Bức Tranh Tổng Quan

```text
SQL files trong Git
  -> build .sqlproj
  -> tạo .dacpac
  -> sinh DeployReport / Script
  -> reviewer approve
  -> publish SQL objects
  -> scheduler/wrapper chạy ETL
  -> Enterprise ETL loader load dữ liệu
  -> AuditLog + TableDictionary + DQ + semantic smoke
```

Điểm quan trọng:

```text
.dacpac không chứa data rows.
.dacpac chỉ chứa định nghĩa object.
Refresh dữ liệu vẫn phải chạy bằng wrapper procedure + Enterprise ETL loader.
```

## Glossary Ngắn

| Thuật ngữ | Nghĩa dễ hiểu |
|---|---|
| CI | Continuous Integration. Tự động kiểm tra code/build trước khi merge/deploy. |
| CD | Continuous Delivery/Deployment. Đưa artifact đã review lên environment có kiểm soát. |
| SQLPROJ | Project đóng gói SQL files thành model build được. |
| `.dacpac` | Package sinh ra từ SQLPROJ, chứa định nghĩa object, không chứa dữ liệu. |
| Artifact | Output của build, ví dụ `.dacpac` hoặc build log. |
| DacFx | Tooling của Microsoft dùng để so sánh/build/publish `.dacpac`. |
| SqlPackage | CLI dùng `.dacpac` để tạo script, deploy report hoặc publish. |
| DeployReport | Báo cáo cho biết publish sẽ thay đổi object gì. |
| Publish | Apply object changes lên warehouse. Đây là live mutation. |
| Smoke test | Kiểm tra nhanh sau deploy/refresh để biết hệ thống còn chạy không. |

Đọc thêm glossary chung: [../../glossary.md](../../glossary.md)

## CI Là Gì?

CI là bước kiểm tra tự động khi có người đề xuất thay đổi code.

Trong repo này, CI thường kiểm tra:

```text
SQL syntax có hợp lệ không
schema/table/view reference có tồn tại không
column reference có đúng không
stored procedure có model được không
cross-database reference có cấu hình đúng không
.sqlproj build có pass không
```

CI bắt được lỗi kỹ thuật, ví dụ:

```text
view gọi nhầm cột không tồn tại
schema reference sai
procedure syntax sai
project thiếu external reference
```

CI không chứng minh business logic đúng.

## CD Là Gì?

CD là đường triển khai object đã build và review.

Trong data platform enterprise, nên hiểu CD là **Continuous Delivery**:

```text
CI pass
  -> artifact được tạo
  -> DeployReport/Script được review
  -> người có quyền approve
  -> publish lên DEV / TEST / PROD
```

Không nên mặc định auto publish production nếu chưa có đầy đủ gate, owner và rollback plan.

## SQLPROJ Package Trong Repo Này

Package nằm ở:

```text
03_operations/deployment/sqlproj/
```

Gồm:

```text
ETL_Framework/
Enterprise_Lakehouse_Reference/
SupplyChain_Processing_Warehouse/
SupplyChain_Gold_Warehouse/
```

Build local:

```bash
cd 03_operations/deployment/sqlproj
./build_all.sh
```

Kết quả build nằm ở:

```text
03_operations/deployment/sqlproj/_package/build_summary.json
03_operations/deployment/sqlproj/_package/build_logs/
```

Repo hiện dùng package này để validate/build và handoff review. Không dùng để live publish nếu chưa có approval rõ.

## Luồng Thay Đổi SQL Object Theo Template

Giả sử DA/DE muốn thêm hoặc sửa một logic trong mart:

```text
Mart:
  <mart_name>

Layer:
  Silver hoặc Gold

Target table:
  <SchemaName>.<TableName>

Source/work view:
  <SchemaName>_Wrk.v_<TableName>

Change:
  <mô tả thay đổi, additive hay breaking>
```

### Step 1 - DA/DE Cập Nhật SQL Trong Repo

Sửa đúng file trong mart package hoặc SQLPROJ source.

Mục tiêu:

```text
final table definition có cột/shape đúng
_Wrk view produce đúng output columns
không đụng mart/layer ngoài scope
```

Sau step này:

```text
Git changed: yes
Live Fabric changed: no
Data refreshed: no
```

### Step 2 - Mở PR / Review

Reviewer cần kiểm tra:

```text
scope có rõ không
change additive hay breaking
datatype có hợp lý không
_Wrk view và final table có khớp column không
semantic/report có bị ảnh hưởng không
DQ rule có cần update không
```

### Step 3 - CI Build SQLPROJ

CI hoặc local command chạy:

```bash
dotnet build <Warehouse>.sqlproj -c Release
```

Nếu build fail, sửa trước khi deploy.

Build pass chỉ có nghĩa là object model compile được. Nó chưa chứng minh dữ liệu đúng.

### Step 4 - Tạo `.dacpac`

Build tạo artifact:

```text
<Warehouse>/bin/Release/<Warehouse>.dacpac
```

`.dacpac` chứa object definitions, không chứa data rows.

### Step 5 - Sinh DeployReport / Script

Trước publish, release process so sánh:

```text
compiled .dacpac
vs
target Fabric Warehouse
```

Reviewer phải nhìn được:

```text
object nào sẽ CREATE/ALTER
có DROP/TRUNCATE/destructive ALTER không
có schema ngoài scope bị ảnh hưởng không
data-loss guard có bật không
```

### Step 6 - Approve Và Publish

Publish là live mutation vì nó thay đổi object trong warehouse.

Không publish nếu thiếu:

```text
reviewer approval
target environment rõ
deploy report/script đã xem
data-loss guard
rollback hoặc fix-forward plan
```

Sau publish:

```text
object definition changed: yes
data refreshed: not yet, trừ khi có post-deploy runtime step
```

### Step 7 - Chạy Wrapper Smoke

Chạy wrapper liên quan để nạp dữ liệu bằng definition mới.

Template:

```sql
EXEC [<Warehouse>].[dbo].[Usp_Refresh_<MartName>_<LayerName>];
```

Wrapper sẽ gọi Enterprise ETL loader, Enterprise ETL loader đọc:

```text
<SchemaName>_Wrk.v_<TableName>
```

rồi ghi vào:

```text
<SchemaName>.<TableName>
```

### Step 8 - Kiểm Tra Runtime Evidence

Kiểm tra:

```text
AuditLog có Process Start/Complete và không có error không
TableDictionary có map đúng schema/table/source view không
DQ check có pass hoặc exception rõ không
semantic/report smoke có pass không
```

Sample query template:

```sql
SELECT TOP 50
    *
FROM [ETL_Framework].[DW_Developer].[AuditLog]
ORDER BY LogDate DESC;
```

```sql
SELECT
    *
FROM [ETL_Framework].[DW_Developer].[TableDictionary]
WHERE SchemaName = '<SchemaName>'
  AND TableName = '<TableName>';
```

## CI Bắt Được Gì?

CI build giỏi bắt lỗi kỹ thuật:

```text
SQL syntax error
missing table reference
missing column reference
wrong cross-database reference
schema not included in project
procedure/view cannot be modeled
target platform misconfigured
```

## CI Không Bắt Được Gì?

CI không chứng minh:

```text
row count đúng
freshness đúng
grain unique
không có duplicate
key không null
metric definition được business approve
report visual nhìn đúng
query performance đủ tốt
```

Các thứ đó cần:

```text
DQ audit
wrapper run
AuditLog check
TableDictionary check
queryinsights check
semantic smoke
business validation
```

## Release Gate Tối Thiểu

```text
1. PR review
   Scope rõ, chỉ đúng mart/layer bị ảnh hưởng.

2. CI build
   Relevant .sqlproj build pass.

3. DeployReport / Script review
   Không có destructive change ngoài ý muốn.

4. Publish approval
   Owner/reviewer approve target environment.

5. Wrapper smoke
   Chạy impacted wrapper theo đúng order.

6. Runtime evidence
   AuditLog complete/no-error.
   TableDictionary map đúng contract.

7. Data validation
   Kiểm tra row count/null/duplicate/freshness/metric theo scope.

8. Semantic smoke
   Model/report quan trọng không bị hỏng.

9. Promotion approval
   TEST/PROD chỉ sau khi DEV evidence sạch.
```

## DA Checklist Trước Khi Yêu Cầu Deploy SQL Change

DA nên trả lời được:

```text
Mart nào?
Layer nào: Silver hay Gold?
Table nào?
_Wrk view nào?
Change additive hay breaking?
Semantic model có cần update không?
Sample query nào chứng minh logic?
Business rule nào validate kết quả?
DQ rule nào cần thêm/sửa?
```

## DE Checklist Trước Khi Publish / Handoff

DE nên kiểm tra:

```text
SQL file đúng folder/layer
_Wrk view map đúng final table
SQLPROJ build pass
DeployReport/Script không có destructive surprise
wrapper smoke plan rõ
AuditLog/TableDictionary check sẵn sàng
DQ/semantic smoke plan rõ
context update plan rõ
```

## Không Nên Làm

Không coi `.dacpac` build success là bằng chứng dữ liệu đúng.

Không publish PROD nếu thiếu:

```text
deploy report
script review
data-loss guard
approval
runtime smoke
rollback/fix-forward plan
```

Không để CI/CD thay SQL Agent runtime:

```text
CI/CD deploys objects.
SQL Agent/Enterprise ETL executes ETL.
```

Không bật tùy tiện:

```text
DropObjectsNotInSource=True
BlockOnPossibleDataLoss=False
automatic PROD publish
destructive post-deployment scripts
```

## Source References

- Enterprise ETL guide: `01_docs/enterprise-etl-framework/source/SQLPROJ_BEST_PRACTICES.md`
- Enterprise ETL guide: `01_docs/enterprise-etl-framework/source/FABRIC_ARCHITECTURE_AND_STANDARDS.md`
- Repo research: `01_docs/runbook/guides/sqlproj_cicd_research.md`
- Microsoft Learn: <https://learn.microsoft.com/fabric/data-warehouse/develop-warehouse-project>
- Microsoft Learn: <https://learn.microsoft.com/sql/tools/sql-database-projects/sql-projects-automation?view=sql-server-ver17>
- Microsoft Learn: <https://learn.microsoft.com/sql/tools/sql-database-projects/concepts/database-references?view=sql-server-ver17>
