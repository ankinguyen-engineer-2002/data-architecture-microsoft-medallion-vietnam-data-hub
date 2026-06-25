# DA Onboarding - Thêm Hoặc Sửa Mart

Tài liệu này dành cho DA / Analytics Engineer, tức người hiểu business logic, report requirement và ý nghĩa dữ liệu.

DA không cần tự vận hành toàn bộ Fabric infrastructure. Điều quan trọng là DA phải mô tả đủ rõ logic, source, grain, key, DQ và semantic impact để DE có thể đưa logic đó vào hệ thống BOB runtime một cách an toàn.

![Luồng onboarding DA](da_onboarding_flow.svg)

Mermaid source: [da_onboarding_flow.mmd](da_onboarding_flow.mmd)

## DA Sở Hữu Phần Nào?

| Khu vực | DA cần chịu trách nhiệm |
|---|---|
| Business question | Bảng/mart này trả lời câu hỏi nghiệp vụ gì? |
| Source contract | Source nào được dùng, source nào không còn active. |
| Grain | Một dòng dữ liệu đại diện cho điều gì. |
| Key | Cột nào là business key, cột nào bắt buộc không null. |
| Date logic | Snapshot date, transaction date, fiscal/calendar logic, freshness expectation. |
| SQL logic | Logic Bronze/Silver/Gold hoặc thay đổi SQL nghiệp vụ. |
| DQ expectation | Rule về null, duplicate, freshness, accepted values, exception. |
| Semantic impact | Ảnh hưởng tới semantic model, measure, relationship, report. |
| Handoff | Ghi chú đủ rõ để DE build, validate và vận hành. |

## DA Không Cần Sở Hữu Phần Nào?

| Khu vực | Ai thường sở hữu |
|---|---|
| Setup scheduler / SQL Agent job | DE / BOB operations |
| Publish SQLPROJ lên environment | DE / platform owner / reviewer |
| Permission Fabric workspace | DE / platform owner |
| Nội bộ BOB loader | BOB framework owner / DE |
| Quyết định live refresh production | Operations owner |

## Workflow Chuẩn Cho DA

### Step 1 - Bắt Đầu Từ Bản Đồ Repo

Đọc:

```text
README.md
00_CONTEXT/current.md
02_marts/README.md
01_docs/glossary.md
```

`00_CONTEXT/current.md` dùng để biết trạng thái mới nhất. Không copy số liệu audit cũ vào tài liệu thiết kế mới nếu số liệu đó chỉ là bằng chứng tại một thời điểm.

### Step 2 - Xác Định Scope

Xác định request thuộc loại nào:

```text
mart mới
bảng mới trong mart hiện có
sửa bảng hiện có
chỉ đổi semantic/report
chỉ thêm hoặc sửa DQ rule
```

Khi mô tả, dùng placeholder rõ:

```text
<mart_name>
<source_domain>
<source_table>
<silver_schema>
<silver_table>
<gold_schema>
<gold_table>
```

### Step 3 - Ghi Source Contract

Với mỗi source table, DA nên ghi:

```text
source system / lakehouse / warehouse
schema.table
ý nghĩa business
freshness mong đợi
grain mong đợi
duplicate có được phép không
null ở key có được phép không
filter bắt buộc
source đang active hay chỉ còn historical
```

Nơi lưu:

```text
02_marts/<mart_name>/01_bronze/
02_marts/<mart_name>/04_dq/contracts/bronze_sources.json
```

Nếu chưa chắc source nào đúng, ghi là open question. Không đoán.

### Step 4 - Định Nghĩa Grain Và Key

Trước khi viết SQL, hãy viết được đoạn này:

```text
Table: <target_table>
Một dòng đại diện cho: <business grain>
Natural key: <columns>
Cột bắt buộc not-null: <columns>
Cột date/freshness: <column or none>
Duplicate rule: <không cho phép / cho phép / cần business exception>
```

Grain và key là nền tảng cho DQ, semantic relationship và incremental load.

### Step 5 - Đặt SQL Vào Đúng Layer

Cấu trúc mart:

```text
02_marts/<mart_name>/
  01_bronze/
  02_silver/
  03_gold/
```

Silver và Gold đi theo pattern BOB:

```text
Final table:
  <SchemaName>.<TableName>

Source/work view:
  <SchemaName>_Wrk.v_<TableName>
```

SQL của DA nên làm rõ:

```text
output columns
business calculation
join logic
filter logic
deduplication assumption
date/snapshot logic
grain có bị thay đổi không
```

### Step 6 - Viết DQ Rule

Checklist tối thiểu:

```text
key không null
grain uniqueness
full-row duplicate nếu source kỳ vọng unique vật lý
freshness nếu có date/load timestamp đáng tin cậy
accepted values cho status/type quan trọng
referential check với dimension quan trọng
known exception kèm owner hoặc câu hỏi cần xác nhận
```

Nơi lưu:

```text
02_marts/<mart_name>/04_dq/contracts/rules.json
02_marts/<mart_name>/04_dq/contracts/exceptions.json
```

Không giấu exception trong SQL. Exception cần được ghi rõ để reviewer hiểu.

### Step 7 - Ghi Semantic Impact

Ghi rõ:

```text
có thêm bảng semantic không
có thêm/xóa/rename cột không
measure nào bị ảnh hưởng
relationship nào bị ảnh hưởng
report page nào có thể bị ảnh hưởng
có backward compatibility issue không
```

Nơi lưu:

```text
02_marts/<mart_name>/05_catalog/semantic_bindings.json
04_semantic/
```

### Step 8 - Bàn Giao Cho DE

DA handoff nên có:

```text
mart name
business owner
source tables
target Silver/Gold tables
grain và key
SQL files thay đổi
DQ rules và exceptions
semantic/report impact
refresh cadence mong muốn
rủi ro hoặc câu hỏi đang mở
```

DE sẽ kiểm tra live Fabric, update SQLPROJ, xác nhận wrapper/runtime order, build package và chuẩn bị handoff vận hành.

## Checklist Trước Khi Gửi Review

```text
[ ] Source tables đã rõ active/historical.
[ ] Grain được viết bằng ngôn ngữ business.
[ ] Key và not-null columns đã rõ.
[ ] SQL nằm đúng layer trong mart package.
[ ] DQ rule được viết thành contract, không chỉ ghi prose.
[ ] Known exceptions có owner hoặc câu hỏi.
[ ] Semantic/report impact đã rõ.
[ ] Không nhét số liệu audit tại một thời điểm vào template docs.
```

## Câu Hỏi DA Nên Hỏi DE

```text
Source này hiện có trên live Fabric chưa?
Tên schema/table đã đúng chuẩn BOB chưa?
_Wrk view có map đúng với final table không?
Bảng này nên chạy ở wave nào?
Load pattern là full refresh, incremental append, incremental merge, SCD2 hay date-range?
DQ smoke nào cần pass trước khi semantic/report validation?
```
