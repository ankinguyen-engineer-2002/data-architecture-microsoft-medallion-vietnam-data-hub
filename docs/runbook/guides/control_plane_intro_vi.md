# Giới thiệu kiến trúc & vận hành Data Platform (VN SupplyChain) trên Microsoft Fabric
*(Bản chi tiết — workflow/câu chuyện rõ ràng, “email-ready” theo nghĩa: anh có thể attach nguyên file này vào email)*

Ngày chốt bằng chứng cho phần compare: **2026-06-17 (ICT)** *(dựa trên evidence pack hub scan 2026-05-10 + VN inventory/ops snapshot 2026-06-16)*.

Mục tiêu tài liệu:
- Viết cho người **không phải Data Engineer** nhưng vẫn cần hiểu “hệ thống chạy thế nào” để quyết định.
- Trình bày theo flow, có câu chuyện vận hành.
- Compare **operations end-to-end** giữa 2 pattern: **VN Control Plane** vs **Enterprise ETL Framework**.
- Nêu rõ các options triển khai đồng bộ và trường hợp “forced adopt hub framework”.

> Tone: trung lập. Không “bên nào tốt hơn”. Chỉ mô tả operational reality + lựa chọn triển khai.

---

## Mục lục (flow end-to-end)

0) Cách đọc nhanh (2 phút)  
1) Executive summary (copy vào email)  
2) Architecture overview (non-DE vẫn hiểu)  
3) Day-in-the-life: một ngày hệ thống chạy ra sao  
4) Control Plane deep dive: tính năng, ý nghĩa, setup, “vì sao dùng”  
5) Compare operations end-to-end: VN Control Plane vs Enterprise ETL Framework  
6) Concerns & câu hỏi (maximize utilize: TableDictionary + working/swap) + forced-adopt scenario  
7) Vận hành & giám sát: ops questions → ops answers (SQL templates)  
8) Options đồng bộ / áp dụng (để stakeholder chọn)  
9) Forced adopt hub ETL framework: hub có/chưa có gì so với runtime controls VN  
10) Các câu hỏi cần chốt (để “đọc xong là ra quyết định”)  
Appendix: templates onboarding (VN vs Enterprise)

## 0) Cách đọc nhanh (2 phút)

Nếu bạn chỉ có 5 phút:
1) Đọc **§1 (Executive summary)**
2) Đọc **§5 (Compare operations end-to-end)**
3) Đọc **§8 (Options)** + **§10 (Decisions)**

Nếu bạn cần hiểu “vì sao hệ thống chạy được như vậy”:
- Đọc **§2–§4** (architecture + day-in-the-life + feature deep dive)
- Xem các toggle ở **Appendix** để mở template kỹ thuật.

---

## 1) Executive summary (copy thẳng vào email)

**1) Chúng tôi đang vận hành cái gì?**  
Một **value-stream data platform** trên Fabric cho Supply Chain: xử lý ở **Processing (Silver)**, publish ở **Gold**, phục vụ BI bằng **Direct Lake semantic/report**.

**2) “Bộ não vận hành” nằm ở đâu?**  
Ở **Control Plane** (metadata-driven): registry quyết định “chạy cái gì, khi nào, theo thứ tự nào”, và logs trả lời “chạy lâu nhất / fail ở đâu”.

**3) Vì sao chọn kiến trúc này?**  
Để giảm “mỗi table một pipeline/proc riêng” thành “đăng ký metadata → engine chạy”, đồng thời có:
- dependency-safe execution (waves)
- asset-level due gate (smart scheduling)
- run-level observability (status/duration/rows/error)
- (tuỳ bật) DQ + lineage hooks

**4) Enterprise ETL Framework (US) khác gì?**  
Enterprise pattern (TableDictionary + AuditLog + working/swap publish) tối ưu cho:
- “enterprise-facing dictionary”: người ngoài team nhìn 1 chỗ là hiểu
- publish kiểu `_Wrk → _LOAD → swap`: consumer không thấy partial state

**5) Cần chốt gì để đồng bộ?**  
Chốt 3 thứ để quyết nhanh:
1) TableDictionary cần adapter/export hay bắt buộc physical sync?
2) Working/swap có bắt buộc không, áp dụng ở Silver/Gold/both?
3) Nếu “forced adopt hub framework”, có cần mang theo runtime controls của VN (due gate/waves/DQ/lineage/runlog) hay không?

---

## 2) Architecture overview (non-DE vẫn hiểu)

### 2.1 Hai workspace và vai trò

- **Enterprise (US / EnterpriseData-Dev)**: governance-first.
  - Có ETL framework tập trung.
  - Dùng TableDictionary/AuditLog như “enterprise control surface”.
- **Value stream (VN / Enterprise SupplyChain-Dev)**: runtime-first.
  - Có control plane để chạy theo registry + logs + dependency waves.
  - Có serving layer (Gold + semantic/report) nên chịu trách nhiệm “consumer contract”.

ASCII overview:

```text
             (Enterprise - US) EnterpriseData-Dev
  Source_Data (Bronze)  + Domain Warehouses (Curated)
          |                       |
          |                 ETL_Framework
          |           (TableDictionary + AuditLog
          |             + working/swap pattern)
          |
          +---- OneLake shortcuts / shared surfaces ----+
                                                       |
                 (Value Stream - VN) Enterprise SupplyChain-Dev
         Processing Warehouse (Silver + Meta/Control Plane)
                          |
                     Gold Warehouse
                          |
                  Direct Lake Semantic + Report
```

