# overall_architecture_ashley_legend.md — Legend / Glossary for `overall_architecture_ashley.png`

Ngữ cảnh: file này giải thích các khối trong sơ đồ kiến trúc tổng quan Ashley (Azure → Databricks → Fabric → domain workspaces), dựa trên góc nhìn enterprise (US) mà Enterprise ETL mô tả: **SQL Server Agent Jobs** là *system-of-record orchestrator*; Databricks là *core compute*; Fabric là *analytics/serving*, trong đó `EnterpriseData` (hub) publish ra các domain workspaces như SupplyChain/Retail/Wholesale/Sales/Finance.

Sơ đồ liên quan:
- `overall_architecture_ashley.png`
- (bản overview ổn layout hơn) `overall_architecture_ashley_overview.png`

## Confidence tags

- **[Verified]**: có trong tài liệu chính thức Microsoft.
- **[Likely]**: đúng theo mô tả của Enterprise ETL + pattern enterprise thường gặp, nhưng chưa có inventory Ashley để xác nhận 100%.
- **[Need-verify]**: cần hỏi Enterprise ETL/Saravan hoặc scan hệ thống để chốt.

---

## 1) L0 — Azure Foundation (Enterprise Platform)

### 1.1 Identity / Security / Ops (typical)

Khối này đại diện cho “nền móng vận hành” (landing zone) của enterprise Azure. Nó không phải 1 service duy nhất mà là tập các năng lực chuẩn:

- **Entra ID (RBAC/PIM)**: quản lý identity + phân quyền truy cập (role-based access) và nâng quyền tạm thời (privileged identity). [Likely]
- **Network (VNet / Private Endpoints / DNS)**: cô lập mạng, private access tới data services, routing/DNS để các service nói chuyện an toàn. [Likely]
- **Key Vault**: lưu secrets/keys/cert để job và app dùng. [Likely]
- **Monitor / Logs / Alerts**: quan sát, log, alerting ở mức platform. [Likely]

> Lưu ý: đây là “foundation”, không phải nơi chứa business logic ETL.

### 1.2 Data Estate (global)

Khối này là “tài sản dữ liệu” (data sources) của enterprise:

- **External systems**: POS/ERP/WMS/IoT/Partners… (hệ thống ngoài tạo dữ liệu gốc). [Likely]
- **Azure Databases / EDW (multi-domain)**: lớp database/EDW để lưu dữ liệu có cấu trúc (structured), thường theo domain. [Likely]
- **Landing (ADLS / files / events)**: lớp landing cho file/event (batch/stream). [Likely]

---

## 2) SQL Server Agent Jobs là gì? Vì sao “mạnh” ở góc nhìn của họ?

**SQL Server Agent** là 1 service trong SQL Server dùng để chạy **jobs** (mỗi job gồm nhiều **job steps**) theo lịch / theo event / chạy tay, có cơ chế logging + notification. [Verified] citeturn0search0turn0search4

Điểm “mạnh” trong enterprise ops (tóm đúng ý Enterprise ETL):
- **One place for schedule + retry + alert + job history**: họ coi đây là “system-of-record” cho vận hành batch. [Likely] citeturn0search0turn0search4
- **Cross-system steps**: một job có thể có nhiều bước gọi SQL, gọi PowerShell/command, gọi API… để điều phối các hệ thống khác nhau. [Likely] citeturn0search0

### 2.1 “SQL Server Agent quản lý được Azure/Databricks/Fabric” nghĩa là gì?

Không phải SQL Agent “điều khiển nội tạng” Databricks/Fabric, mà là nó đóng vai **orchestrator-of-orchestrators**:

- SQL Agent chạy 1 step kiểu “trigger downstream job” (API/CLI/PowerShell/SQL).
- Downstream platform (Databricks/Fabric/…​) tự chạy workload của nó.
- SQL Agent tiếp tục làm gate/retry/alert theo policy enterprise.

=> Đây là lý do Enterprise ETL nói “job retail daily có 100+ tasks” (multi-step, cross-environment). [Likely]

---

## 3) Azure Databases/EDW vs ADLS (Data Lake Storage)

### 3.1 Azure Databases / EDW là gì?

Khái niệm chung: hệ quản trị dữ liệu có schema/transaction, truy vấn bằng SQL, phù hợp structured workloads. “EDW” thường nhấn mạnh enterprise warehouse patterns (star schema, marts, conformed dimensions, governance). [Likely]

### 3.2 ADLS (Azure Data Lake Storage Gen2) là gì?

ADLS Gen2 là capability của Azure Storage (Blob) khi bật **hierarchical namespace** để có “file system semantics” (folders/paths) ở quy mô object storage. [Verified] citeturn0search1turn0search5

### 3.3 Khác nhau nhanh

- **Database/EDW**: “tables-first”, transaction/query engine, schema constraints, phục vụ SQL analytics/BI chuẩn. [Likely]
- **ADLS**: “files-first”, lưu raw/curated files (Parquet/JSON/CSV), phù hợp landing + big data processing engines. [Likely] citeturn0search1

---

## 4) L1 — Databricks (core compute)

Trong sơ đồ, Databricks là nơi làm “core compute”:

