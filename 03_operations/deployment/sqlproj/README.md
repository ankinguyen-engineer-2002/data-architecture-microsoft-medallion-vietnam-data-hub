# SQLPROJ Deployment Package

Folder này chứa package SQLPROJ build-only cho runtime hiện tại.

Nói đơn giản:

```text
SQLPROJ giúp build và review SQL object.
SQLPROJ không tự refresh dữ liệu.
Refresh dữ liệu vẫn do wrapper procedure + Enterprise ETL loader chạy.
```

## Có Những Project Nào?

| Project | Ý nghĩa |
|---|---|
| `Enterprise_Lakehouse_Reference` | Stub/reference phục vụ build cho Bronze source tables. |
| `ETL_Framework` | Framework metadata/audit tables, loader procedures, helper functions. |
| `SupplyChain_Processing_Warehouse` | Silver/processing final tables, `_Wrk` views, Silver wrappers. |
| `SupplyChain_Gold_Warehouse` | Gold/shared final tables, `_Wrk` views, Gold wrappers. |

## Build Tất Cả Project

```bash
./build_all.sh
```

Build tạo `.dacpac` artifacts để reviewer/CI/CD dùng. Kết quả build cụ thể nằm trong:

```text
_package/build_summary.json
_package/build_logs/*.log
```

## Khi Nào Dùng?

Dùng khi:

```text
SQL object thay đổi
cần kiểm tra project build được không
cần chuẩn bị handoff cho CI/CD reviewer
cần sinh artifact trước khi deploy có kiểm soát
```

Không dùng để:

```text
refresh dữ liệu
publish live nếu chưa có owner/gate
drop/recreate object có rủi ro mất dữ liệu
thay thế SQL Agent/runtime refresh
```

Operating guide:

- [SQLPROJ CI/CD Operating Guide](../../../01_docs/runbook/guides/sqlproj_cicd_operating_guide_for_da.md)

Runtime handoff vẫn là wrapper procedures được mô tả trong [ADR-010](../../../01_docs/decisions/ADR-010-enterprise-etl-wrapper-runtime-handoff.md).