### 2.2 Data Plane vs Control Plane (ý tưởng lõi)

- **Data Plane**: bảng dữ liệu thật (Silver/Gold) mà consumer dùng.
- **Control Plane**: metadata + logs + rules để điều khiển vận hành.

Một câu để nhớ: **Data Plane là “cái hệ thống tạo ra”, Control Plane là “cách hệ thống quyết định tạo ra nó”.**

### 2.3 5 nguyên lý thiết kế (architecture principles)

1) **Metadata-driven**: registry quyết định runtime; tránh hard-code list tables trong pipeline.
2) **Dependency-aware**: không publish bảng con trước bảng cha; cho phép song song có kiểm soát (waves).
3) **Schedule-aware**: chạy theo “đến hạn” ở level asset/table (due gate).
4) **Observable by default**: mọi run đều log status/duration/rows/error (machine-readable).
5) **Serving-first contract**: Gold + semantic là hợp đồng với consumer → schema/naming ổn định.

### 2.4 Minh hoạ đề xuất (attach vào email nếu cần)

Để đọc nhanh bằng hình, attach các sơ đồ (đã nhúng inline để đọc không bị “khô”):

**(1) Cross-workspace overview (Enterprise ↔ Value stream)**

![Cross-workspace overview](assets/cross_workspace_architecture.png)

**(2) Main architecture**

![Main architecture](assets/02_main_architecture.svg)

**(3) Control plane overview**

![Control plane overview](assets/03_control_plane.svg)

**(4) Control plane detail**

![Control plane detail](assets/22_control_plane_detail.svg)

---

## 3) Câu chuyện vận hành: “Một ngày hệ thống chạy”

### 3.0 Pipeline → Control Plane (trên Fabric, nhìn từ outside)

- [Verified] `pl_sc_master` là pipeline master (daily schedule 02:00 ICT) → gọi `pl_sc_mart` theo `project` trong registry → chạy Bronze/Silver/Gold theo metadata.
- “Control Plane” nằm ở phần metadata + procedures (registry, waves planner, generic loader, run logs) — pipeline chỉ là “executor”.

### 3.1 Day-in-the-life (operational narrative)

1) **Pick work**: đọc registry để biết asset nào “đến hạn” (due).
2) **Plan order**: tính dependency và chia thành waves (wave 0 → 1 → 2…).
3) **Execute**: chạy theo wave; trong wave có thể song song nhưng chỉ trong phạm vi dependency-safe.
4) **Log**: mỗi asset run ghi status/duration/rows/error để truy vết.
5) **Controls (tuỳ chọn)**: chạy DQ/reconciliation, ghi PASS/FAIL, tuỳ mode có thể block publish.
6) **Publish**: publish ra Gold (và/hoặc curated outputs).
7) **Serve**: semantic/report consume Gold; nếu có drift, đây là nơi bộc lộ lỗi nhanh nhất.

### 3.2 Vì sao “waves + due gate” đáng giá? (giải thích kiểu stakeholder)

- **Waves**: không chỉ để “nhanh hơn”, mà để “đúng thứ tự nhưng vẫn song song”, giảm blast radius khi fail.
- **Due gate**: chạy đúng cái đến hạn, giảm chạy dư và giảm risk capacity spike.

---

## 4) Control Plane deep dive: tính năng & “vì sao dùng”

Mục tiêu phần này: giải thích rõ **Control Plane là gì** và **vì sao nó giúp vận hành**, theo từng capability.

### 4.1 Registry (AssetRegistry) — “đăng ký để chạy”

Ý tưởng: thay vì hard-code “danh sách tables cần chạy” trong pipeline/procedure, team chỉ **đăng ký metadata** cho từng asset. Runtime engine sẽ đọc registry để quyết định:

- chạy cái gì (asset list)
- chạy theo thứ tự nào (dependency)
- chạy khi nào (schedule/due)
- chạy bằng cách nào (load_type/pattern)

Tại sao cách này giúp scale:
- Khi số asset tăng, registry-driven giúp tránh “bùng nổ số pipeline/proc theo table”.
- Khi có thay đổi source/refresh rule, update registry có thể đủ (không cần sửa pipeline).

<details>
  <summary><b>Ví dụ (dễ hình dung): thêm 1 DomainSilver table mới</b></summary>

  Use case: DA/DE muốn thêm `InventoryHistory_Enh.SupplierLeadTime`.

  “Đăng ký” nghĩa là:
  - viết 1 view `InventoryHistory_Enh.v_SupplierLeadTime`
  - insert 1 row vào `Meta.AssetRegistry` với `asset_id='InventoryHistory_Enh.SupplierLeadTime'`
  - test `Meta.usp_GenericLoad` 1-table
  - ok rồi mới bật `is_active=1` để pipeline tự pick up

</details>

<details>
  <summary><b>Setup (copy/paste) — registry row tối thiểu</b></summary>

  Mục tiêu: có đủ metadata để runtime engine chạy được, triage được, và để sau này đồng bộ sang hub (nếu cần).

