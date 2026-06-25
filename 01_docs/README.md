# Docs

Folder này là thư viện kiến thức chính của repo.

Nếu root `README.md` là bản đồ tổng quan, thì `01_docs/` là nơi giải thích sâu hơn: kiến trúc, onboarding, tài liệu Enterprise ETL, quyết định kiến trúc, runbook và kế hoạch migration.

## Nên Đọc Theo Thứ Tự Nào?

| Bạn cần gì? | Đọc ở đâu? |
|---|---|
| Mới vào repo, chưa hiểu bức tranh | [../README.md](../README.md) |
| Không hiểu thuật ngữ | [glossary.md](glossary.md) |
| DA cần add/sửa mart | [onboarding/da_onboarding.md](onboarding/da_onboarding.md) |
| DE cần vận hành repo/live Fabric | [onboarding/de_onboarding.md](onboarding/de_onboarding.md) |
| Muốn hiểu kiến trúc hiện tại | [architecture/current/README.md](architecture/current/README.md) |
| Muốn hiểu tài liệu Enterprise ETL được áp dụng ra sao | [enterprise-etl-framework/README.md](enterprise-etl-framework/README.md) |
| Muốn xem quyết định kiến trúc | [decisions/](decisions/) |
| Muốn xem runbook và evidence | [runbook/](runbook/) |

## Cấu Trúc Folder

| Folder | Ý nghĩa |
|---|---|
| [onboarding/](onboarding/) | Hướng dẫn theo vai trò DA và DE. |
| [architecture/current/](architecture/current/) | Kiến trúc hiện tại sau Phase 1 và các sơ đồ. |
| [enterprise-etl-framework/](enterprise-etl-framework/) | Tài liệu Enterprise ETL gửi, kèm cách hiểu và áp dụng vào SupplyChain. |
| [decisions/](decisions/) | ADR, tức quyết định kiến trúc quan trọng và lý do chọn. |
| [plans/](plans/) | Kế hoạch triển khai/migration. |
| [runbook/](runbook/) | Hướng dẫn vận hành, artifacts, script hỗ trợ và evidence. |

## Điều Quan Trọng Cần Nhớ

```text
Current architecture nằm ở architecture/current.
Archive chỉ là lịch sử.
Context là nhật ký mới nhất.
Mart SQL và DQ contract nằm ở 02_marts.
Operations manifest và SQLPROJ nằm ở 03_operations.
```

## Các Quyết Định Và Guide Quan Trọng

- [ADR-009: Enterprise `_Wrk` View Contract For Curated Warehouses](decisions/ADR-009-enterprise-wrk-view-contract.md)
- [ADR-010: Enterprise ETL Wrapper Runtime Handoff For Phase 1](decisions/ADR-010-enterprise-etl-wrapper-runtime-handoff.md)
- [SQLPROJ And CI/CD Research](runbook/guides/sqlproj_cicd_research.md)
- [SQLPROJ CI/CD Operating Guide For DA/DE](runbook/guides/sqlproj_cicd_operating_guide_for_da.md)
