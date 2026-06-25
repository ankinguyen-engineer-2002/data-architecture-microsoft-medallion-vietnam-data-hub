# Kiến Trúc Hiện Tại

Folder này mô tả kiến trúc hiện tại sau Phase 1 BOB ETL Framework migration.

Mục tiêu của folder này là giúp người đọc hiểu:

```text
dữ liệu đi từ đâu tới đâu
business layers được giữ lại như thế nào
BOB runtime được gắn vào đâu
_Wrk view, final table, wrapper procedure và loader liên kết ra sao
CI/CD chỉ deploy object, không thay runtime refresh
```

## Nên Đọc Theo Thứ Tự

1. [../../glossary.md](../../glossary.md) - giải thích thuật ngữ.
2. [final_bob_runtime_architecture.md](final_bob_runtime_architecture.md) - giải thích kiến trúc chi tiết.
3. [final_bob_runtime_architecture.svg](final_bob_runtime_architecture.svg) - hình kiến trúc chính.
4. [../../Enterprise_Framework_Migration_Master_Plan.md](../../Enterprise_Framework_Migration_Master_Plan.md) - master plan và trạng thái Phase 1.

## Sơ Đồ Hỗ Trợ Root README

| Sơ đồ | Mermaid source | Dùng để hiểu gì? |
|---|---|---|
| [readme_operating_map.svg](readme_operating_map.svg) | [readme_operating_map.mmd](readme_operating_map.mmd) | Repo có những khu vực nào và nên đi từ đâu. |
| [readme_mart_package_anatomy.svg](readme_mart_package_anatomy.svg) | [readme_mart_package_anatomy.mmd](readme_mart_package_anatomy.mmd) | Một mart được đóng gói trong repo như thế nào. |
| [readme_bob_loader_contract.svg](readme_bob_loader_contract.svg) | [readme_bob_loader_contract.mmd](readme_bob_loader_contract.mmd) | `_Wrk` view, final table, wrapper và BOB loader liên kết ra sao. |
| [readme_cicd_to_runtime_flow.svg](readme_cicd_to_runtime_flow.svg) | [readme_cicd_to_runtime_flow.mmd](readme_cicd_to_runtime_flow.mmd) | CI/CD deploy SQL object rồi bàn giao sang runtime refresh như thế nào. |
| [readme_full_lifecycle.svg](readme_full_lifecycle.svg) | [readme_full_lifecycle.mmd](readme_full_lifecycle.mmd) | Vòng đời từ DA logic tới DE validation, CI/CD, runtime và evidence. |

## Trạng Thái Hiện Tại

- Phase 1 đã hoàn tất theo hướng BOB-aligned cho scope SupplyChain hiện tại.
- Bronze/Silver/Gold business layers và semantic/report contract được giữ.
- Runtime chính là `ETL_Framework.DW_Developer` cộng với wrapper stored procedures.
- Phase 2 đang deferred, không tự khởi động nếu chưa có yêu cầu mới.

Số liệu audit, duration, row count và closeout evidence không đặt ở README kiến trúc. Xem [../../../00_CONTEXT/current.md](../../../00_CONTEXT/current.md) hoặc runbook artifacts khi cần bằng chứng cụ thể.