```sql
DECLARE @ws VARCHAR(128) = 'c8d9fc83-18b6-4e1d-8264-0b49eed36fe0';
DECLARE @wh_proc VARCHAR(128) = 'SupplyChain_Processing_Warehouse';

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES (
    '<Schema>.<TableName>',
    '<project>',
    '<ReferenceMaster|DomainSilver|Gold>',
    @ws,
    @wh_proc,
    '<Schema>',
    '<TableName>',
    '<Schema>.v_<TableName>',
    '<overwrite|incremental|upsert|datekey|daterange|identity|cdc|scd2>',
    '<pk1,pk2,...>',
    '["<UpstreamObject1>","<UpstreamObject2>"]',
    NULL,
    '<daily|monthly|...>',
    '<cron>',
    0,
    '<WarehouseTransform|GoldPublish|...>'
);
```

  Ghi chú: bắt đầu với `is_active=0` để test an toàn, chỉ bật `1` khi one-table test xanh.

</details>

### 4.2 1 generic SP nhiều load pattern — “engine chạy theo metadata”

Ý tưởng: thay vì có nhiều stored procedures cho từng table, ta dùng **1 engine** (`Meta.usp_GenericLoad`) và route theo `load_type`/metadata.

Điểm mạnh (đọc cho stakeholder):
- Một thay đổi về logic load/observability/security → áp dụng đồng đều cho tất cả assets.
- Khi scale lên 50/100/500 tables, không phát sinh “rừng proc”.

Trade-off thực tế:
- Dynamic SQL + dispatch logic khiến debug khó hơn nếu thiếu logs tốt.
- Vì vậy engine phải đi cùng RunLog/AuditLog, và quy ước input metadata rõ ràng (PK/watermark/date key).

<details>
  <summary><b>Ví dụ: 3 kiểu load phổ biến (nói bằng business-language)</b></summary>

  - `overwrite`: “mỗi lần chạy là build lại table từ view” (phù hợp table nhỏ/medium hoặc view đã scoped đúng snapshot).
  - `incremental`: “chỉ load phần mới” theo `watermark_column` (phù hợp fact lớn).
  - `datekey` / `daterange`: “reload theo ngày / theo cửa sổ” để xử lý late-arriving data.

</details>

<details>
  <summary><b>Setup (copy/paste) — one-table test + verify logs</b></summary>

```sql
-- 1) Smoke-test view
SELECT TOP 100 * FROM <Schema>.v_<TableName>;
SELECT COUNT(*) AS row_count FROM <Schema>.v_<TableName>;

-- 2) Run one-table materialization
EXEC Meta.usp_GenericLoad
    @target_schema = '<Schema>',
    @target_table  = '<TableName>';

-- 3) Verify physical + RunLog
SELECT COUNT(*) AS physical_row_count
FROM <Schema>.<TableName>;

SELECT TOP 50 *
FROM Meta.RunLog
WHERE asset_id = '<Schema>.<TableName>'
ORDER BY start_time_utc DESC;
```

</details>

### 4.3 Waves (DAG runtime) — “đúng thứ tự nhưng vẫn song song”

Ý tưởng: dependency giữa tables là “sự thật vận hành”. Nếu chạy sai thứ tự thì output có thể sai hoặc fail.

Waves giúp giải quyết bài toán: “đúng thứ tự” nhưng vẫn tận dụng concurrency:
- DAG được build từ `depends_on`
- engine phân waves: Wave 0 (không phụ thuộc), Wave 1 (phụ thuộc Wave 0), …
- trong cùng wave, tables chạy song song (batch=8) vì không phụ thuộc nhau

<details>
  <summary><b>Ví dụ (nhìn như graph):</b></summary>

```text
Wave 0:  DimCalendar, DimItem
Wave 1:  FactSales (depends_on DimCalendar, DimItem)
Wave 2:  GoldKPI (depends_on FactSales)
```

  Nếu `FactSales` fail ở Wave 1 thì Wave 2 không chạy → giảm blast radius và tránh publish dữ liệu sai/thiếu.

</details>

<details>
  <summary><b>Setup (copy/paste) — recompute waves + xem wave assignment</b></summary>

```sql
EXEC Meta.usp_ComputeSilverWaves;

SELECT *
FROM Meta.SilverDagWaveRuntime
WHERE project = '<project>'
ORDER BY wave_number, asset_id;
```

</details>

### 4.4 Due gate / smart scheduling — “chỉ chạy cái đến hạn”

Ý tưởng: schedule nên ở level “asset/table” chứ không chỉ ở level pipeline.

Do đó control plane lưu:
- `cron_expression` (khi nào nên chạy)
- `next_run_time` (được tính ra để pipeline có thể filter “due now”)

Lợi ích vận hành:
- Tránh “full refresh every day” khi có assets monthly/weekly.
- Tập trung compute vào phần thực sự đến hạn → ổn định runtime/cost.
- Mở đường cho SLA management ở level table.

Ghi chú trạng thái hiện tại:
- [Verified] due-filter đã được chứng minh rõ ở Bronze/REF và Gold.
- [Verified] Silver hiện đang all-daily nên chưa cần due-filter trực tiếp; nếu sau này Silver mixed-frequency thì đây là requirement.

<details>
  <summary><b>Setup (copy/paste) — query “what is due now?”</b></summary>

```sql
SELECT TOP 200
    r.project, r.asset_id, r.cron_expression, r.next_run_time, r.last_load_date
FROM Meta.AssetRegistry r
WHERE r.is_active = 1
  AND (r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())
ORDER BY r.project, r.next_run_time, r.asset_id;
```

</details>

### 4.5 Observability (RunLog/AuditLog/UpdateLog) — “trả lời 5 câu hỏi ops”

Nếu không có logs chuẩn, team operations sẽ bị kẹt ở:
- “có vẻ pipeline fail” nhưng không biết fail ở table nào
- “pipeline lâu” nhưng không biết table nào gây chậm

