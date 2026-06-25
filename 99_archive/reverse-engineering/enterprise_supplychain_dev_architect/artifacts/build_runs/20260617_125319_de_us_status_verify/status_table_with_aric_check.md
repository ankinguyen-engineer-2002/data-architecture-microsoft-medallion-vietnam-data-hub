# DE US status table — with Aric checking (2026-06-17)

Evidence pack:
- `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260617_125319_de_us_status_verify/results.md`
- `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260617_125319_de_us_status_verify/results.json`

Legend:
- `[V]` = Verified (đã có SQL evidence)
- `[NV]` = Need-verify (thiếu evidence để kết luận đúng issue)
- `[L]` = Likely (phán đoán có cơ sở nhưng chưa đủ chứng minh)

| Dataset / Table | Issue Raise Ban Đầu | Phân loại | Trạng thái hiện tại | Aric checking |
|---|---|---|---|---|
| `SupplyChain_Enh_1.DemandForecastSnapshotDaily` | Snapshot chậm 85 ngày (MAX Snapshot = 2026-02-24) | ✅ Hoàn thành | Đã full load và refresh thành công | [V] `SupplyChain_Enh_1` schema không còn; trong `SupplyChain_Enh` có 2 bảng gần giống: (1) `DemandForecastSnapshotDaily` max `dfcSnapshot` = 2026-06-02 (fresh hơn) (2) `DemandForecastSnapshotDaily_1` max `dfcSnapshot` = 2025-10-31 (stale). |
| `SupplyChain_DW.DimAFIWarehouses` | Data freshness (194 ngày stale) | ✅ Hoàn thành | Đã tạo Gold View và refresh | [NV] ✓ Exists in `Enterprise_Lakehouse`; không có `LoadDT/UpdateTS` để chứng minh stale-days |
| `Customers.AccountMaster` | Data freshness (169 ngày stale) | ✅ Hoàn thành | Done | [V] ✓ Exists; max `cmaTerritoryChangeDate` = 2026-06-15 (business attr, không phải LoadDT) |
| `Customers.ShippingLocations` | Data freshness (169 ngày stale) | ✅ Hoàn thành | Done | [V] ✓ Exists; max `cslTerritoryEffectivityDate` = 2026-06-16 (business attr, không phải LoadDT) |
| `Wholesale_ProductSourcing_AFI.CustomerGrouping` | Data freshness (161 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; chưa có evidence freshness (no load column) |
| `Wholesale_Codis_AFI.COMAST` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; chưa có evidence freshness (no load column) |
| `Wholesale_Codis_AFI.Codatan` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; các date field dạng số, max = 20391225 (future) → không dùng làm freshness |
| `Wholesale_Codis_AFI.EXTORD` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `HDATE` max = 20260617 (numeric date) |
| `Wholesale_Codis_AFI.EXTORIT` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; numeric date max = 20391225 (future) |
| `Wholesale_Codis_AFI.AAORDTYP` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `OTDATE` max = 20210317 (không đủ chứng minh stale-days metric) |
| `Manufacturing_ProductionPlanning_AFI.MOMAST` | Data freshness (169 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `ODUDT` max = 1261231 (CYYMMDD) |
| `Manufacturing_Inventory_AFI.TFRDTL` | Data freshness (161 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `DETADT` max = 0 (not usable) |
| `Manufacturing_Inventory_AFI.TFRHDR` | Data freshness (161 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `HARRDT` max = 20280619 (future; không chứng minh freshness) |
| `Wholesale_Codis_AFI.AshleyWarehouseMaster` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; chưa có evidence freshness (no load column) |
| `Wholesale_Purchasing_AFI.ATPSUM` | Data freshness (98 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; chưa có evidence freshness (no load column) |
| `ItemMaster_AFI.ITBEXT` | Data freshness (71 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `MFSDT` max = 20391101 (future) |
| `ItemMaster_AFI.ITMRVA` | Data freshness (66 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `BZBLDT` max = 1060826 (numeric date) |
| `ItemMaster_AFI.ITEMBL` | Data freshness (58 ngày stale) | ✅ Hoàn thành | Done | [NV] ✓ Exists; `LACDT` max = 1800305 (numeric date) |
| `Wholesale_Purchasing_AFI.ATPSUM (APWK01)` | Data issue được raise trong review | ✅ Hoàn thành | Done | [NV] Chưa rõ “APWK01” là object/logic nào (view/filter/column); cần định nghĩa check |
| `SupplyChain_Enh.CurFcstSnapshotWeekly` | Cần pull/load table | ✅ Hoàn thành | Validation mới xác nhận không còn issue | [V] ✓ Exists; max `SnapshotDate` = 2026-06-15 |
| `SalesHistory_AFI_Enh.InvoiceHeader` | Thiếu dữ liệu lịch sử (~4M vs ~25M records) | 🟡 Cần Analytics kiểm tra lại | DE đã chạy full history load | [V] ✓ Exists; `COUNT_BIG(*)=62,441,183`; `MIN(InvoiceDate)=2019-05-22`, `MAX(InvoiceDate)=2026-06-16`. (Legacy `SalesHistory_AFI.InvoiceHeader` vẫn có ~4,006,374 rows; `MIN=2025-12-14`.) |
| `SalesHistory_AFI_Enh.InvoiceDetail` | (Schema change) kiểm tra coverage/history | 🟡 Cần Analytics kiểm tra lại | DE nói đã update schema sang `SalesHistory_AFI_enh` | [V] ✓ Exists; `COUNT_BIG(*)=285,442,399`; `MIN(InvoiceDate)=2017-08-10`, `MAX(InvoiceDate)=2026-06-16`. (Legacy `SalesHistory_AFI.InvoiceDetail` ~126,963,516 rows.) |
| `SupplyChain_Enh.PurchaseOrderSnapshot` | Chưa được promote lên Enterprise Lakehouse | 🟡 Cần Analytics kiểm tra lại | DE đã tạo table, procedure và daily load | [V] ✓ Exists; max `posSnapshot` = 2026-06-16 → mô tả “chưa promote” không khớp hiện trạng |
| `SupplyChain_Enh.ATPWeekEnding` | Duplicate records + AFIFinanceDivision null | 🟡 Cần Analytics kiểm tra lại | DE đã load table nhưng validation mới vẫn phát hiện duplicate/null | [V] Re-scan 2026-06-18: `MAX(WeekEnding)=2026-07-25` (đã vượt 06/2026). `AFIFinanceDivision` NULL exists. Duplicate exists ở nhiều grain guess; cần chốt canonical dedupe key. Evidence: `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260618_142034_de_us_table2_scan/results.md`. |
| `Manufacturing_Inventory_AFI.IMHIST` | Future-dated records | 🟠 Cần xác nhận nghiệp vụ | DE xác nhận source cũng có future-date records | [V] future-dated on `TRNDT` (CYYMMDD): 5 rows where `TRNDT > 1260617`; max = 1261110 (2026-11-10) |
| `Wholesale_ProductSourcing_AFI.PoDetail vs PoMaster` | 481 orphan detail rows, 20 warehouse mismatch | 🟠 Cần xác nhận nghiệp vụ | DE xác nhận source và EDW cũng có cùng pattern | [V] Re-scan 2026-06-18: orphan detail rows = `509` at join keys (`podordernum`,`podvendornum`,`podwarehouse`) ↔ (`pomordernum`,`pomvendornum`,`pomwarehouse`). Evidence: `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260618_142034_de_us_table2_scan/results.md`. |
| `Manufacturing_Inventory_AFI.TFRDTL vs TFRHDR` | 188 orphan detail records | 🟠 Cần xác nhận nghiệp vụ | DE xác nhận source cũng có orphan records | [V] orphan detail rows (DTL w/o HDR by transfer no) = 440; orphan distinct transfer no = 189 (US “188” có thể khác grain) |
| `Inventory_Enh_History.ItemBalance` | Chưa được promote lên EL, đang dùng workaround Dataflow Gen2 (~49M rows) | 🔴 DE chưa hoàn thành | Yet to done | [V] ✗ Không tồn tại trong `Enterprise_Lakehouse`; search `INFORMATION_SCHEMA.TABLES` không thấy table name chứa `ItemBalance`/`Balance`. |
| `DemandForecastSnapshotWeekly` | Snapshot refresh dừng từ 2024-03-25 | 🔴 DE chưa hoàn thành | Yet to done | [V] Resolved to `SupplyChain_Enh.DemandForecastSnapshotWeekly`; max `dfcSnapshot` = 2024-03-25 |
| `MasterData_DW.DimDate` | Data stale (204 ngày) | 🔴 DE chưa hoàn thành | Yet to done | [V] Calendar load is driven by `Meta.AssetRegistry` asset `ReferenceMaster_Enh.Calendar` (source=`Enterprise_Lakehouse.MasterData_DW.DimDate`): frequency **monthly→daily** (cron=`0 2 * * *`). Manual refresh completed: `ReferenceMaster_Enh.Calendar` max `LoadDT`=2026-06-17 07:34:43.333333; `SupplyChain_Gold_Warehouse.Shared_DW.DimCalendar` max `LoadDT`=2026-06-17 07:34:43.333333. Evidence: `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260617_1431_calendar_manual_refresh/`. |
| `MasterData_DW.DimItemMaster` | Data stale (204 ngày) | 🔴 DE chưa hoàn thành | Yet to done | [NV] ✓ Exists; max `ManufacturingStatusChangeDate` = 2026-06-15 (không phải LoadDT) |
| `DemandInventorySnapshotWeekly` | Snapshot refresh dừng từ 2026-03-02 | 🔴 DE chưa hoàn thành | Yet to done | [V] Resolved to `SupplyChain_Enh.DemandInventorySnapshotWeekly`; max `dinSnapshot` = 2026-03-02 |
| `DemandFulfillmentCommonContainer_Logility` | 9,128 duplicate groups; chưa có canonical dedupe rule | 🔴 DE chưa hoàn thành | Chưa có kết luận/remediation | [NV] ✓ Exists; max `WeekEnding` = 2026-05-16; duplicate-groups cần canonical key để verify |
| `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily` *(issue mới)* | Missing snapshots 20-Dec-2025..14-Feb-2026, ảnh hưởng IsActiveItemWhIn14DNext / IsActiveItemWhIn7DNext | 🔴 DE chưa hoàn thành | Chưa có remediation/backfill plan | [V] `SupplyChain_Enh_1` schema không còn; ✓ `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily` exists. Re-scan 2026-06-18: `MAX(spdWeekEnding)=2027-02-27` (future-dated). Evidence: `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260618_142034_de_us_table2_scan/results.md`. |

---

## Focus list — chỉ giữ 🟡 / 🟠 / 🔴 (loại bỏ `MasterData_DW.DimDate`, `DemandForecastSnapshotWeekly`)

Ghi chú:
- Mục 🔴: theo ý Aric, **không thêm check** ở đây (đã đủ để kết luận “chưa done”); chỉ ghi “next step” ở mức ownership.
- Mục 🟠 (3 items): DE nói “EDW/source cũng có lỗi” ⇒ **next step là chứng minh + quyết định**: (a) accept as business reality + document exception + monitor, hoặc (b) mở ticket fix upstream/EDW rồi reload.
- Mục 🟡 `SupplyChain_Enh.ATPWeekEnding`: cần re-check **freshness** (MAX `WeekEnding` có lên đến 06/2026 chưa) và **duplicate grain** (canonical key) trước khi chốt hướng xử lý.

Re-scan (Table 2 only, exclude `*_1` schemas): `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260618_142034_de_us_table2_scan/results.md`.

| Dataset / Table | Phân loại | Trạng thái hiện tại | Next step (owner) |
|---|---:|---|---|
| `SalesHistory_AFI_Enh.InvoiceHeader` | 🟡 | DE đã chạy full history load; cần Analytics confirm | Analytics xác nhận logic/coverage (source-of-truth) + chốt report impact (Analytics) |
| `SalesHistory_AFI_Enh.InvoiceDetail` | 🟡 | DE đã update schema sang `SalesHistory_AFI_enh`; cần Analytics confirm | Analytics xác nhận schema/joins/metrics không break; chốt consumer mapping (Analytics) |
| `SupplyChain_Enh.PurchaseOrderSnapshot` | 🟡 | DE nói “chưa promote” nhưng thực tế đã có data; cần Analytics confirm | Analytics xác nhận business expectation “promote” nghĩa là gì (table vs view vs semantic); nếu ok thì downgrade severity (Analytics + DE) |
| `SupplyChain_Enh.ATPWeekEnding` | 🟡 | DE load xong nhưng còn duplicate/null | (1) Re-check `MAX(WeekEnding)` xem có lên đến 06/2026 không; (2) xác định canonical dedupe key + rule; (3) chốt xử lý `AFIFinanceDivision` NULL (Analytics + DE) |
| `Manufacturing_Inventory_AFI.IMHIST` | 🟠 | DE nói source/EDW cũng future-dated | Yêu cầu DE gửi evidence EDW query (counts + max TRNDT) + business confirm: future-date là hợp lệ hay bug; nếu bug → nhờ team EDW/source fix và DE reload vào Fabric (DE + EDW owners + Business) |
| `Wholesale_ProductSourcing_AFI.PoDetail vs PoMaster` | 🟠 | DE nói source/EDW cũng orphan | Yêu cầu DE gửi evidence EDW query (481 orphan theo grain nào) + quyết định: accept exception (monitor) hay fix upstream (backfill missing masters / enforce FK) rồi reload (DE + EDW owners + Business) |
| `Manufacturing_Inventory_AFI.TFRDTL vs TFRHDR` | 🟠 | DE nói source/EDW cũng orphan; grain mismatch (188 vs 440 vs 189) | Chốt grain thống nhất để đo (transfer_no vs full-row); DE cung cấp EDW evidence theo đúng grain; nếu bug → fix upstream/EDW rồi reload; nếu accept → document exception + monitor (DE + EDW owners + Business) |
| `Inventory_Enh_History.ItemBalance` | 🔴 | Yet to done (không tồn tại trong `Enterprise_Lakehouse`) | DE provide plan: promote object vào `Enterprise_Lakehouse` hoặc chốt workaround thay thế + timeline (DE) |
| `MasterData_DW.DimItemMaster` | 🔴 | Yet to done (exists nhưng stale metric chưa chứng minh bằng LoadDT) | DE clarify freshness definition/column; nếu cần freshness thật → bổ sung LoadDT/UpdateTS hoặc publish a standardized freshness view (DE) |
| `DemandInventorySnapshotWeekly` | 🔴 | Yet to done (max `dinSnapshot` = 2026-03-02) | DE provide remediation/backfill plan + target snapshot date (DE) |
| `DemandFulfillmentCommonContainer_Logility` | 🔴 | Chưa có canonical dedupe rule | Chốt canonical key + dedupe policy (Analytics/Business), rồi DE implement dedupe/constraint/monitoring (Analytics + DE) |
| `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily` | 🔴 | Missing snapshot range; chưa có remediation plan | DE provide backfill plan + confirm correct object name (no `_Enh_1`) + impact assessment (DE + Analytics) |

---

## Table 3 — Draft message to DE team (Dhivya) based on Table 2 re-scan (2026-06-18)

Hi Dhivya, we reviewed the latest status note and re-validated the remaining open items directly in `Enterprise_Lakehouse` (re-scan date: **2026-06-18**, ignoring any schemas ending with `_1`). Most requests look completed; below are the items that still appear unresolved / need clarification. Could you please help check with the team and provide an update + remediation plan where needed? Thank you.

Evidence:
- `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260618_142034_de_us_table2_scan/results.md`
- `Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260618_142034_de_us_table2_scan/results.json`

| # | Dataset / Table | Category | Current Status | Issue / Validation Finding | Question / Action Needed |
|---:|---|---|---|---|---|
| 1 | `SupplyChain_Enh.ATPWeekEnding` | 🟡 Requires Analytics Revalidation | DE loaded the table, but validation still detects issues | Re-scan 2026-06-18: `MAX(WeekEnding)=2026-07-25`. `AFIFinanceDivision` NULL still exists. Duplicates exist under multiple key/grain guesses (canonical key/versioning needs confirmation). | Please confirm the intended canonical grain for this table. Then: (a) confirm why `AFIFinanceDivision` can be NULL (expected source behavior vs load/transform issue), and (b) provide a remediation plan (dedupe rule / constraint / downstream handling). |
| 2 | `Manufacturing_Inventory_AFI.IMHIST` | 🟠 Business Validation Required | DE confirmed future-dated records also exist in source/EDW | Re-scan 2026-06-18: future-dated records found in `TRNDT` (CYYMMDD). `future_rows=5`, `MAX(TRNDT)=1261110` (2026-11-10). | Please confirm business rule: are future transaction dates valid behavior or data error? If error: source/EDW fix + reload. If valid: define approved handling (flag/exclude from KPIs, or separate “future-posted” bucket). |
| 3 | `Wholesale_ProductSourcing_AFI.PoDetail` vs `PoMaster` | 🟠 Business Validation Required | DE confirmed pattern exists in source/EDW | Re-scan 2026-06-18: orphan detail rows = `509` using join keys (`podordernum`,`podvendornum`,`podwarehouse`) ↔ (`pomordernum`,`pomvendornum`,`pomwarehouse`). | Please confirm whether these orphans are valid business cases. If not valid: source/EDW fix (missing masters / late-arriving masters) + reload. If valid: define an orphan-handling rule (flag + reporting exclusion/exception logic). |
| 4 | `Manufacturing_Inventory_AFI.TFRDTL` vs `TFRHDR` | 🟠 Business Validation Required | DE confirmed orphan records also exist in source/EDW | Re-scan 2026-06-18: orphan detail rows = `440` by transfer number join `DTFRNO↔HTFRNO`. | Please confirm expected lifecycle: are detail-only transfers valid or data issue? If issue: source/EDW fix + reload. If valid: define reporting rule to flag incomplete transfers. |
| 5 | `Inventory_Enh_History.ItemBalance` | 🔴 Raised / No Update Yet | No update observed yet | Re-scan 2026-06-18: table does **not** exist in `Enterprise_Lakehouse` (invalid object). | Please confirm target object name/status: will it be promoted/created in `Enterprise_Lakehouse`, renamed, or replaced? Provide ETA + expected refresh schedule and a reliable freshness column/audit reference once available. |
| 6 | `MasterData_DW.DimItemMaster` | 🔴 Raised / Needs Freshness Proof | Table exists but load timestamp is unclear | Re-scan 2026-06-18: `MAX(ManufacturingStatusChangeDate)=2026-06-15` appears to be a business attribute, not `LoadDT`. | Please confirm the proper freshness proof (LoadDT column, pipeline audit table, or standard “freshness view”) for this table. |
| 7 | `SupplyChain_Enh.DemandInventorySnapshotWeekly` | 🔴 Raised / Still Stale | Still stale | Re-scan 2026-06-18: `MAX(dinSnapshot)=2026-03-02 05:30:02`. | Please confirm whether the pipeline is disabled/failing/missing source data, and provide refresh/backfill plan + ETA. |
| 8 | `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` | 🔴 Raised / Needs Canonical Dedupe Key | Canonical key still required | Re-scan 2026-06-18: `MAX(WeekEnding)=2026-05-16`. Duplicates are reported but canonical business key is required to validate/remediate correctly. | Please define/confirm the canonical deduplication key. After key confirmation, we can validate duplicate counts precisely and decide remediation (upstream fix vs EDW dedupe vs downstream logic). |
| 9 | `SupplyChain_Enh.SupplyPlanDetailSnapshotDaily` | 🔴 Raised / Missing Snapshot Range | Missing snapshots in a specific period | `SupplyChain_Enh_1` schema no longer exists; table exists under `SupplyChain_Enh`. Prior finding: for 2025-12-20..2026-02-14 only 3 distinct `spdWeekEnding` (impacts IsActiveItemWhIn14DNext/7DNext). Re-scan 2026-06-18: `MAX(spdWeekEnding)=2027-02-27` (future-dated horizon exists). | Please confirm whether missing snapshots for 2025-12-20..2026-02-14 can be backfilled. If not possible, provide expected business impact + recommended downstream handling (exclude/flag the period). |
