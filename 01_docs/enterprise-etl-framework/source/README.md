# Enterprise ETL Guide

Tập này lưu:

- tài liệu gốc Enterprise ETL gửi (`ETL_FRAMEWORK_GUIDE.md`, `FABRIC_ARCHITECTURE_AND_STANDARDS.md`, `SQLPROJ_BEST_PRACTICES.md`)
- user-curated overview từ email/tài liệu Enterprise ETL
- sample alert email Enterprise ETL gửi để chứng minh SLA/data-feed email output thật
- asset hình tóm tắt để future session đọc nhanh hơn

## Scope note

- Đây là **design intent / canonical guide** cho framework Enterprise ETL.
- Khi triển khai Phase 1 trong repo này, source-of-truth để execute vẫn là:
  - live verified hub/local inventory
  - reverse-engineered evidence đã lưu trong repo
  - `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
- Không được coi các tên object trong guide là 1:1 live contract nếu chưa match với evidence.

## Current files

- `ETL_FRAMEWORK_GUIDE.md`
- `FABRIC_ARCHITECTURE_AND_STANDARDS.md`
- `SQLPROJ_BEST_PRACTICES.md`
- `2026-06-23_enterprise_etl_architecture_summary_from_email.md`
- `2026-06-23_enterprisedata_data_feed_alert_email_analysis.md`
- `EnterpriseData - ETL_Framework DataWarehouse Data Feed Alert_ 0.2857% behind (1 of 350).msg`
- `assets/20260623_enterprise_etl_architecture_summary_from_email.png`