Run-level logs giúp trả lời các câu hỏi ops một cách machine-readable:
- status (running/success/failed)
- duration (start/end timestamps)
- rows_loaded (để detect anomaly)
- error_message (để triage nhanh)

<details>
  <summary><b>Ví dụ: top slowest assets (7 ngày)</b></summary>

```sql
SELECT TOP 30
    rl.asset_id,
    rl.status,
    rl.load_type,
    rl.start_time_utc,
    rl.end_time_utc,
    DATEDIFF(SECOND, rl.start_time_utc, rl.end_time_utc) AS duration_sec,
    rl.rows_loaded,
    LEFT(rl.error_message, 200) AS error_preview
FROM Meta.RunLog rl
WHERE rl.start_time_utc >= DATEADD(DAY, -7, GETUTCDATE())
  AND rl.end_time_utc IS NOT NULL
ORDER BY duration_sec DESC;
```

</details>

### 4.6 Data Quality (DQ) — “rules + modes”

DQ “có” không đủ — điều quan trọng là DQ được dùng như thế nào:

- **DQ as alert**: phát hiện vấn đề và gửi cảnh báo, nhưng pipeline vẫn publish.
- **DQ as gate**: rule có mode/severity; nếu fail ở mức CRITICAL có thể block publish để tránh consumer dùng dữ liệu sai.

Để làm được DQ as gate, cần 3 thứ:
1) rules registry (rule definition, target, severity)
2) results log (PASS/FAIL theo run)
3) gate policy (Off/WarnOnly/CriticalStops…)

<details>
  <summary><b>Setup (copy/paste) — thêm rule tối thiểu</b></summary>

```sql
INSERT INTO Meta.DQRule (
    rule_name, target_schema, target_table, layer,
    check_type, column_name, severity, threshold, is_active
) VALUES
('<rule name>', '<Schema>', '<TableName>', '<DomainSilver|ReferenceMaster|Gold>',
 'completeness', '<ColumnName>', 'CRITICAL', 100.0, 1);

-- Run a single check (id depends on your insert method)
EXEC Meta.usp_CheckDqSingle @rule_id = <new_rule_id>;
```

</details>

### 4.7 Lineage (direct + semantic) — “table này đọc từ đâu”

Lineage ở đây được hiểu theo 2 lớp:

- **Direct lineage** (data movement): table/view này đọc từ source nào → transform → ra target nào.
- **Semantic lineage** (serving contract): nếu có BI serving, một thay đổi ở table có thể ảnh hưởng measure/visual/report nào.

Tại sao lineage quan trọng với US team:
- Dễ audit “data contract” và blast radius của thay đổi (schema/drift).
- Giảm thời gian debug khi có incident downstream (BI/consumer).

<details>
  <summary><b>Setup (copy/paste) — build & query lineage edges</b></summary>

```sql
EXEC Meta.usp_BuildLineage;

SELECT source_asset, target_asset, edge_type, transform_type
FROM Meta.LineageEdge
WHERE target_asset = '<Schema>.<TableName>';
```

</details>

### 4.8 “Vì sao dùng?” — 6 câu hỏi thường gặp (FAQ)

1) Vì sao không “mỗi table một pipeline”?  
→ Scale lên sẽ nổ số lượng pipeline/proc và drift; registry-driven giúp giữ 1 runtime engine.

2) Vì sao phải có waves?  
→ Để vừa đúng dependency vừa tận dụng parallelism (không phải chạy tuần tự tất cả).

3) Vì sao phải có due gate?  
→ Tránh refresh dư; giữ cost/runtime ổn định khi assets tăng.

4) Vì sao cần RunLog riêng, không chỉ AuditLog text?  
→ Để query/aggregate machine-readable (duration/rows/error) và export monitoring dễ.

5) Vì sao DQ phải có “modes”?  
→ Stakeholder cần biết rule nào chỉ cảnh báo và rule nào phải block publish.

6) Vì sao lineage quan trọng nếu đã có TableDictionary?  
→ TableDictionary tốt cho governance, nhưng lineage graph + semantic edges giúp debug serving nhanh hơn.

---

## 5) Compare operations end-to-end: VN Control Plane vs Enterprise ETL Framework

> Compare để hiểu “khả năng vận hành và điểm cần đồng bộ”, không phải để chấm điểm.

Điểm giống nhau (nền tảng chung):
- Cả hai đều **metadata-driven** (registry/dictionary quyết định runtime).
- Cả hai đều coi **audit/logging** là phần của “control surface” (không phải phụ trợ).
- Cả hai đều có “publish semantics” để giảm rủi ro consumer thấy trạng thái chưa hoàn chỉnh (Enterprise đã chuẩn hoá mạnh bằng working/swap; VN có thể adopt theo phạm vi).

Điểm khác nhau (trọng tâm):
- Enterprise ưu tiên **enterprise-facing governance** (TableDictionary posture + audit trails).
- VN ưu tiên **runtime controls** (due gate + waves + run-level metrics + DQ modes + lineage hooks) vì có serving layer active.

### 5.1 Compare theo 8 mảng vận hành

1) Workspace surface & serving burden
2) Data contracts
3) Orchestration
4) Scheduling & gating
5) Publish semantics
6) Observability/Audit
7) Controls (DQ/Reconciliation)
8) Lineage

### 5.2 Workspace surface & serving burden