- **Databricks Jobs / Workflows**: cơ chế chạy batch/stream workloads (job runs). [Likely]
- **Streaming + Batch processing**: xử lý ETL/ELT, curated tables (thường là Delta Lake). [Likely]

> [Need-verify] Ashley dùng Workflows/Jobs theo cách nào (task graph, retries, cluster policy, streaming sources cụ thể…).

---

## 5) L2 — Microsoft Fabric (EnterpriseData → Domains)

### 5.1 EnterpriseData workspace là gì?

Trong ngữ cảnh enterprise, `EnterpriseData` (hub) là nơi publish “shared curated surfaces” để domain workspaces consume. [Likely]

### 5.2 Fabric Lakehouse vs Warehouse (khác gì ADLS/Azure DB?)

Microsoft Fabric có **Lakehouse** và **Data Warehouse** là 2 “workloads” để lưu và phục vụ data, chọn theo persona/use-case. [Verified] citeturn0search2turn0search10

Tóm tắt theo decision guide:
- **Warehouse**: thiên về enterprise warehousing, SQL/BI/OLAP, full SQL transaction support. [Verified] citeturn0search10
- **Lakehouse**: thiên về data engineering/big data/ML, dữ liệu dạng open table format trong OneLake (Delta-style). [Verified] citeturn0search10

So với ADLS:
- ADLS là storage nền (files/paths).
- Fabric Lakehouse/Warehouse là “managed analytic workloads” trên OneLake (vẫn dựa trên open formats), có experience/engine/permissioning/monitoring theo Fabric. [Likely] citeturn0search10

### 5.3 Fabric “jobs entrypoints” là gì?

Trong sơ đồ mình dùng cụm “Fabric jobs entrypoints” để gom nhóm các cách enterprise thường “đá xuống Fabric”:

- **Pipeline runs** (Fabric Data Factory pipelines): có thể run on-demand, schedule, hoặc event trigger. [Verified] citeturn0search3turn0search7
- **Refresh / SQL execution**: các hành động kiểu refresh semantic model / chạy SQL trong warehouse/lakehouse… (tùy cách họ setup). [Need-verify]

### 5.4 “Fabric job sinh ra đã bị super orchestrator quản lý đúng không?”

- Về nguyên tắc: **đúng nếu họ chọn như vậy** (SQL Agent là system-of-record, trigger Fabric entrypoints). [Likely]
- Nhưng: Fabric không tự “bị quản lý” một cách magic. Cần integration (API/CLI/call pattern) để SQL Agent trigger và nhận trạng thái. [Need-verify]

Điểm cần chốt bằng chứng với Enterprise ETL/Saravan:
- “L0 gọi Fabric bằng gì?” (REST API? PowerShell module? ADF? custom wrapper?) [Need-verify]
- “Ai là source-of-truth cho retry/alert?” (SQL Agent hay Fabric?) [Need-verify]

---

## 6) “ETL framework” vs “VN Control Plane” trong Fabric domain (SupplyChain)

### 6.1 ETL framework (enterprise pattern)

Trong mô tả repo của bạn, “Enterprise ETL Framework” thường là:
- dictionary/metadata contract (TableDictionary posture)
- publish semantics kiểu working/swap (`_Wrk → _LOAD → swap`)
- audit/audit log patterns
- wrapper procedure/mapping để refresh theo danh sách [Likely]

=> Đây là “framework governance + publish semantics” mạnh, phù hợp enterprise multi-domain.

### 6.2 VN Control Plane (SupplyChain) là gì trong sơ đồ?

VN Control Plane (SupplyChain) là **domain runtime capability**:
- dependency → **waves**
- **due gate / smart scheduling**
- per-asset **run logs**
- (tuỳ mode) DQ/lineage hooks [Likely]

Điểm quan trọng: nó không phải “thêm 1 scheduler thứ 2”, mà là “runtime intelligence” chạy **bên trong domain**. [Likely]

### 6.3 Nếu không apply theo họ mà “tự cải cách” thì rủi ro gì?

Rủi ro họ lo nhất thường là **dueling schedulers**:
- Fabric pipelines tự schedule/retry/alert độc lập
- trong khi SQL Agent vẫn schedule workload tương tự
→ split-brain ops, khó incident response. [Likely]

---

## 7) Câu trả lời ngắn cho câu hỏi cuối của bạn

> “Cụ thể ở Fabric họ quản lý bằng ETL framework?”

Khả năng cao là:
- **ETL framework** của họ định nghĩa contract/publish/audit và cách refresh tables/views theo domain. [Likely]
- **SQL Server Agent** là L0 orchestrator gọi các “entrypoints” (có thể là wrapper proc/pipeline/refresh) để chạy các phần trong Fabric và các platform khác. [Likely]

Nhưng để trả lời “đúng 100% Ashley” cần chốt 3 câu: [Need-verify]
1) L0 orchestrator của họ ngoài SQL Agent còn gì nữa không?
2) Trong Fabric họ trigger bằng pipeline hay by SQL proc wrappers hay cả hai?
3) On-call/alerting source-of-truth là SQL Agent hay Fabric?

