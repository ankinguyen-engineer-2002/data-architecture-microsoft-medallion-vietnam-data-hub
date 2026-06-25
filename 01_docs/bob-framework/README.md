# BOB Framework Guide

Folder này lưu tài liệu BOB gửi và cách repo này hiểu/áp dụng vào SupplyChain Phase 1.

Đọc nhanh:

```text
BOB docs = tiêu chuẩn và gợi ý kiến trúc.
Live EnterpriseData evidence = cách họ đang vận hành thật.
Repo này áp dụng phần đã verify được để giữ business layer nhưng chuẩn hóa runtime.
```

## Tài Liệu Gốc

Tài liệu gốc nằm trong [source/](source/):

- `ETL_FRAMEWORK_GUIDE.md`
- `FABRIC_ARCHITECTURE_AND_STANDARDS.md`
- `SQLPROJ_BEST_PRACTICES.md`
- `2026-06-23_bob_architecture_summary_from_email.md`
- `2026-06-23_enterprisedata_data_feed_alert_email_analysis.md`
- sample alert email `.msg`

## Cách Đọc Tài Liệu BOB

Không copy object một cách máy móc. Thứ tự ưu tiên khi có khác biệt:

1. Live evidence đã reverse-engineer từ EnterpriseData/BOB hub.
2. Verification artifacts của Phase 1 trong repo này.
3. BOB guide docs và email notes.
4. Tài liệu cũ v8/v9/v10 trong archive.

Lý do:

- BOB docs có thể mô tả pattern hoặc object lý tưởng.
- Live hub cho thấy runtime thật đang dùng loader procedures, wrapper procedures, `TableDictionary`, `AuditLog`, `_Wrk` và `_LOAD`.
- SupplyChain Phase 1 chọn theo live runtime contract, đồng thời giữ các concept quan trọng của BOB: audit, metadata, SLA/freshness, `_Wrk`, managed refresh.

## Concept BOB Được Áp Dụng Ở Đây

| Concept | Ý nghĩa trong SupplyChain repo |
|---|---|
| Shared `ETL_Framework` | Framework runtime chính cho scope SupplyChain hiện tại. |
| `DW_Developer.TableDictionary` | Registry metadata cho table, source view, refresh method, SLA/freshness. |
| `DW_Developer.AuditLog` | Evidence runtime cho loader start/complete/error. |
| `TableDictionary_UpdateLog` | Lịch sử update metadata. |
| `_Wrk` | Schema chứa source/work view, ví dụ `<SchemaName>_Wrk.v_<TableName>`. |
| `_LOAD` | Bảng tạm do loader tạo trong quá trình load. Không phải business output. |
| Email alerting | Capability trong BOB ecosystem; tích hợp alert channel đầy đủ là backlog vận hành. |
| Restart from failure | BOB loader ecosystem hỗ trợ resume/restart; repo lưu manifest để chạy lại theo dependency order. |

## Kết Quả Phase 1

Phase 1 đã đưa runtime hiện tại về hướng BOB-aligned:

- local `ETL_Framework` là framework path chính
- asset Bronze/Silver/Gold hiện tại được register/backfill metadata
- `_Wrk` wrapper coverage được canonicalize
- business table/view/semantic surface được giữ
- `Meta.usp_GenericLoad` chỉ còn là fallback/rollback, không phải runtime chính

## Backlog Không Chặn Phase 1

- xác nhận owner enterprise schedule
- tích hợp email alert channel
- automation rộng hơn cho semantic/report smoke
- Phase 2 cho DQ/lineage/wave planner nâng cao
- production promotion path sang EnterpriseData hub
- SQLPROJ/CI/CD adoption hoàn chỉnh