- VN: [Verified] có semantic/report active → ops burden cao hơn ở serving (schema stability, Direct Lake failures, binding drift).
- Enterprise: [Need-verify] evidence pack enterprise scan tập trung vào ETL framework + domain warehouses; serving footprint (semantic/report) trong DEV snapshot chưa được chứng minh tương đương VN.

Giải thích dễ hiểu:
- Khi có semantic/report active, “data contract” không chỉ là table schema mà còn là relationships/measures/visual expectations. Drift nhỏ ở upstream có thể gây user-facing incident.
- Vì vậy serving layer tạo thêm responsibilities: compatibility, refresh strategy, and change management.

**Implication:** Nếu hub productize BI nhiều hơn sau này, serving ops sẽ tăng mạnh (đây là “độ khó tự nhiên” của serving layer).

### 5.3 Data contracts (consumer “tin” vào đâu)

- VN: [Verified] Gold physical tables + Direct Lake semantic là contract.
- Enterprise: [Verified] curated domain tables + TableDictionary là governance contract.

Giải thích dễ hiểu:
- Enterprise contract thiên về “enterprise metadata + curated tables”: ai cũng đọc được TableDictionary để hiểu table, keys, refresh cadence, source mapping.
- VN contract thiên về “serving correctness”: Gold tables + semantic model là thứ report/consumer chạm trực tiếp.

**Implication:** Khi schema đổi, cần chốt rõ backward compatibility là trách nhiệm ở layer nào (view compatibility, table compatibility, semantic compatibility).

### 5.4 Orchestration (ai quyết định chạy cái gì)

- VN: [Verified] registry-driven, project-aware, dependency-aware (waves).
- Enterprise: [Verified] dictionary/mapping-driven, wrapper/loop style; per-table refresh theo EXEC calls.

**Implication:**
- VN onboarding thường là “đăng ký metadata” + engine chạy.
- Enterprise onboarding thường là “thêm row TableDictionary” + “thêm EXEC vào wrapper/mapping”.

Ví dụ (onboarding 1 table mới):
- Enterprise: domain team thường tạo `_Wrk` view + register TableDictionary + add vào wrapper refresh (sequential).
- VN: tạo view + register AssetRegistry (is_active=0) + one-table test + flip is_active=1 (pipeline auto picks up).

### 5.5 Scheduling & gating

- VN: [Verified] asset-level due gate/smart scheduling (đã thấy due-filter ở Bronze/REF + Gold; Silver hiện all-daily).
- Enterprise: [Verified] có pipeline-level schedule + có cột `RefreshRate`/`Modified` trong TableDictionary (phục vụ SLA tracking); [Verified] orchestration quan sát được không có “smart skip” theo refresh rate (wrapper chạy full refresh).

**Implication:** Nếu enterprise yêu cầu “chạy đúng table đến hạn”, hub cần bổ sung asset-level schedule state + due-filter.

### 5.6 Publish semantics (consumer có thấy partial state không)

- Enterprise: [Verified] working/swap `_Wrk → _LOAD → swap/rename`.
- VN: [Likely] có thể adopt working/swap có chọn lọc để đồng bộ consumer experience, nhưng cần policy rõ.

Giải thích dễ hiểu:
- working/swap là cách giảm rủi ro “consumer đọc trúng table đang load dở” (partial state).
- Nếu VN adopt, cần chốt phạm vi + policy: table nào bắt buộc, ai được quyền swap, rollback thế nào.

### 5.7 Observability/Audit

- VN: [Verified] run-level machine-readable logs (status/duration/rows/error per asset).
- Enterprise: [Verified] AuditLog trail + UpdateLog; [Likely] suy duration bằng pairing Start/Complete; [Need-verify] pairing 100% nếu thiếu correlation id.

**Implication:** Nếu enterprise cần “duration analytics chuẩn 100%”, cần correlation rules/run id.

### 5.8 Controls (DQ / reconciliation / guardrails)

- VN: [Verified] có DQ registry/runlog (Meta surface) và có thể bật gate modes.
- Enterprise: [Verified] có DQ/reconciliation theo kiểu “check + alert” (ví dụ pipeline reconciliation + AuditMode/Audit_TableName trong TableDictionary), nhưng [Need-verify] chưa thấy subsystem “DQ rules registry + gate modes” ở level asset tương đương VN.

**Implication:** Nếu bắt buộc DQ gate state + modes, hub cần thêm subsystem DQ registry + run log + hook points.

### 5.9 Lineage

- VN: [Verified] có lineage surface và build được từ metadata/registry + semantic edges khi có serving.
- Enterprise: [Verified] TableDictionary giữ được source reference ở table-level; [Need-verify] chưa thấy module lineage graph (LineageEdge table + build proc) như VN.

Giải thích dễ hiểu:
- TableDictionary “giữ mô tả + mapping” tốt, nhưng lineage graph giúp trả lời nhanh “động vào table A thì ảnh hưởng downstream nào”.

---

## 6) Concerns & câu hỏi (maximize utilize) + forced-adopt scenario

### 6.1 TableDictionary — cần mức nào để “enterprise có thể reuse tooling”

- Concern: nếu chỉ adapter/export → hub thấy được “dictionary posture” nhưng có thể thiếu strict schema/ownership rules.
- Câu hỏi chốt: hub yêu cầu **physical sync** (write vào hub TableDictionary) hay **export/adapter** (publish 1 table/view mapping) là đủ?

### 6.2 Working/swap publish — phạm vi và chi phí ops

