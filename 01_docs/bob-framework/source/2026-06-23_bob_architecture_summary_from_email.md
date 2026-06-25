# Bob Architecture Summary From Email

Nguon: user-curated summary image built from Bob email + attached docs.

## Files

- Image asset: [20260623_bob_architecture_summary_from_email.png](/Users/MAC/Documents/20260413_Fabric_Refactor_Architect/01_docs/bob-framework/source/assets/20260623_bob_architecture_summary_from_email.png)

## What this summary is good for

- Nhanh chóng nhìn ra intended repo/project tree của Bob:
  - shared `ETL_Framework`
  - `DW_Developer`
  - `Performance_Logs`
  - `SecurityAccess`
  - publish profiles
- Hiểu intended workspace split:
  - centralized `Enterprise_Data` cho Bronze + Silver
  - business-unit workspaces cho Gold + Analytics
- Thấy capability story Bob muốn nhấn mạnh:
  - audit logging
  - metadata + SLA
  - DQ
  - SCD2
  - incremental
  - deduplication
  - performance
  - security
- Thấy rõ phần Bob docs chưa mô tả đủ:
  - orchestration engine
  - dependency graph persistence
  - schedule / trigger
  - restart / checkpoint
  - retry / timeout / failure handling
  - emergency refresh workflow
  - monitoring dashboard

## How to use it in this repo

- Dùng như **intent map** cho discussion với Bob và cho việc đọc nhanh framework direction.
- Không dùng một mình để suy ra live contract.
- Khi phase planning/execution conflict với image này, ưu tiên:
  1. live verified repo/hub evidence
  2. `01_docs/Enterprise_Framework_Migration_Master_Plan.md`
  3. `CONTEXT.md`

## Scope lock reaffirmed

Cho migration hiện tại:

- thay runtime / control plane / framework services
- giu nguyen `Bronze / Silver / Gold`
- giu nguyen current views
- giu nguyen current business tables
- giu nguyen 04_semantic/report contract

Noi cach khac: **replace the operating framework, not the business/data product surface**.