- [Verified] Enterprise pattern dùng `_Wrk` views + `_LOAD` table + rename (swap) để consumer không thấy partial state.
- Concern: nếu VN adopt 100% ở mọi layer → ops complexity tăng (policy swap/rename/drop, permissions, audit).
- Câu hỏi chốt: working/swap bắt buộc ở **Gold** hay cả **Silver/Gold**?

### 6.3 Giả sử “forced adopt hub ETL framework”: đưa runtime controls của VN vào hub như thế nào?

Thay vì đặt vấn đề theo kiểu “bên nào phải chấp nhận thiếu capability”, cách nói dễ làm việc hơn là:

> Nếu enterprise buộc value stream phải chạy theo hub ETL framework, thì để không downgrade vận hành, chúng ta sẽ **đưa các runtime controls của VN** vào ETL_Framework theo module nào, đặt ở đâu, và rollout theo bước nào?

Những capability VN thường cần trong thực tế vận hành (khi serving active):
- dependency waves (DAG runtime / parallel batch)
- due gate (asset-level cron + next_run_time filter)
- run-level machine-readable metrics (rows/duration/error per asset)
- DQ registry + gate modes (WarnOnly/CriticalStops)
- lineage graph (LineageEdge + build) + semantic edges khi có BI serving

<details>
  <summary><b>Cách apply vào ETL_Framework (conceptual module mapping)</b></summary>

  Ý tưởng là **giữ nguyên TableDictionary posture + working/swap** (thế mạnh hub), rồi bổ sung các module runtime theo cách không phá governance:

  1) <b>Schedule Gate module</b>  
     - Bổ sung schedule-state (cron/next_run_time) ở level table/asset (có thể là table mới hoặc extension view).  
     - Orchestrator (pipeline/wrapper) filter “due now” trước khi gọi refresh.

  2) <b>Dependency + Waves module</b>  
     - Lưu dependency edges (table A depends_on B) → compute waves runtime.  
     - Thay wrapper sequential bằng “waves executor”: trong wave chạy parallel, giữa waves chạy sequential.

  3) <b>RunLog module</b>  
     - Giữ AuditLog (trail) nhưng thêm RunLog machine-readable (rows/duration/error per asset) để analytics/triage chuẩn.

  4) <b>DQ module (rules + modes)</b>  
     - Giữ reconciliation/alerts hiện có, nhưng thêm rules registry + gate modes để có thể block publish khi CRITICAL fail.

  5) <b>Lineage module</b>  
     - Giữ source reference trong TableDictionary; thêm LineageEdge graph + build job để audit blast radius nhanh.

  Rollout an toàn thường là: RunLog → Due gate → Waves → DQ gate → Lineage graph (vì RunLog/Due gate dễ value và ít phá hệ thống).

</details>

Capability checklist (để nói chuyện nhanh, không tranh luận cảm tính):

| Capability | VN Control Plane | Enterprise ETL Framework | Ghi chú |
|---|---|---|---|
| Dictionary/metadata contract | [Verified] có (Meta + TableDictionary compat) | [Verified] có (TableDictionary 65 cols) | Enterprise governance-first |
| Working/swap publish semantics | [Likely] adopt theo phạm vi | [Verified] có (`_Wrk` views + `_LOAD` + rename) | Enterprise chuẩn hoá mạnh |
| Smart schedule / due gate | [Verified] có (BRZ/REF + Gold due-filter) | [Verified] chưa thấy “smart skip” | Enterprise có `RefreshRate`/`Modified` cho SLA tracking |
| Dependency waves (DAG runtime) | [Verified] có (waves + parallel batch) | [Verified] wrapper refresh chạy sequential | Enterprise dependency chủ yếu manual trong proc body |
| Run-level machine-readable metrics | [Verified] có (rows/duration/error per asset) | [Verified] AuditLog trail + UpdateLog; [Need-verify] duration pairing 100% | Nếu enterprise cần analytics chuẩn, cần correlation rules/run-id |
| DQ rules + gate modes | [Verified] hướng subsystem (rules/runlog/modes) | [Verified] có check+alert (reconciliation/AuditMode); [Need-verify] gate modes | “Alert” khác “Gate” |
| Lineage graph + semantic edges | [Verified] build từ metadata/registry + serving | [Verified] source reference ở table-level; [Need-verify] lineage graph module | Serving footprint khác nhau giữa 2 bên |
| 1 generic engine nhiều load patterns | [Verified] có (8 load patterns qua `load_type`) | [Verified] không (35 procs/10 families + UpdateMethod) | Trade-off debugability vs maintainability |

Trạng thái theo evidence hiện có:
- Waves/DAG runtime: [Verified] hub wrapper chạy sequential; không thấy DAG-wave executor.
- Due gate/smart skip: [Verified] “smart skip” không thấy trong orchestration; schedule chủ yếu ở pipeline/wrapper.
- DQ: [Verified] có check+alert (reconciliation/AuditMode); [Need-verify] DQ registry + gate modes như VN.
- Lineage: [Verified] có source reference trong TableDictionary; [Need-verify] lineage graph module.
- 1 generic SP nhiều load patterns: [Verified] hub là “35 procs / 10 families + UpdateMethod”, không phải 1 engine duy nhất.

---

## 7) Vận hành & giám sát: ops questions → ops answers

### 7.1 5 câu hỏi ops tiêu chuẩn

1) Hệ thống đang chạy gì?
2) Cái gì chạy lâu nhất?
3) Cái gì fail, fail vì sao?
4) Cái gì đến hạn chạy?
5) Table này đọc từ đâu?

### 7.2 Cách trả lời theo 2 pattern

**VN (registry + run logs):**
- Trả lời mạnh câu 2/3/4 nhờ due gate + run-level metrics.

**Enterprise (TableDictionary + AuditLog + working/swap):**
- Trả lời mạnh câu 5 theo hướng enterprise dictionary.
- Publish “không partial state” nhờ working/swap.
- Câu 2/3 suy từ AuditLog; để chắc 100% cần chốt pairing/correlation rule.

### 7.3 SQL templates (tuỳ chọn)

```sql
-- Top runs by duration (last 7 days)
SELECT TOP 30
    rl.asset_id,
    rl.status,
    rl.load_type,
    rl.start_time_utc,
    rl.end_time_utc,
    DATEDIFF(SECOND, rl.start_time_utc, rl.end_time_utc) AS duration_sec,
    rl.rows_loaded,
    LEFT(rl.error_message, 200) AS error_preview
FROM Meta.RunLog rl
WHERE rl.start_time_utc >= DATEADD(DAY, -7, GETUTCDATE())
  AND rl.end_time_utc IS NOT NULL
ORDER BY duration_sec DESC;

-- Recent failures
SELECT TOP 50
    rl.asset_id, rl.start_time_utc, rl.end_time_utc, rl.status, rl.rows_loaded, rl.error_message
FROM Meta.RunLog rl
WHERE rl.status <> 'success'
ORDER BY rl.start_time_utc DESC;

-- “What is due now?”
SELECT TOP 200
    r.project, r.asset_id, r.cron_expression, r.next_run_time, r.last_load_date
FROM Meta.AssetRegistry r
WHERE r.is_active = 1
  AND (r.next_run_time IS NULL OR r.next_run_time <= GETUTCDATE())
ORDER BY r.project, r.next_run_time, r.asset_id;
```

---

## 8) Options đồng bộ / áp dụng (để stakeholder chọn)

### Option A — Giữ runtime engine VN, bổ sung “enterprise-facing visibility layer”

Giữ registry/waves/due gate/run logs/DQ/lineage; bổ sung presentation layer để stakeholder đọc “giống TableDictionary/Audit”.

- Pros: không downgrade runtime; rollout nhanh.
- Cons: cần chốt output contract (cột bắt buộc, strict schema).
- Trade-off: effort modeling tăng, runtime regression tối thiểu.

### Option B — Adopt working/swap publish pattern của hub (chọn phạm vi)

Áp dụng `_Wrk → _LOAD → swap` cho publish quan trọng (Silver/Gold/both).

- Pros: consumer không thấy partial state.
- Cons: cần policy swap/rename/drop; chốt phạm vi.
- Trade-off: ops complexity tăng, consumer experience tốt hơn.

### Option C — Physical TableDictionary sync “y chang hub”

Sync/export thành physical table đúng schema hub yêu cầu.

- Pros: hub monitoring reuse tool 1:1.
- Cons: risk drift/maintenance; cần approval/quyền.
- Trade-off: compatibility cao, cost ops cao.

---

## 9) Forced adopt hub ETL framework: hub có/chưa có gì so với runtime controls VN

### 9.1 Enterprise ETL framework làm tốt sẵn

- [Verified] enterprise-facing dictionary posture (TableDictionary/AuditLog)
- [Verified] working/swap publish (consumer không thấy partial state)

### 9.2 Enterprise ETL framework làm được nhưng cần chốt cách đo

- [Likely] “table/proc chạy lâu nhất”: suy duration bằng AuditLog Start/Complete pairing
- [Need-verify] nếu cần chắc 100% trong mọi case (retry/concurrency/nested calls) thì cần correlation id hoặc pairing rules chuẩn

### 9.3 Enterprise ETL framework có “hooks” nhưng để đạt runtime controls kiểu VN thì cần bổ sung module rõ ràng

Nếu bắt buộc phải có (để không downgrade ops khi forced adopt), cần nâng cấp modules:
- asset-level due gate (next_run_time/cron per asset)
- dependency waves (DAG runtime)
- DQ gate state + modes (WarnOnly/CriticalStops)
- lineage state table + build proc
- run-level machine-readable metrics (rows_loaded/error per asset)

### 9.4 Checklist nâng cấp tối thiểu (nếu hub phải đạt capability VN)

1) Schedule gate: add schedule-state + `is_due` + orchestrator due-filter
2) Waves: add dependency edges + wave runtime + wave executor
3) DQ: add DQ registry + DQ run log + hook points + gate modes
4) Lineage: add LineageEdge + build procedure từ mapping/metadata
5) RunLog: nếu AuditLog chỉ là trail, thêm RunLog machine-readable để có rows/duration/error theo asset

---

## 10) Các câu hỏi cần chốt (để “đọc xong là ra quyết định”)

1) TableDictionary: adapter/export đủ hay bắt buộc physical sync? strict schema đến đâu?
2) Working/swap có bắt buộc không? áp dụng ở Silver, Gold hay cả hai?
3) Forced adopt hub framework: có cần mang theo runtime controls của VN (due gate/waves/DQ/lineage/runlog) hay chấp nhận bỏ bớt?
4) Ops metrics cần ở level nào: table-level, proc-level, hay pipeline-level? correlation id có bắt buộc không?
5) Ownership: ai sở hữu modules bổ sung (hub team hay value-stream team), và đặt ở đâu (ETL hub hay domain WH)?

---

## Appendix (tuỳ chọn mở rộng)

<details>
  <summary><b>Appendix A: Workflow onboarding 1 table mới theo VN pattern (template)</b></summary>

  Mục tiêu: thêm 1 table/asset mới mà không phải “mỗi table viết 1 pipeline riêng”.

  1) Xác định contract: target schema/table, grain, primary key, refresh frequency.
  2) Tạo source view / transform logic (nếu có).
  3) Đăng ký metadata vào registry (asset_id, project, layer, load_type, source mapping, depends_on, schedule).
  4) (Tuỳ chọn) thêm DQ rules và reconciliation rules.
  5) Chạy thử 1 lần (manual) và verify logs (status/duration/rows/error) + verify consumer contract (Gold/semantic nếu có).

</details>

<details>
  <summary><b>Appendix B: Workflow onboarding 1 curated table theo Enterprise pattern (template)</b></summary>

  Mục tiêu: thêm 1 curated table theo “dictionary-first + working/swap publish”.

  1) Viết view trong working schema (`*_Wrk.v_*`).
  2) Insert/Update row trong TableDictionary (update method, refresh rate, source mapping, keys).
  3) Thêm EXEC call vào wrapper proc/mapping loop để refresh.
  4) Verify AuditLog + TableDictionary.Modified/UpdateLog.

</details>

<details>
  <summary><b>Appendix C: Setup chi tiết (copy/paste) — View → Registry → DAG/Lineage → One-table test → Activate</b></summary>

  Mục tiêu: bổ sung “setup detail” để người đọc có thể hình dung rõ end-to-end *từ lúc nhận yêu cầu đến lúc pipeline tự pick up*.

  <b>0) Mental model</b>

```text
DA request
  -> define source + target + grain
  -> create T-SQL view
  -> insert Meta.AssetRegistry row (is_active=0)
  -> recompute Silver DAG / lineage
  -> run one-table test
  -> flip is_active=1 (pipeline auto-picks up)
```

  <b>1) Smoke-test view (đảm bảo source OK trước khi load)</b>

```sql
SELECT TOP 100 * FROM <Schema>.v_<TableName>;
SELECT COUNT(*) AS row_count FROM <Schema>.v_<TableName>;
```

  Nếu có primary key kỳ vọng unique:

```sql
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT CONCAT(<pk_col1>, '|', <pk_col2>, '|', <pk_col3>)) AS distinct_key_count
FROM <Schema>.v_<TableName>;
```

  <b>2) Insert registry row (DomainSilver example)</b>

```sql
DECLARE @ws VARCHAR(128) = 'c8d9fc83-18b6-4e1d-8264-0b49eed36fe0';
DECLARE @wh_proc VARCHAR(128) = 'SupplyChain_Processing_Warehouse';

INSERT INTO Meta.AssetRegistry (
    asset_id, project, canonical_layer,
    physical_workspace, physical_item, physical_schema, physical_object,
    legacy_view_name, load_type, primary_key,
    source_objects, depends_on,
    frequency, cron_expression, is_active, access_mode
) VALUES (
    '<Schema>.<TableName>',
    '<project>',
    'DomainSilver',
    @ws,
    @wh_proc,
    '<Schema>',
    '<TableName>',
    '<Schema>.v_<TableName>',
    '<load_type>',
    '<pk1,pk2,...>',
    '["<UpstreamObject1>","<UpstreamObject2>"]',
    NULL,
    '<daily|monthly|...>',
    '<cron>',
    0,
    'WarehouseTransform'
);
```

  <b>3) Recompute Silver DAG (nếu là DomainSilver)</b>

```sql
EXEC Meta.usp_ComputeSilverWaves;

SELECT *
FROM Meta.SilverDagWaveRuntime
WHERE asset_id = '<Schema>.<TableName>';
```

  <b>4) Build lineage</b>

```sql
EXEC Meta.usp_BuildLineage;

SELECT source_asset, target_asset, edge_type, transform_type
FROM Meta.LineageEdge
WHERE target_asset = '<Schema>.<TableName>';
```

  <b>5) One-table materialization test</b>

ReferenceMaster / DomainSilver (Processing Warehouse):

```sql
EXEC Meta.usp_GenericLoad
    @target_schema = '<Schema>',
    @target_table  = '<TableName>';
```

Verify:

```sql
SELECT COUNT(*) AS physical_row_count
FROM <Schema>.<TableName>;

SELECT TOP 50 *
FROM Meta.RunLog
WHERE asset_id = '<Schema>.<TableName>'
ORDER BY start_time_utc DESC;
```

  <b>6) DQ rules (tuỳ chọn nhưng khuyến nghị)</b>

```sql
INSERT INTO Meta.DQRule (
    rule_name, target_schema, target_table, layer,
    check_type, column_name, severity, threshold, is_active
) VALUES
('<rule name>', '<Schema>', '<TableName>', '<DomainSilver|ReferenceMaster|Gold>',
 'completeness', '<ColumnName>', 'CRITICAL', 100.0, 1);
```

  <b>7) Activate (để pipeline auto pick up)</b>

```sql
UPDATE Meta.AssetRegistry
SET is_active = 1
WHERE asset_id = '<Schema>.<TableName>';

EXEC Meta.usp_ComputeSilverWaves;
EXEC Meta.usp_BuildLineage;
```

  <b>8) Gold note (destructive risk)</b>

  [Verified] Gold publish được mô tả là `pl_sc_gold` chạy CTAS theo registry. Nếu manual test bằng CTAS, phải tránh đè table production-facing nếu chưa được approve.

</details>
