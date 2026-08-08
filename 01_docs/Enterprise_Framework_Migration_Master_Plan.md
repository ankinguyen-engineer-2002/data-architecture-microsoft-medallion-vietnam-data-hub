# Kế hoạch tổng thể Migration Enterprise Framework

> Mục tiêu: thay đổi framework vận hành từ VN Control Plane hiện tại sang mô hình nền tảng do Enterprise ETL Framework điều khiển, nhưng **không thay đổi business logic ETL**, **không redesign Medallion**, và **không phá 04_semantic/report contract**.
>
> Ngày đánh giá: 2026-06-21 ICT  
> Cập nhật định hướng: 2026-06-22 ICT — Phase 1 dùng local `Enterprise SupplyChain-Dev.ETL_Framework` làm nền, nâng lên full Enterprise ETL Framework, rồi apply 100% cho Bronze/Silver/Gold; Phase 2 mới port các năng lực VN Control Plane cần giữ.
> Cập nhật trạng thái: 2026-06-23 ICT — Phase 1 đã complete; Phase 2 tạm deferred; repo đang được restructure thành documentation + operations repo với current architecture ở `01_docs/architecture/current/`, mart hubs ở `02_marts/`, orchestration ở `03_operations/orchestration/`, và context split ở `00_CONTEXT/`.
> Cập nhật closeout: 2026-06-24 ICT — full 4-wrapper Enterprise ETL runtime rerun đã pass, final audit pass, `TableDictionary`/`AuditLog` sạch cho active runtime, live/local SQL contract khớp `49/49`.
> Phạm vi chính: `Enterprise SupplyChain-Dev` và `EnterpriseData-Dev`  
> Ngôn ngữ: tiếng Việt, giữ nguyên technical terms/object names để đối chiếu với Fabric/repo.

---

## Tóm tắt điều hành

### Closeout hiện tại — 2026-06-24

- [Verified] SQL Agent handoff hiện là 4 wrapper procedures:
  1. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver`
  2. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
  3. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver`
  4. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`
- [Verified] Full wrapper run ngày 2026-06-24 pass `4/4`, tổng runtime `1,721.01s`.
- [Verified] Final audit pass:
  - live/local SQL modules: `49/49` matched, `0` drift
  - active `TableDictionary`: `46` curated rows, `46` `_Wrk.v_*` refs, `0` active error rows
  - compile smoke: `92/92` active target/source checks passed
  - `AuditLog`: `56 Process Start` + `56 Process Complete`, `0` errors
  - `queryinsights`: `0` non-success entries since full run start
  - semantic read-only smoke: `sc_control_tower` exists and remains Direct Lake on `SupplyChain_Gold_Warehouse`
- [Verified] `Shared_DW` is not a standalone mart; it is embedded inside each mart Gold wrapper as Wave 00.
- [Verified] Phase 2 remains deferred. DQ/Data Lineage/Wave enhancement work should not be started without a new explicit instruction.

### Historical baseline — 2026-06-21/2026-06-22

The notes below are preserved as the pre-migration baseline that drove the Phase 1 plan. They are intentionally kept for audit trail, but the 2026-06-24 closeout above is the current runtime state.

- [Verified] `Enterprise SupplyChain-Dev` hiện là value-stream workspace có runtime control plane mạnh: `Meta.AssetRegistry`, `Meta.RunLog`, `Meta.PipelineRunLog`, `Meta.SilverDagWaveRuntime`, `Meta.DQRule`, `Meta.LineageEdge`, `Meta.TableDictionary`, và 7 pipelines `pl_sc_*`.
- [Verified] `EnterpriseData-Dev` là enterprise hub có Enterprise ETL Framework: `ETL_Framework.DW_Developer.TableDictionary`, `AuditLog`, `TableDictionary_UpdateLog`, nhiều loader/refresh procs, và pattern domain warehouse `_Wrk -> _LOAD -> final table`.
- [Verified] `Enterprise SupplyChain-Dev` đã có local warehouse `ETL_Framework` (`d4eb02f9-c29e-4f0d-9870-43b5970b349f`), schema `DW_Developer`, 6 tables, 1 view, 8 stored procedures, 1 function, và `TableDictionary=13`; hiện metadata chủ yếu trỏ legacy `SupplyChain_Warehouse.SCP_Core.*` / `Temp_SCPWarehouse.SCP_Core.*`, chưa trỏ v10 Bronze/Silver/Gold.
- [Verified] `EnterpriseData-Dev.SupplyChain_Warehouse` hiện đã tồn tại, nhưng live SQL probe ngày 2026-06-21 cho thấy chưa có user tables/routines; đây là landing zone migration tiềm năng, chưa phải target đã triển khai.
- [Verified] `Enterprise SupplyChain-Dev` vẫn có 04_semantic/report debt: report `Forecast Accuracy Gold` đang bind vào legacy semantic model `Supply Chain Control Tower`, model này tiếp tục fail DirectLake framing vì thiếu `CogsRollingHelper`; `sc_control_tower` mới refresh được nhưng report chưa bind qua.
- [Verified] Chuyển đổi phải là **framework transformation**, không phải business transformation: cùng inputs, cùng SQL transformations, cùng Gold outputs, cùng 04_semantic/KPI behavior.
- [Likely] Kiến trúc mục tiêu hợp lý nhất sau cập nhật 2026-06-22 là **local `Enterprise SupplyChain-Dev.ETL_Framework` được nâng lên full Enterprise ETL và làm primary runtime/load framework cho cả Bronze/Silver/Gold**; các năng lực VN cần giữ chỉ được port sau đó như Enterprise ETL-compatible extensions: **DQ, Data Lineage, Wave Planner**.
- [Verified] `Meta.usp_GenericLoad` là capability hiện hữu và vẫn hữu ích cho rollback/fallback, nhưng không còn là target runtime nếu mục tiêu là “chuẩn y chang Enterprise ETL”.

Quyết định kiến trúc khuyến nghị:

```text
Không viết lại business SQL.
Không đổi grain/KPI/report contract.
Không bỏ Bronze/Silver/Gold.

Chỉ thay:
  Runtime/load framework: local ETL_Framework được nâng lên full Enterprise ETL và owns Bronze/Silver/Gold
  Hợp đồng metadata: local Enterprise ETL TableDictionary là registry chính trong Enterprise SupplyChain-Dev
  Điểm vào orchestration: Enterprise ETL wrapper/loader pattern là đường chạy chính
  Đóng gói monitoring/governance/CI-CD
  VN DQ / Data Lineage / Wave được port như extension sau Phase 1
```

---

## Cơ sở bằng chứng

### Bằng chứng từ repo

- [Verified] `AGENTS.md`: repo là Microsoft Fabric, Pure T-SQL, metadata-driven, có `Enterprise SupplyChain-Dev` DEV IDs và anti-amnesia `CONTEXT.md`.
- [Verified] `CONTEXT.md`: active retained context log under the repository retention policy. Historical pre-split context is available from Git history when explicitly needed.
- [Verified] `01_docs/enterprise-etl-framework/source/ETL_FRAMEWORK_GUIDE.md`, `01_docs/enterprise-etl-framework/source/FABRIC_ARCHITECTURE_AND_STANDARDS.md`, `01_docs/enterprise-etl-framework/source/SQLPROJ_BEST_PRACTICES.md`: tài liệu Enterprise ETL mới gửi mô tả intended architecture, `.sqlproj` conventions, và canonical framework concepts như `AuditLog`, `TableDictionary`, `Performance_Logs`, SLA/email alerting.
- [Verified] `01_docs/enterprise-etl-framework/source/EnterpriseData - ETL_Framework DataWarehouse Data Feed Alert_ 0.2857% behind (1 of 350).msg`: sample email thật từ `Datawarehouse Alerts`, ngày 2026-06-22, chứng minh Enterprise ETL có data-feed/SLA alert output dựa trên TableDictionary freshness với fields `Hours Late`, `Last Updated (UTC)`, `Refresh Rate`, `Schema Name`, `Table Name`, `Job Server`, `Job Name`.
- [Verified] Đối chiếu repo ngày 2026-06-23 cho thấy `01_docs/enterprise-etl-framework/source` hữu ích để hiểu intent/canonical style, nhưng **không phải** object-inventory source-of-truth 1:1 cho Phase 1; nó khác live reverse-engineered hub ở các điểm như 4-col `AuditLog`, `FabricMapping`, proc-family thực tế (`usp_RefreshCuratedTableFromView`, `usp_IncrementalTableLoad`, parquet variants) và absence của một số guide-only names trong evidence pack.
- [Verified] `01_docs/decisions/ADR-001-v10-hybrid-medallion.md`: Hybrid Medallion v10 đã accepted/implemented; control plane được giữ như horizontal operating layer.
- [Verified] `01_docs/decisions/ADR-008-enterprise_etl-alignment-naming-and-integration.md`: Enterprise ETL alignment đã implemented; `Meta.TableDictionary`, `AuditLog`, `TableDictionary_UpdateLog` được clone/port local.
- [Verified] `99_archive/reverse-engineering/enterprise_data_architect/10_evidence/02_etl_framework_summary.md`: pattern Enterprise ETL `ETL_Framework`, `TableDictionary` 65 cột, `AuditLog`, các nhóm loader, pattern refresh `_Wrk`.
- [Verified] `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/projects/live_audit_2026-06-15_v10_core_stack.md`: v10 core-stack audit mới nhất trong repo trước assessment này.
- [Verified] `01_docs/runbook/artifacts/20260616_compare_ws/20260616_ws_compare_analysis.md`: so sánh trực tiếp VN control plane với Enterprise ETL Framework.

### Bằng chứng live ngày 2026-06-21

- [Verified] Azure identity: `NAric@ashleyfurniture.com`, tenant `5a9d9cfd-c32e-4ac1-a9ed-fe83df4f9e4d`, subscription `DATAWAREHOUSE PROD`.
- [Verified] Accessible workspaces gồm `EnterpriseData-Dev`, `EnterpriseData`, `Enterprise SupplyChain-Dev`, `Enterprise SupplyChain`, `Enterprise_Retail_Dev`.
- [Verified] `Enterprise SupplyChain-Dev`: 147 items.
- [Verified] `EnterpriseData-Dev`: 73 items.
- [Verified] `EnterpriseData-Dev.SupplyChain_Warehouse`: đã tồn tại, created `2026-05-12`, last updated `2026-06-18`, hiện chưa có user tables/routines.
- [Verified] `pl_sc_master`: có 2 schedules, cả hai đều `enabled=false`.
- [Verified] `EDW2FabricLoader`: chưa có schedule.
- [Verified] `EnterpriseData-Dev.ETL_Framework`: `TableDictionary=812`, `AuditLog=58261`, `TableDictionary_UpdateLog=23064`; đây là reference chuẩn Enterprise ETL để diff/sync local framework.
- [Verified] `Enterprise SupplyChain-Dev.ETL_Framework`: warehouse tồn tại, created `2025-08-19`, last updated `2026-06-15`, database `ETL_Framework`, schema `DW_Developer`; hiện có 6 base tables, 1 view, 8 stored procedures, 1 function.
- [Verified] Local `Enterprise SupplyChain-Dev.ETL_Framework.DW_Developer.TableDictionary`: `13` rows, chủ yếu legacy `SupplyChain_Warehouse.SCP_Core.*` và `Temp_SCPWarehouse.SCP_Core.FactOpenOrders`; chưa phải registry chính cho `Enterprise_Lakehouse`, `SupplyChain_Processing_Warehouse`, `SupplyChain_Gold_Warehouse`.
- [Verified] Local `Enterprise SupplyChain-Dev.ETL_Framework.DW_Developer.AuditLog`: `244` rows; recent commands là `usp_RefreshCuratedTableFromView` cho legacy `SCP_Core` objects, không phải v10 Medallion runtime.
- [Verified] `SupplyChain_Processing_Warehouse.Meta`: `AssetRegistry=55`, active assets `47`, `RunLog=1163`, `PipelineRunLog=61`, `LineageEdge=112`, `DQRule=98`, `DQGateRun=88`, `SourceContract=674`.
- [Verified] `SupplyChain_Gold_Warehouse`: `ForecastAccuracy_DW=4` tables, `InventoryHealth_DW=6` tables, `Shared_DW=3` tables.
- [Verified] Report `Forecast Accuracy Gold` bind vào legacy dataset `Supply Chain Control Tower` (`3eecf594-a75e-46ab-9162-63c95ee68e45`).
- [Verified] Legacy model refresh ngày 2026-06-20 vẫn fail: `DirectLake_TableNotFound` cho `CogsRollingHelper`.
- [Verified] `sc_control_tower` refresh ngày 2026-06-20 completed.

### Bằng chứng ngoài từ nguồn chính thức

- [Verified] Hướng dẫn Medallion của Microsoft Fabric khuyến nghị tách Bronze/Silver/Gold, dùng shortcuts khi dữ liệu nguồn đã ở OneLake/ADLS/S3/Google, và dùng Delta tables cho Silver/Gold. Nguồn: https://learn.microsoft.com/fabric/onelake/onelake-medallion-lakehouse-architecture
- [Verified] Baseline governance của Microsoft Fabric nói cấu trúc workspace xác định security boundary, phân bổ capacity, và ownership vận hành; data products nên gắn với owner rõ ràng. Nguồn: https://learn.microsoft.com/azure/cloud-adoption-framework/data/governance-security-baselines-fabric-data-lake-unify-data-platform
- [Verified] Lakehouse Git/deployment pipelines theo dõi metadata/shortcuts, không theo dõi data trong tables; deployment có thể override metadata của shortcut, nên review thay đổi là bắt buộc. Nguồn: https://learn.microsoft.com/fabric/data-engineering/lakehouse-git-deployment-pipelines
- [Verified] Direct Lake refresh là metadata/framing, không phải Import refresh; Direct Lake phụ thuộc vào object Delta hợp lệ và có thể fail/fallback theo giới hạn của source/table/view. Nguồn: https://learn.microsoft.com/fabric/fundamentals/direct-lake-overview

---

## 1. Bối cảnh hiện tại

### 1.1 Nền tảng hiện tại

[Verified] Kiến trúc hiện tại là 2-workspace hub-and-value-stream:

```text
EnterpriseData-Dev (hub / Enterprise ETL)
  - ETL_Framework
  - Source_Data
  - SupplyChain_Warehouse (shell rỗng hiện tại)
  - Retail / Wholesale / MasterData / Centralized / other warehouses
  - Databricks mirror / Mounted ADF / pipelines

Enterprise SupplyChain-Dev (VN value stream)
  - Enterprise_Lakehouse
  - SupplyChain_Processing_Warehouse
  - SupplyChain_Gold_Warehouse
  - Meta control plane
  - sc_control_tower + legacy 04_semantic/report artifacts
```

### 1.2 Mục tiêu chuyển đổi framework

[Verified] Ràng buộc của user khóa scope: mục tiêu là chuyển đổi framework, không phải redesign business logic.

Được phép thay đổi:

- Control Plane
- Metadata Layer
- Orchestration Layer
- Framework Services
- Monitoring
- Governance
- Deployment Framework

Không được thay đổi:

- Thay business SQL rules
- Thay aggregation/calculation/KPI behavior
- Thay grain của outputs hiện có
- Phá Direct Lake 04_semantic/report consumers
- Bỏ Bronze/Silver/Gold

### 1.3 Drift hiện tại cần chú ý

- [Verified] Hub `SupplyChain_Warehouse` đã tồn tại nhưng chưa có user objects. Docs cũ nói “does not exist” nay đã stale.
- [Verified] VN `Meta.AssetRegistry` active project taxonomy có drift: `inventoryHistory_Enh` active trở lại với 2 rows, trong khi target taxonomy trước đó là `inventory_health`.
- [Verified] VN Gold inventory table set đã đổi: `InventoryHealth_DW` hiện có 6 physical tables, trong khi nhiều 01_docs/TMDL snapshot chỉ nói 4.
- [Verified] `Meta.PipelineRunLog` có 2 run `pl_sc_master` ngày 2026-06-17 còn `running`, nhưng Fabric job history đánh dấu failed.
- [Verified] Legacy semantic model tiếp tục fail Direct Lake framing do thiếu table `CogsRollingHelper`.

---

## 2. Kiến trúc hiện trạng

### 2.1 Control Plane hiện tại

[Verified] VN Control Plane là runtime-aware, không chỉ catalog:

```text
Meta.AssetRegistry
  -> source_objects / depends_on / load_type / primary_key / watermark
  -> physical workspace/item/schema/object
  -> frequency / cron_expression / next_run_time
  -> project / canonical_layer

Meta.usp_GenericLoad
  -> thực thi table/view load theo registry contract

Meta.SilverDagWaveRuntime
  -> tính dependency waves

Meta.RunLog + Meta.PipelineRunLog
  -> asset/pipeline runtime logs

Meta.DQRule + Meta.DQGateRun
  -> quality gates

Meta.LineageEdge
  -> trạng thái lineage

Meta.TableDictionary + AuditLog + UpdateLog
  -> governance mirror tương thích Enterprise ETL
```

Điểm mạnh:

- [Verified] Dependency waves, due-gate, DQ hooks, lineage hooks, per-asset runtime logs đã tồn tại.
- [Verified] `Meta.usp_GenericLoad` có capability rộng; live active config chủ yếu là `overwrite`, thêm `datekey` và `incremental`.

Điểm yếu:

- [Verified] Enterprise-facing presentation vẫn khó đọc hơn Enterprise ETL `TableDictionary`.
- [Verified] Pipeline finalizer/log reconciliation có gaps: Fabric failed jobs có thể vẫn còn `running` trong `Meta.PipelineRunLog`.
- [Verified] Giới hạn execution của scalar UDF đã gây live failures trong một số context.

### 2.2 Data Plane hiện tại

[Verified] Data plane:

```text
Enterprise_Lakehouse
  -> logical Bronze / shortcut aggregator

SupplyChain_Processing_Warehouse
  -> Staging_Wrk
  -> ReferenceMaster_Enh
  -> ForecastHistory_Enh
  -> SalesHistory_Enh
  -> OpenOrderHistory_Enh
  -> InventoryHistory_Enh
  -> Meta

SupplyChain_Gold_Warehouse
  -> ForecastAccuracy_DW
  -> InventoryHealth_DW
  -> Shared_DW

Power BI / lớp semantic
  -> sc_control_tower
  -> legacy Supply Chain Control Tower
```

### 2.3 ETL Framework hiện tại

Phía VN:

- [Verified] 1 generic loader `Meta.usp_GenericLoad`.
- [Verified] 7 active v10 pipelines: `pl_sc_master`, `pl_sc_mart`, `pl_sc_staging`, `pl_sc_silver`, `pl_sc_silver_wave`, `pl_sc_gold`, `pl_dq_check`.
- [Verified] Silver dùng generic SP; Gold dùng pipeline CTAS publish.

Phía Enterprise ETL:

- [Verified] `ETL_Framework.DW_Developer.TableDictionary` là registry governance trung tâm.
- [Verified] `AuditLog` và `TableDictionary_UpdateLog` cung cấp operational trail nhìn được ở cấp enterprise.
- [Verified] Mô hình loader gồm nhiều stored procedure chuyên biệt và wrapper refresh patterns.
- [Verified] Các schema `_Wrk` chứa working views; loader tạo bảng `_LOAD` rồi chuyển sang final table.

### 2.4 Metadata Framework

Metadata hiện tại của VN mạnh hơn một catalog thụ động:

- [Verified] `AssetRegistry`: operational truth.
- [Verified] `TableDictionary`: Enterprise ETL-compatible governance mirror.
- [Verified] `SourceContract`: có 674 rows nhưng `SourceContractRun=0`, nên contract validation chưa phải active gate.
- [Verified] `LineageEdge`: đã tồn tại, nhưng registry `source_objects + depends_on` vẫn là sự thật ETL mạnh hơn khi lineage table bị trễ.

### 2.5 Monitoring / Observability

[Verified] Hiện có:

- `RunLog`
- `PipelineRunLog`
- `AuditLog`
- `DQGateRun`
- `TableDictionary_UpdateLog`
- Fabric job history
- Power BI refresh history

[Verified] Khoảng trống:

- Fabric job history và `Meta.PipelineRunLog` có thể lệch nhau.
- `PerformanceBaseline=0` và `PipelineCostLog=0` trong prior/live audit context.
- Alerting vẫn bị chặn/chưa trưởng thành do quyền IT/Mail/Teams.
- [Verified] Hub-side Enterprise ETL evidence có `Performance_Logs`, SLA alert/email queue families, và guide/email của Enterprise ETL cũng nhắc data-quality alerting qua email; tuy nhiên những năng lực này hiện **chưa là prerequisite** để chứng minh current SupplyChain runtime/load path chạy được qua local Enterprise ETL Phase 1.
- [Verified] Email alert sample mới xác nhận output alert dùng freshness/SLA fields tương thích `TableDictionary`: `Modified`/last-updated, `RefreshRate`, `JobServer`, `JobName`, `SchemaName`, `TableName`. Vì vậy Phase 1 phải bảo toàn/seed các field này cho SupplyChain rows, còn actual email scheduler/channel integration vẫn là readiness/backlog work.

### 2.6 Governance / Security

[Verified] Governance artifacts exist, but security model remains incomplete:

- `SecurityPolicy` và `DeploymentChecklist` tồn tại trong Meta, nhưng chưa được chứng minh là active.
- Workspace security/RLS/OLS/SQL grants cần thiết kế rõ ràng và owner sign-off.
- Microsoft guidance xem workspace là security boundary; mô hình hiện tại cần document owner, roles, và capacity/cost boundary theo từng workspace.

### 2.7 CI/CD / IaC

[Verified] Repo hiện là documentation/evidence repo, chưa phải full IaC source-of-truth.

Hiện tại:

- Đã có REST/TMDL scripts cho emergency/manual changes.
- Fabric Git/Deployment Pipelines chưa được áp dụng đầy đủ cho toàn bộ assets.
- ADO access từng bị blocked.

Hàm ý:

- Migration phải có một phase hardening CI/CD, không được giả định CI/CD đã sẵn sàng.

### 2.8 Chiến lược workspace

[Verified] Strategy hiện tại là hub + value-stream:

- Hub: `EnterpriseData-Dev`
- Value stream: `Enterprise SupplyChain-Dev`
- Target enterprise SupplyChain tiềm năng: `EnterpriseData-Dev.SupplyChain_Warehouse`

[Need-verify] Production promotion path cần Enterprise ETL/Rakesh xác nhận vì hiện `SupplyChain_Warehouse` đã tồn tại nhưng vẫn rỗng.

### 2.9 Chiến lược domain

[Verified] Chiến lược domain cần bảo toàn:

- Shared/enterprise data products ở hub khi có thể tái sử dụng.
- SupplyChain-specific Gold và 04_semantic/report serving tiếp tục nằm trong value-stream workspace, trừ khi Enterprise ETL/Rakesh quyết định khác.
- Domain ownership vẫn thuộc value-stream squad đối với SLAs/DQ/business outputs.

---

## 3. Kiến trúc mục tiêu

### 3.1 Nguyên tắc mục tiêu

```text
Local `Enterprise SupplyChain-Dev.ETL_Framework` được nâng lên full Enterprise ETL Framework và trở thành primary runtime/load framework cho Bronze/Silver/Gold.
VN business SQL giữ nguyên về mặt chức năng.
VN runtime intelligence không còn là runner chính; chỉ DQ, Data Lineage, Wave được port như Enterprise ETL-compatible extensions.
Medallion layers được giữ nguyên.
Semantic/report contracts giữ backward compatibility.
```

### 3.2 Kiến trúc logic

```text
Sources / Enterprise Lakehouse
        |
        v
Bronze access layer
  - OneLake shortcuts ở nơi source contract ổn định
  - Staging_Wrk chỉ dùng cho exception/fallback/replay
  - local Enterprise ETL TableDictionary + Enterprise ETL loader/wrapper pattern là đường chạy chính
        |
        v
Silver layer
  - existing SQL views/business transformations được bảo toàn
  - `_Wrk` views và target tables chạy theo Enterprise ETL Framework
  - không dùng `Meta.usp_GenericLoad` làm target runtime
  - Wave Planner được port sau Phase 1 để tối ưu dependency execution
        |
        v
Gold layer
  - physical Direct Lake serving tables được bảo toàn
  - không thay KPI/grain
  - Enterprise ETL loader/wrapper publish Gold theo cùng business SQL hiện có
        |
        v
Semantic layer
  - sc_control_tower được bảo toàn/mở rộng
  - legacy report binding chỉ retired sau validation
```

### 3.3 Kiến trúc vật lý

Mục tiêu khuyến nghị sau cập nhật 2026-06-22 là **local-first**, không tạo framework mới từ zero:

```text
Enterprise SupplyChain-Dev
  ETL_Framework
    - dùng warehouse local hiện có làm framework shell
    - bổ sung/sync missing Enterprise ETL tables/views/procs để đạt full Enterprise ETL contract
    - DW_Developer.TableDictionary trở thành registry chính cho v10 Medallion objects
    - DW_Developer.AuditLog và TableDictionary_UpdateLog là enterprise-style ops trail
    - Enterprise ETL wrapper/loader procs chạy Bronze/Silver/Gold
    - legacy SCP_Core rows giữ làm baseline/history/fallback; không delete/drop nếu chưa approve

  Enterprise_Lakehouse
    - Bronze access / shortcuts / lakehouse tables hiện có
    - không move/recreate nếu chưa có approved placement

  SupplyChain_Processing_Warehouse
    - Staging_Wrk / Silver / processing boundary giữ nguyên
    - SQL business views/tables giữ nguyên behavior
    - `_Wrk` views tương thích Enterprise ETL khi cần

  SupplyChain_Gold_Warehouse
    - Gold physical serving tables
    - giữ compatibility cho 04_semantic/report cho đến khi cutover đã validate

  sc_control_tower
    - semantic contract

  Meta
    - current VN runtime/control plane giữ làm fallback/rollback trong Phase 1
    - DQ / Data Lineage / Wave được port sau Phase 1

EnterpriseData-Dev
  ETL_Framework
    - source-of-truth reference cho full Enterprise ETL contract
    - dùng để diff/sync object definitions vào local ETL_Framework theo approval

  SupplyChain_Warehouse
    - landing zone rỗng hiện tại
    - future placement nếu Enterprise ETL/Rakesh quyết định move shared SupplyChain objects lên hub
    - không phải prerequisite của Phase 1 local Enterprise ETL adoption
```

### 3.4 Kiến trúc luồng dữ liệu

Hiện tại và tương lai phải giữ nguyên về mặt chức năng:

```text
Cùng Inputs
  -> Cùng SQL transformations
  -> Cùng Silver business outputs
  -> Cùng Gold physical outputs
  -> Cùng semantic measures/KPIs
```

Migration chỉ bổ sung:

```text
Enterprise ETL metadata registration
  -> Enterprise ETL audit/update logs
  -> Enterprise ETL loader/wrapper execution for Bronze/Silver/Gold
  -> Phase 2 Enterprise ETL extensions for DQ / Data Lineage / Wave
```

### 3.5 Kiến trúc metadata

Metadata mục tiêu nên tách trách nhiệm:

| Vai trò | Object mục tiêu | Mục đích |
|---|---|---|
| Enterprise catalog | Enterprise ETL `TableDictionary` | object nào tồn tại, owner, source, refresh method, Modified/RowCount |
| Runtime contract | Enterprise ETL `TableDictionary` + Enterprise ETL load wrapper | load method, source view, target table, Modified/RowCount |
| Audit trail | Enterprise ETL `AuditLog` + VN `RunLog` | enterprise message log + asset-level truth |
| Wave extension | Enterprise ETL execution-wave table seeded from VN dependency logic | dependency-safe execution |
| Lineage extension | `LineageEdge` ported to Enterprise ETL extension + Fabric/Purview lineage | impact analysis |
| Quality extension | `DQRule` / `DQGateRun` ported to Enterprise ETL DQ extension | validation evidence |
| Semantic contract | TMDL/PBIR + semantic contract table | bảo vệ report/KPI compatibility |

### 3.6 Kiến trúc governance

Governance mục tiêu:

- [Verified] Mỗi workspace/data product cần một named owner rõ ràng.
- [Need-verify] Enterprise ETL/Rakesh xác nhận owner của `EnterpriseData-Dev.SupplyChain_Warehouse`.
- [Need-verify] Security matrix: workspace roles, SQL endpoint permissions, semantic Build access, RLS/OLS, deployment rights.
- [Need-verify] Data classification và Purview labels/DLP strategy.

### 3.7 Kiến trúc deployment

Mục tiêu:

- Git-backed definitions cho pipelines/04_semantic/report ở nơi Fabric hỗ trợ.
- SQL deploy scripts hoặc sqlproj cho Warehouse objects.
- Controlled deployment TMDL/PBIR cho 04_semantic/report.
- Deployment pipeline hoặc Git sync có thể review.
- Bắt buộc pre-deploy diff và post-deploy validation.

Lưu ý quan trọng:

- [Verified] Fabric lakehouse Git/deployment theo dõi metadata/shortcuts, không theo dõi table data.
- [Verified] Deployment có thể override shortcuts; mọi deployment phải có review/diff.

### 3.8 Kiến trúc vận hành

Phần vận hành chính phía Enterprise ETL:

- Enterprise schedule / framework entrypoint
- `TableDictionary` và `AuditLog`
- Hub-level visibility
- Enterprise ETL loader/wrapper procs cho Bronze/Silver/Gold

Phần VN chỉ giữ lại như extension sau Phase 1:

- dependency waves
- DQ gates
- lineage graph
- semantic smoke tests

---

## 4. Tại sao phải thay đổi

### 4.1 Căn chỉnh với enterprise

[Verified] Enterprise ETL framework là governance surface được enterprise nhận diện trong `EnterpriseData-Dev`. Nếu SupplyChain muốn được promotion ở cấp enterprise, nó phải nhìn được qua metadata/audit paths tương thích Enterprise ETL.

### 4.2 Tránh platform hai bề mặt điều khiển

[Likely] Nếu chạy VN control plane như primary framework hoàn toàn tách biệt mãi mãi, governance sẽ bị nhân đôi:

- TableDictionary tách riêng
- AuditLog tách riêng
- scheduling semantics tách riêng
- owner story tách riêng
- deployment story tách riêng

### 4.3 Giữ điểm mạnh của VN

[Verified] VN control plane có các capabilities chưa thấy rõ trong Enterprise ETL Framework snapshots:

- asset-level due gate
- dependency waves
- explicit DQ tables
- lineage table
- rich RunLog

Thay đổi này **không được** xóa các năng lực đó. Nó nên expose các năng lực đó dưới enterprise framework.

### 4.4 Technical debt hiện tại cần cleanup

[Verified] Live drift hiện đang ảnh hưởng reliability:

- stale project taxonomy
- semantic split
- failed legacy refreshes
- pipeline log reconciliation mismatch
- source path failures under `SupplyChain_Enh_1`
- scalar UDF unavailable errors

Migration tạo một checkpoint tự nhiên để harden các contracts này.

---

## 5. Phân tích khoảng cách

| Khu vực | Hiện trạng | Trạng thái mục tiêu | Khoảng cách | Mức độ |
|---|---|---|---|---|
| Framework ownership | VN `Meta` là runtime brain | Enterprise ETL framework là primary runtime/load framework | Cần chuyển runtime sang Enterprise ETL, không chỉ làm facade | Cao |
| Metadata | VN `AssetRegistry` giàu hơn; Enterprise ETL `TableDictionary` là enterprise registry | Enterprise ETL `TableDictionary` là registry chính; VN metadata chỉ seed/fallback/extension | Cần mapping và cutover registry | Cao |
| Orchestration | VN có waves/due-gate; Enterprise ETL có wrappers/FabricMapping | Phase 1 Enterprise ETL wrapper/loader; Phase 2 Wave extension | Cần tách baseline Enterprise ETL khỏi nâng cấp wave | Cao |
| Scheduling | `pl_sc_master` schedules đang disabled | enterprise schedule có kiểm soát | Cần schedule owner và đường enablement | Cao |
| Logging | Giàu chi tiết nhưng có thể drift với Fabric job history | ops logs reconciled và authoritative | Cần finalizer/reconciliation | Cao |
| DQ | DQ objects đã tồn tại | active gate theo từng migration phase | `SourceContractRun=0`; DQ chưa tích hợp phổ quát | Cao |
| Lineage | `LineageEdge` tồn tại; registry là sự thật mạnh hơn | Fabric/Purview + registry lineage | Cần kỷ luật refresh/rebuild | Trung bình |
| Semantic | `sc_control_tower` ổn; report vẫn bind vào legacy failed model | report bind vào model khỏe hoặc legacy được sửa | Rủi ro BI tức thời | Nghiêm trọng |
| Hub SupplyChain WH | đã tồn tại nhưng rỗng | Bronze/Silver/Gold objects được populate/approve theo Enterprise ETL target scope | Cần object migration plan | Cao |
| CI/CD | REST/script/manual | Git/deployment governance | Gap IT/ADO/process | Cao |
| Security | docs còn một phần | explicit matrix | owner/roles/RLS/OLS cần signoff | Cao |
| Business logic | SQL logic nằm trong views/procs | cùng logic dưới framework mới | Cần parity harness | Nghiêm trọng |

---

## 6. Kế hoạch thay thế Control Plane

### 6.1 Chiến lược

Không “delete then rebuild”. Nhưng target không còn là hybrid runtime. Thay thế theo 4 lớp:

1. **Freeze** VN `Meta` hiện tại làm operational baseline.
2. **Implement Enterprise ETL 100% runtime/load pattern** cho Bronze/Silver/Gold trước.
3. **Port selectively** DQ, Data Lineage, Wave từ VN Control Plane sang Enterprise ETL-compatible extensions.
4. **Retire/demote** các phần VN control dư thừa chỉ sau parity và rollback window.

### 6.2 Mapping Control Plane mục tiêu

| VN Control Plane | Mục tiêu dưới Enterprise ETL migration | Quy tắc |
|---|---|---|
| `Meta.AssetRegistry` | transition inventory + rollback source | không còn primary runtime registry sau Phase 1 |
| `Meta.TableDictionary` | one-time/scheduled sync vào `ETL_Framework.DW_Developer.TableDictionary` | Enterprise ETL `TableDictionary` là registry chính |
| `Meta.RunLog` | optional detail log / fallback evidence | không thay thế Enterprise ETL `AuditLog`, chỉ bổ sung nếu cần |
| `Meta.PipelineRunLog` | reconciliation seed | sửa stuck-running rồi map vào Enterprise ETL ops view nếu cần |
| `Meta.SilverDagWaveRuntime` | Enterprise ETL Wave extension | port sau Phase 1 để giữ dependency-safe execution |
| `Meta.DQRule/DQGateRun` | Enterprise ETL DQ extension | port sau Phase 1; không chặn Enterprise ETL baseline cutover |
| `Meta.LineageEdge` | Enterprise ETL Lineage extension + Fabric/Purview lineage | port sau Phase 1; giữ source-to-target graph |
| `Meta.usp_GenericLoad` | legacy fallback/rollback only | không dùng làm target runtime |

### 6.3 Điều kiện tối thiểu để xem là đã thay thế

Control Plane được xem là đã thay thế cho Phase 1 DEV runtime khi:

- [Verified] Enterprise ETL `TableDictionary` + wrapper/loader path chạy được Silver/Gold end-to-end qua 4 wrappers ngày 2026-06-24.
- [Verified] Enterprise ETL runtime trả lời được: target table, source `_Wrk` view, last modified, status, duration/error qua `TableDictionary`, `AuditLog`, và `queryinsights`.
- [Verified] `Meta.usp_GenericLoad` không còn nằm trên critical path của 4 wrappers; rollback/fallback path vẫn tồn tại nhưng không phải đường chạy chính.
- [Deferred] Phase 2 extensions mới trả lời sâu hơn về DQ status, lineage/downstream, và wave/dependency UI.

---

## 7. Kế hoạch áp dụng Enterprise ETL Framework

### 7.1 Mô hình áp dụng

Khuyến nghị cập nhật: **dùng local `Enterprise SupplyChain-Dev.ETL_Framework` làm nền, nâng nó lên full Enterprise ETL contract, rồi dùng nó làm primary runtime/load framework 100% cho Bronze/Silver/Gold; VN chỉ đóng vai trò fallback/extension capability sau Phase 1**.

Clarification sau khi đọc `01_docs/enterprise-etl-framework/source` ngày 2026-06-23:

- [Verified] `01_docs/enterprise-etl-framework/source` nên được dùng như **canonical design guide / naming / deployment / intent reference**.
- [Verified] Phase 1 implementation target vẫn phải bám **live approved Enterprise ETL runtime/load contract** đã reverse-engineer và verify trong repo/hub snapshots: `TableDictionary`, `AuditLog`, `TableDictionary_UpdateLog`, `FabricMapping`, curated refresh wrappers, incremental loaders, `Performance_Logs` surface liên quan.
- [Verified] Vì vậy Phase 1 **không** được pivot sang copy mù guide-only object names như `usp_LogAuditEntry`, `usp_UpdateTableMetadata`, `usp_CurateData_*`, hay `PerformanceLog` table chỉ vì tài liệu mô tả đẹp hơn; chỉ object nào match được live hub evidence hoặc là approved local equivalent mới được xem là bắt buộc trước Phase 1 exit.
- [Likely] Các phần Enterprise ETL nêu thêm qua email như email-based DQ alerts, restart-from-failure semantics, lineage/catalog augmentation là capability thật của Enterprise ETL ecosystem, nhưng với current SupplyChain scope chúng nên được classify rõ thành `Phase 1 observability follow-up` hoặc `Phase 2+ extension` nếu chưa cần để hoàn thành runtime/load cutover.

```text
Phase 1
  Reuse local ETL_Framework hiện có
  Diff/sync missing Enterprise ETL framework objects từ EnterpriseData-Dev
  Local Enterprise ETL TableDictionary / AuditLog / UpdateLog
  Execution manifest seeded from Meta.AssetRegistry + Meta.SilverDagWaveRuntime
  Local Enterprise ETL _Wrk views / current business SQL views
  Local Enterprise ETL loader/wrapper procs
  SQL-only manual wrapper/script execution, no new Fabric pipeline
  Bronze/Silver/Gold execution in dependency-safe order
  Meta.usp_GenericLoad fallback only

Phase 2
  Enterprise ETL DQ extension
  Enterprise ETL Lineage extension
  Enterprise ETL Wave Planner extension
```

### 7.2 Đường triển khai ưu tiên qua local `ETL_Framework`

[Verified] `Enterprise SupplyChain-Dev.ETL_Framework` đã tồn tại và có sẵn một phần Enterprise ETL-style framework, nhưng hiện chưa đủ full Enterprise ETL và đang trỏ legacy `SupplyChain_Warehouse.SCP_Core.*` / `Temp_SCPWarehouse.SCP_Core.*`.

Kế hoạch migration local-first:

1. Baseline/export local `ETL_Framework` hiện tại, bao gồm tables/views/procs/functions và row-level metadata cần thiết.
2. Diff local `ETL_Framework` với `EnterpriseData-Dev.ETL_Framework` để xác định phần thiếu so với full Enterprise ETL contract.
3. Sync/backfill missing Enterprise ETL framework objects vào local `ETL_Framework` sau approval; không drop/recreate object cũ nếu chưa có explicit approval.
4. Giữ legacy `SCP_Core` metadata rows làm history/fallback; không dùng chúng làm target runtime cho v10.
5. Register current v10 Bronze/Silver/Gold objects vào local `ETL_Framework.DW_Developer.TableDictionary`.
6. Map current 3 layers:
   - Bronze: `Enterprise_Lakehouse`
   - Silver: `SupplyChain_Processing_Warehouse`
   - Gold: `SupplyChain_Gold_Warehouse`
7. Export/freeze execution manifest từ current control plane:
   - `Meta.AssetRegistry.depends_on`
   - `Meta.AssetRegistry.source_objects`
   - `Meta.SilverDagWaveRuntime.wave_number`
   - current layer/project/object metadata
8. Bọc existing SQL business logic bằng Enterprise ETL `_Wrk` view/wrapper pattern khi cần, nhưng không rewrite transformation logic.
9. Dùng local Enterprise ETL loader/wrapper procs hoặc generated SQL run script để publish/refresh target tables.
10. Manual execution phải chạy theo manifest:
    - Bronze/reference prerequisites trước
    - Silver theo `wave_number` tăng dần
    - Gold sau khi Silver dependencies hoàn tất
11. So sánh output hiện tại với output qua Enterprise ETL path.
12. Giữ `Meta.usp_GenericLoad` và current VN pipelines làm fallback trong transition, không dùng làm primary runtime.
13. Chỉ sau parity mới bàn tiếp Phase 2 DQ/Data Lineage/Wave.

Scan policy:

- [Verified] Repo/context hiện đã có đủ evidence để viết plan: local `ETL_Framework`, legacy `SCP_Core` metadata, current 3-layer target, `AssetRegistry.depends_on`, `SilverDagWaveRuntime`, và `pl_sc_silver_wave`.
- [Need-verify] Trước khi execute bất kỳ script nào, Phase 1A vẫn phải refresh read-only baseline live vì wave/order/active assets có thể drift theo thời gian.
- [Verified] Không scan live trong lúc update tài liệu nếu không cần mutation hoặc current-run output; scan live được xem là bước execution readiness, không phải prerequisite để sửa plan.

### 7.3 Vai trò của hub `EnterpriseData-Dev.SupplyChain_Warehouse`

[Verified] `EnterpriseData-Dev.SupplyChain_Warehouse` đã tồn tại nhưng hiện rỗng.

Trong kế hoạch cập nhật, hub warehouse này **không phải prerequisite để apply Phase 1**. Nó là future placement/landing zone nếu Enterprise ETL/Rakesh muốn promote một phần SupplyChain objects lên hub sau khi local Enterprise ETL path đã chạy ổn.

Quy tắc:

- Phase 1 không phụ thuộc việc populate hub `SupplyChain_Warehouse`.
- Phase 1 lấy `EnterpriseData-Dev.ETL_Framework` làm reference chuẩn Enterprise ETL để diff/sync framework contract.
- Nếu sau này move/shared objects lên hub, phải tạo work package riêng với parity, security, semantic, và rollback gates riêng.

### 7.4 Những phần không được copy mù

- [Verified] Sequential Enterprise ETL wrapper có thể dùng để establish Phase 1 baseline, nhưng không được xem là final replacement cho Wave Planner.
- [Verified] Không giảm DQ xuống chỉ còn message-only audit logs.
- [Verified] Không bỏ chi tiết `RunLog`.
- [Verified] Không route report sang semantic model mới nếu chưa kiểm tra tương thích PBIR/queryRef.
- [Verified] Không đưa `Meta.usp_GenericLoad` vào target path nếu mục tiêu là Enterprise ETL 100%; nó chỉ là fallback/rollback.
- [Verified] Không xóa legacy `SCP_Core` rows trong local `ETL_Framework` chỉ vì chúng không thuộc v10; xử lý chúng bằng baseline/history/disable/archive strategy sau approval.
- [Verified] Không generate manual `EXEC` script theo alphabetical order hoặc TableDictionary insert order; phải dùng execution manifest seeded từ current dependency/wave metadata.
- [Verified] Không tạo Fabric pipeline mới nếu Enterprise ETL không approve. Phase 1 dùng SQL-only wrappers/manual scripts; nếu sau này Enterprise ETL cho phép thì existing approved pipeline chỉ gọi wrapper đã có.

---

## 8. Kế hoạch bảo toàn Business Logic

### 8.1 Nguyên tắc không thương lượng

[Verified] Existing SQL ETL logic phải giữ nguyên.

Cần bảo toàn:

- joins
- filters
- CASE logic
- window functions
- aggregations
- date logic
- de-duplication rules
- DQ logic
- KPI calculations
- source-to-target behavior

### 8.2 Cơ chế migration

Dùng “lift-and-wrap”, không rewrite:

```text
SQL view/proc VN hiện tại
  -> copy nguyên văn vào _Wrk view tương thích Enterprise ETL hoặc target đã approve
  -> bọc bằng metadata/load mechanism của Enterprise ETL
  -> so sánh outputs
```

### 8.3 Nhóm kiểm thử parity

Mỗi object được migration phải pass:

- Schema parity
- Row count parity
- Key/grain parity
- Duplicate pattern parity
- Null distribution parity
- Date coverage parity
- Metric parity
- DQ parity
- Performance threshold
- Lineage/update log parity

### 8.4 Kiểm soát thay đổi business logic

Mọi thay đổi vào SQL business logic phải trở thành ADR/change request riêng. Việc đó nằm ngoài scope của framework migration.

---

## 9. Kế hoạch bảo toàn `sc_control_tower`

### 9.1 Sự thật semantic hiện tại

- [Verified] `sc_control_tower` refresh completed ngày 2026-06-20.
- [Verified] Report `Forecast Accuracy Gold` vẫn bind vào legacy `Supply Chain Control Tower`, chưa bind vào `sc_control_tower`.
- [Verified] Legacy model vẫn fail DirectLake framing vì thiếu `CogsRollingHelper`.
- [Verified] TMDL của `sc_control_tower` hiện chưa reference 2 physical Gold inventory tables mới hơn: `FactInventoryHealthFutureWeekEnding`, `ProjectedInventoryHealthSubStatus`.

### 9.2 Chiến lược bảo toàn semantic

1. Xem TMDL table names, measures, relationships, và PBIR `queryRef` như API contracts.
2. Export baseline TMDL/PBIR trước mọi framework migration.
3. Build semantic compatibility matrix:
   - physical Gold table
   - semantic table
   - measure table
   - report visual references
   - DAX smoke query
4. Sửa legacy binding debt trước hoặc song song với migration:
   - Option A: rebind `Forecast Accuracy Gold` sang `sc_control_tower` sau khi validate PBIR compatibility.
   - Option B: sửa legacy `Supply Chain Control Tower` bằng cách remove/alias missing refs.
5. Thêm semantic smoke tests vào migration gates.

### 9.3 Kiểm thử semantic bắt buộc

- DAX row counts cho tất cả fact/dim tables.
- Critical KPI measures trả về values.
- Tên PBIR `queryRef` của report tồn tại trong semantic TMDL.
- DirectLake refresh/framing thành công.
- Không còn missing physical table refs.
- Backward-compatible measure aliases được giữ đến khi reports migration xong.

---

## 10. Kế hoạch Migration theo từng giai đoạn

### Giai đoạn 0 — Đánh giá & Discovery

Mục tiêu: đóng băng sự thật hiện tại trước khi di chuyển bất kỳ thứ gì.

Nhiệm vụ:

- Export current Fabric item inventory cho cả 2 workspaces.
- Export warehouse schema/table/view/proc inventory.
- Export TMDL cho `sc_control_tower` và legacy model.
- Export PBIR cho `Forecast Accuracy Gold`.
- Freeze current SQL view/proc definitions.
- Build lineage và dependency graph từ `AssetRegistry`.
- Document current failures/drift.

Tiêu chí thoát phase:

- Gói bằng chứng hoàn tất.
- Không có destructive/live mutation.
- Migration candidate list được approve.

### Giai đoạn 1 — Apply Enterprise ETL Framework 100% cho Bronze/Silver/Gold

Mục tiêu: dùng local `Enterprise SupplyChain-Dev.ETL_Framework` hiện có làm nền, nâng nó lên full Enterprise ETL framework contract, rồi register/repoint current v10 Bronze/Silver/Gold vào local Enterprise ETL path. Phase này là **một workstream duy nhất**: `reuse local ETL_Framework` + `complete full Enterprise ETL framework` + `apply 100% Enterprise ETL cho 3 Medallion layers`.

Phạm vi bắt buộc của Phase 1:

```text
Input giữ nguyên
  -> SQL business logic giữ nguyên
  -> Bronze/Silver/Gold physical layers giữ nguyên
  -> Enterprise ETL framework path thay thế VN runtime path
  -> Semantic/report outputs không đổi
```

Target runtime sau Phase 1:

```text
Enterprise SupplyChain-Dev.ETL_Framework
  -> DW_Developer.TableDictionary registry chính
  -> DW_Developer.AuditLog / TableDictionary_UpdateLog
  -> Enterprise ETL loader/wrapper procs
  -> Bronze: Enterprise_Lakehouse
  -> Silver: SupplyChain_Processing_Warehouse
  -> Gold: SupplyChain_Gold_Warehouse

SupplyChain_Processing_Warehouse.Meta.usp_GenericLoad
  -> fallback/rollback only

Manual execution contract trong Phase 1
  -> no new Fabric pipeline
  -> generated SQL run script hoặc SQL wrapper proc trong local ETL_Framework
  -> execution manifest lấy từ current control plane
  -> Bronze/reference trước
  -> Silver theo wave_number tăng dần
  -> Gold sau Silver dependencies
  -> parity + semantic smoke sau run
```

Không làm trong Phase 1:

- Không port DQ/Data Lineage/Wave thành Enterprise ETL extensions; để Phase 2.
- Không build dynamic Enterprise ETL Wave engine; chỉ preserve current wave/order như static execution contract.
- Không drop/delete legacy `SCP_Core` rows hoặc old VN metadata.
- Không move object sang `EnterpriseData-Dev.SupplyChain_Warehouse` nếu chưa có owner/placement approval.
- Không rewrite SQL business transformations.
- Không tạo Fabric pipeline mới nếu Enterprise ETL không approve.
- Không rebind report/semantic nếu chưa có PBIR/TMDL validation gate riêng.

Ước tính tổng thời gian Phase 1: **5-6.5 ngày làm việc** cho DEV baseline + side-by-side Enterprise ETL path + manifest-based manual execution, tùy quyền deploy, số object cần register, và độ lệch giữa local `ETL_Framework` với full Enterprise ETL. Các estimate dưới đây là [Need-verify] và phải được update sau read-only baseline pack.

**Progress snapshot — cập nhật 2026-06-23 13:25 ICT**

- [x] `Phase 1A` — Read-only baseline, rollback pack, artifact freeze đã hoàn tất.
- [x] `Phase 1B` — Diff local `ETL_Framework` với full Enterprise ETL reference đã hoàn tất.
- [x] `Phase 1C` — `Option A` additive uplift cho local framework đã apply xong cho backlog cần trước mắt của Phase 1.
- [x] `Phase 1D` — current runtime assets đã được register vào local Enterprise ETL registry; checkpoint đã đạt `47/47` assets hiện hành và local `DW_Developer.TableDictionary` đã lên `67` rows sau Phase 1E backfill.
- [x] `Phase 1E` — live-contract correction, `_Wrk` wrapper surface, metadata backfill, và smoke cho overwrite/date-window/datekey đã đạt checkpoint usable; `DW_Developer.usp_IncrementalTableLoad` đã được fix và re-verified GREEN cho `HoldingTransferSnapshotDaily` + `ManufacturingOrderSnapshotDaily`.
- [x] `Phase 1F` — Enterprise ETL `_Wrk`/wrapper coverage đã canonicalize cho active runtime path; business SQL/view/table/semantic contract giữ nguyên, không rewrite business logic.
- [x] `Phase 1G` — manual execution pack `phase1_manual_refresh_manifest_v2` đã regenerate với dependency-order validation `PASS`; canonical staging path dùng `Staging.DemandForecastSnapshotDaily` + `Staging_Wrk.v_DemandForecastSnapshotDaily`; full refresh pack không chạy lại vì không cần cho framework closeout.
- [x] `Phase 1H` — final smoke/audit pass: orphan/deprecated objects remaining `0`, Enterprise ETL incremental staging smoke `Process Complete`, canonical refs clean, freshness/count/grain duplicate checks pass.
- [x] `Phase 1I` — completion report / cutover readiness / Phase 2 backlog packaging đã được tạo trong Phase 1H artifacts; Phase 2 giữ lại orchestration/wave planner/semantic broader smoke.

**Current blocker note**

- [Verified] `DW_Developer.usp_IncrementalTableLoad` **không còn** là blocker của plan này; smoke re-run ngày 2026-06-23 xác nhận cả `HoldingTransferSnapshotDaily` và `ManufacturingOrderSnapshotDaily` đều ghi `Process Start` + `Process Complete` trong local `DW_Developer.AuditLog`.
- [Verified] Manual run pack hiện đã có stable path cho active `DateKey` objects và đã thêm live-contract row `InventoryHistory_Enh.PurchaseOrderSnapshotHistorical`, đồng thời normalize alias drift như `SalesHistory_Enh.v_InvoiceDetailLineLevel` -> `SalesHistory_Enh.InvoiceDetailLineLevel`.
- [Verified] `Staging_Wrk_Wrk` naming smell đã được canonicalize live không full reload: final target là `Staging.DemandForecastSnapshotDaily`, source wrapper là `Staging_Wrk.v_DemandForecastSnapshotDaily`, và Enterprise ETL `DW_Developer.usp_IncrementalTableLoad` dùng `DateRange`/`dfcSnapshot`.
- [Verified] Phase 1 closeout ngày 2026-06-23: `DemandForecastSnapshotDaily` canonicalization đã apply không full reload; cleanup approved đã remove orphan `_LOAD`, deprecated `_Wrk_Wrk` view/schema, và stale metadata row. Semantic/report objects không bị mutate trong Phase 1 này.

#### Phase 1A — Read-only baseline và safety freeze

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1A.01 | Re-read `AGENTS.md`, `CONTEXT.md`, ADR-008, ETL framework summary, workspace compare | 30 phút | xác nhận scope lock và evidence list |
| 1A.02 | Validate login bằng `az account show` và Fabric token read-only | 15 phút | tenant/user/subscription recorded |
| 1A.03 | List Fabric items trong `Enterprise SupplyChain-Dev` | 20 phút | item inventory snapshot |
| 1A.04 | Export metadata của local warehouse `ETL_Framework` | 20 phút | item ID, created/updated, SQL endpoint |
| 1A.05 | Query object inventory local `ETL_Framework`: schemas/tables/views/procs/functions | 30 phút | object inventory CSV/MD |
| 1A.06 | Export definitions của local `DW_Developer` procs/views/functions nếu quyền cho phép | 45 phút | non-destructive DDL snapshot |
| 1A.07 | Query row counts local framework tables: `TableDictionary`, `AuditLog`, `TableDictionary_UpdateLog`, `FabricLoad` nếu tồn tại | 20 phút | row-count baseline |
| 1A.08 | Export sample rows của local `TableDictionary` để chứng minh legacy `SCP_Core` scope | 20 phút | metadata sample baseline |
| 1A.09 | Snapshot current VN `Meta.AssetRegistry`, `Meta.TableDictionary`, `Meta.RunLog`, `Meta.LineageEdge` counts | 45 phút | VN runtime baseline |
| 1A.10 | Snapshot current dependency source: `AssetRegistry.depends_on`, `source_objects`, `next_run_time`, `project`, `canonical_layer` | 45-60 phút | dependency source extract |
| 1A.11 | Snapshot current `Meta.SilverDagWaveRuntime` và `Meta.v_SilverWaveRuntime` theo project/wave/object | 45 phút | wave runtime extract |
| 1A.12 | Snapshot current Bronze/Silver/Gold object inventory từ `Enterprise_Lakehouse`, `SupplyChain_Processing_Warehouse`, `SupplyChain_Gold_Warehouse` | 60 phút | 3-layer object inventory |
| 1A.13 | Export current SQL definitions cho views/procs chứa business ETL logic | 90-150 phút | frozen SQL business logic pack |
| 1A.14 | Export TMDL/PBIR baseline cho `sc_control_tower`, legacy model, và critical reports | 60-90 phút | 04_semantic/report rollback pack |
| 1A.15 | Ghi `CONTEXT.md` checkpoint: evidence location, no mutation, next step | 10 phút | resumability checkpoint |

Exit gate Phase 1A:

- Có baseline read-only đầy đủ.
- Không có live mutation.
- Xác nhận local `ETL_Framework` chỉ là partial Enterprise ETL shell hiện tại.
- Xác nhận current dependency/wave source đã được export mới, không chỉ dựa vào old scan.
- Xác nhận current 3 layers và 04_semantic/report artifacts đã có rollback snapshot.

#### Phase 1B — Diff local `ETL_Framework` với full Enterprise ETL reference

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1B.01 | Export object inventory `EnterpriseData-Dev.ETL_Framework` | 30 phút | reference object list |
| 1B.02 | Export Enterprise ETL reference definitions cho tables/views/procs/functions cần so sánh | 90-180 phút | Enterprise ETL DDL reference pack |
| 1B.03 | Compare schemas: `DW_Developer`, `Performance_Logs`, `Retail_DW`, `dbo` nếu có | 30 phút | schema diff |
| 1B.04 | Compare framework tables: `TableDictionary`, `AuditLog`, `TableDictionary_UpdateLog`, `FabricLoad`, `Source_EDW_CountCheck`, `Source_EDW_AggCheck` | 60 phút | table diff matrix |
| 1B.05 | Compare `TableDictionary` column-level schema với expected 65-col Enterprise ETL contract | 45 phút | column gap list |
| 1B.06 | Compare procs local vs Enterprise ETL 35-proc families | 60 phút | missing/proc-family matrix |
| 1B.07 | Identify minimum proc families required for SupplyChain Phase 1: curated refresh, incremental, audit/update, cleanup | 45 phút | Phase 1 required proc list |
| 1B.08 | Mark optional/deferred proc families: alert/SLA, parquet variants, SCD2/snapshot, non-SupplyChain utilities | 30 phút | deferred list |
| 1B.09 | Identify duplicate/experimental Enterprise ETL variants that should not be blindly copied | 30 phút | standardization note |
| 1B.10 | Produce “local-to-full-Enterprise ETL gap register” with severity: blocker, required, optional, deferred | 60 phút | approved sync backlog |
| 1B.11 | Review gap register with Enterprise ETL/Rakesh/Aric before any local framework mutation | 60 phút | approval notes |

Exit gate Phase 1B:

- Biết chính xác local `ETL_Framework` thiếu gì để đạt full Enterprise ETL contract.
- Có danh sách object/proc/table nào sync vào local.
- Có danh sách object nào không copy vì optional/tech debt/deferred.
- Chưa có destructive operation.

#### Phase 1C — Nâng local `ETL_Framework` lên full Enterprise ETL contract

Execution note (2026-06-22, Option A approved):

- `Option A` là **staged additive sync strategy**, không phải giảm scope của Phase 1.
- Nghĩa là: Phase 1C chỉ sync **minimum additive set** trước để tránh copy mù tech debt/experimental variants từ hub.
- Nhưng exit gate cuối **toàn bộ Phase 1** vẫn giữ nguyên:
  - local `Enterprise SupplyChain-Dev.ETL_Framework` phải cover **100% approved Enterprise ETL runtime/load contract** cho current SupplyChain scope
  - Bronze / Silver / Gold active paths phải chạy qua Enterprise ETL path
  - mọi active current load patterns phải có Enterprise ETL-compatible execution path
  - 04_semantic/report contract vẫn không đổi
- “100% Enterprise ETL” trong Phase 1 được hiểu là:
  - 100% contract cần cho current Medallion runtime của SupplyChain
  - không bắt buộc copy toàn bộ duplicate/experimental/non-SupplyChain hub variants nếu đã chọn 1 standardized Enterprise ETL path tương đương và documented rõ object nào được defer như tech debt/out-of-scope
- Mọi hub-only object không sync trong Option A phải được classify rõ một trong các nhóm:
  - `standardized-out` (duplicate variant, không cần copy)
  - `deferred-noncritical`
  - `non-supplychain utility`
  - `phase2+ candidate`
  - hoặc `required-before-phase1-exit`

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1C.00 | Curate exact Option A sync backlog: map từng hub-only object vào `required-before-phase1-exit` vs `standardized-out/deferred`, và chứng minh current active load patterns vẫn có đường đạt 100% approved Enterprise ETL coverage khi Phase 1 kết thúc | 60-120 phút | curated Option A sync backlog |
| 1C.01 | Tạo deployment script dạng create/additive cho missing tables/views/procs/functions | 120-240 phút | SQL deploy pack |
| 1C.02 | Tạo rollback script non-destructive: restore definitions, disable new wrappers, restore metadata snapshot | 90 phút | rollback pack |
| 1C.03 | Review script để bảo đảm không có `DROP`, `TRUNCATE`, destructive `ALTER`, overwrite table recreation | 45 phút | destructive-safety checklist |
| 1C.04 | Validate object dependency order trong script | 30 phút | dependency order checklist |
| 1C.05 | Dry-run parse hoặc syntax-check script nếu tooling hỗ trợ | 45 phút | syntax check result |
| 1C.06 | Approval gate: Aric/Enterprise ETL/Rakesh xác nhận exact object list sẽ apply | 30-60 phút | explicit approval |
| 1C.07 | Apply create/additive objects vào local `ETL_Framework` DEV | 60-120 phút | local framework objects created/updated |
| 1C.08 | Query inventory lại sau apply | 30 phút | post-apply object inventory |
| 1C.09 | Validate required Enterprise ETL proc families callable trong local `ETL_Framework` | 60 phút | proc smoke result |
| 1C.10 | Validate `TableDictionary`/`AuditLog`/`TableDictionary_UpdateLog` write behavior bằng test object an toàn hoặc dry-run wrapper | 60-90 phút | audit/update smoke result |
| 1C.11 | Confirm legacy `SCP_Core` rows vẫn còn, không bị delete/drop | 15 phút | legacy row preservation check |
| 1C.12 | Update `CONTEXT.md` với applied objects và validation outputs | 15 phút | resumability checkpoint |

Exit gate Phase 1C:

- Local `ETL_Framework` có đủ Enterprise ETL core objects/procs để chạy SupplyChain Bronze/Silver/Gold.
- Không có object hub-only nào bị bỏ qua mà không được classify rõ trong curated Option A backlog.
- Legacy rows không bị mất.
- Audit/update lifecycle chạy được.
- Có rollback pack.

#### Phase 1D — Build metadata mapping từ VN current state sang Enterprise ETL `TableDictionary`

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1D.01 | Extract active assets từ `Meta.AssetRegistry` với layer/schema/object/source/dependency/load_type | 45 phút | active asset extract |
| 1D.02 | Extract current `Meta.TableDictionary` rows đã Enterprise ETL-align trước đó | 30 phút | VN dictionary extract |
| 1D.03 | Build mapping `AssetRegistry -> Enterprise ETL TableDictionary` field-by-field | 90-150 phút | mapping workbook/SQL |
| 1D.04 | Define Bronze registration convention cho `Enterprise_Lakehouse` | 45 phút | Bronze registration rules |
| 1D.05 | Define Silver registration convention cho `SupplyChain_Processing_Warehouse` | 60 phút | Silver registration rules |
| 1D.06 | Define Gold registration convention cho `SupplyChain_Gold_Warehouse` | 60 phút | Gold registration rules |
| 1D.07 | Mark object type: table, view, shortcut/lakehouse table, warehouse table | 30 phút | object-type mapping |
| 1D.08 | Mark update method: insert/overwrite/incremental/datekey based on current behavior | 60-90 phút | update-method mapping |
| 1D.09 | Map keys/grain/watermark/date columns from current registry | 60 phút | key/watermark mapping |
| 1D.10 | Map owner/source/refresh metadata required by Enterprise ETL `TableDictionary` | 45 phút | governance mapping |
| 1D.11 | Map dependency fields needed for manual order: `depends_on`, `source_objects`, `project`, `canonical_layer`, `wave_number` | 60-90 phút | dependency/order mapping |
| 1D.12 | Create execution manifest shape: `run_sequence`, `layer`, `project`, `wave_number`, `schema_name`, `object_name`, `depends_on`, `enterprise_etl_exec_command`, `is_manual_run_enabled` | 60 phút | manifest schema/design |
| 1D.13 | Generate initial execution manifest from `AssetRegistry` + `SilverDagWaveRuntime` extract | 90 phút | execution manifest CSV/SQL |
| 1D.14 | Validate manifest dependency rule: every `depends_on` object must appear in an earlier layer/wave or be documented as external/source dependency | 60-120 phút | dependency validation report |
| 1D.15 | Flag rows requiring Enterprise ETL/Rakesh decision because Enterprise ETL required fields or dependency order are missing | 30-60 phút | open-decision list |
| 1D.16 | Generate INSERT/MERGE script for new v10 rows into local Enterprise ETL `TableDictionary` | 90 phút | metadata registration script |
| 1D.17 | Review script to ensure legacy `SCP_Core` rows are not overwritten | 30 phút | no-overwrite check |
| 1D.18 | Approval gate before metadata insert/update or manifest adoption | 30 phút | approval note |

Exit gate Phase 1D:

- Có mapping đầy đủ từ current v10 objects sang local Enterprise ETL registry.
- Có registration script không phá metadata cũ.
- Mọi missing Enterprise ETL-required field được mark rõ.
- Có execution manifest đủ để chạy manual refresh đúng dependency/wave order.
- Không có object nào bị đưa vào manual run nếu dependency chưa được resolve.

#### Phase 1E — Register/repoint 3 Medallion layers và freeze execution manifest

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1E.01 | Apply Bronze `TableDictionary` rows cho `Enterprise_Lakehouse` | 30-60 phút | Bronze registered |
| 1E.02 | Query Bronze rows sau apply để validate DatabaseName/SchemaName/TableName/ObjectType/UpdateMethod | 30 phút | Bronze validation |
| 1E.03 | Apply Silver `TableDictionary` rows cho `SupplyChain_Processing_Warehouse` | 60-90 phút | Silver registered |
| 1E.04 | Query Silver rows sau apply để validate schema/domain/project mapping | 30 phút | Silver validation |
| 1E.05 | Apply Gold `TableDictionary` rows cho `SupplyChain_Gold_Warehouse` | 45-75 phút | Gold registered |
| 1E.06 | Query Gold rows sau apply để validate semantic-critical serving tables | 30 phút | Gold validation |
| 1E.07 | Validate local Enterprise ETL registry can answer: source, target, update method, last modified, row count placeholder | 45 phút | registry query result |
| 1E.08 | Run `usp_UpdateTableDictionary_ModifiedDate` or Enterprise ETL equivalent on a safe migrated object | 30-45 phút | modified-date smoke |
| 1E.09 | Run `usp_UpdateTableDictionaryModified` or Enterprise ETL equivalent if required by lifecycle | 30 phút | update-log aggregation smoke |
| 1E.10 | Confirm `AuditLog` captures framework operation start/end for test path | 30 phút | audit smoke |
| 1E.11 | Freeze manifest version `phase1_manual_refresh_manifest_v1` after registration | 30 phút | versioned manifest |
| 1E.12 | Validate manifest uses registered Enterprise ETL TableDictionary rows, not legacy `SCP_Core` rows | 30 phút | no-legacy-target check |
| 1E.13 | Validate manifest sort order: Bronze/reference first, Silver by `project + wave_number`, Gold last | 45 phút | manifest order check |
| 1E.14 | Update `CONTEXT.md` với object counts registered by layer và manifest version | 10 phút | checkpoint |

Exit gate Phase 1E:

- Local Enterprise ETL `TableDictionary` trỏ đúng 3 current layers.
- Metadata cũ `SCP_Core` không bị xóa.
- Enterprise ETL lifecycle update/audit chạy được trên at least one safe migrated object.
- Execution manifest v1 tồn tại và được validate không dùng alphabetical/order-by-name làm thứ tự chạy.

#### Phase 1F — Bọc business SQL bằng Enterprise ETL `_Wrk`/wrapper pattern, không rewrite

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1F.01 | Chọn first pilot domain/object set có blast radius thấp | 30 phút | pilot list |
| 1F.02 | Export current SQL business logic cho pilot objects | 45 phút | SQL baseline |
| 1F.03 | Create Enterprise ETL-compatible `_Wrk` view definition bằng cách copy SQL text nguyên văn hoặc reference existing view | 60-120 phút | `_Wrk` view script |
| 1F.04 | Diff SQL text trước/sau để chứng minh no business rewrite | 30 phút | SQL diff result |
| 1F.05 | Validate `_Wrk` view compiles/returns schema | 30-60 phút | compile/schema result |
| 1F.06 | Create/prepare Enterprise ETL wrapper call cho pilot object | 45 phút | wrapper call script |
| 1F.07 | Run pilot wrapper in side-by-side/safe mode nếu có target side-by-side | 60-120 phút | pilot run log |
| 1F.08 | Compare pilot output schema/row count/key/grain/current KPI slice | 60-120 phút | pilot parity result |
| 1F.09 | Repeat steps 1F.02-1F.08 for remaining Bronze objects | 0.5-1.5 ngày | Bronze wrapper coverage |
| 1F.10 | Repeat steps 1F.02-1F.08 for remaining Silver objects | 1-2 ngày | Silver wrapper coverage |
| 1F.11 | Repeat steps 1F.02-1F.08 for remaining Gold objects | 0.5-1 ngày | Gold wrapper coverage |
| 1F.12 | Capture exceptions where Enterprise ETL wrapper cannot support current pattern without extension | 45 phút | exception register |

Exit gate Phase 1F:

- Mỗi object migrated có SQL baseline, Enterprise ETL wrapper path, và parity result.
- Không có SQL business logic rewrite.
- Exceptions được ghi thành decision items, không sửa lén trong framework migration.

#### Phase 1G — Build SQL-only manual execution theo manifest, không tạo pipeline mới

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1G.01 | Confirm no-new-pipeline constraint with Enterprise ETL/Aric for Phase 1 manual refresh | 15-30 phút | execution constraint note |
| 1G.02 | Define SQL wrapper strategy: existing Enterprise ETL proc calls only, new SQL wrapper proc if approved, or repo-generated `.sql` run script if no new live proc allowed | 45 phút | wrapper strategy decision |
| 1G.03 | Define manual run naming convention, ví dụ `phase1_manual_refresh_all.sql`, `phase1_manual_refresh_silver_wave_0.sql` | 30 phút | file/proc naming decision |
| 1G.04 | Generate Bronze/reference `EXEC` block từ manifest where `layer in ('Bronze','Reference')` | 60 phút | Bronze manual SQL block |
| 1G.05 | Generate Silver wave 0 `EXEC` block từ manifest where `layer='Silver' and wave_number=0` | 45-60 phút | Silver wave 0 SQL block |
| 1G.06 | Generate Silver wave 1 `EXEC` block từ manifest where `layer='Silver' and wave_number=1` | 45-60 phút | Silver wave 1 SQL block |
| 1G.07 | Generate Silver wave 2+ blocks nếu project có deeper wave chain | 45-90 phút | Silver wave 2+ SQL blocks |
| 1G.08 | Generate Gold `EXEC` block từ manifest where `layer='Gold'`, placed after all required Silver waves | 60 phút | Gold manual SQL block |
| 1G.09 | Add comment headers before every block with source manifest version, layer, project, wave, object count | 30 phút | readable run script |
| 1G.10 | Add Enterprise ETL `AuditLog` start/end/error logging around run-level and object-level execution if supported by local procs | 60-120 phút | audit-wrapped script/proc |
| 1G.11 | Add per-object call to Enterprise ETL update-log/modified-date proc after successful object refresh | 60 phút | modified tracking integrated |
| 1G.12 | Add stop-on-failure behavior: if one object in a wave fails, do not continue to later waves/Gold until triaged | 45-60 phút | failure control rule |
| 1G.13 | Dry-run script generation only: inspect commands, no data mutation | 30-60 phút | generated SQL review |
| 1G.14 | Static dependency validation: compare script order against manifest order and fail if any `depends_on` appears later than dependent object | 60-120 phút | order validation report |
| 1G.15 | Pilot manual run on 1-2 low-risk objects in side-by-side mode | 60-120 phút | pilot run result |
| 1G.16 | Run Bronze/reference manual block if pilot passes | 60-120 phút | Bronze run result |
| 1G.17 | Run Silver manual blocks wave-by-wave, sequential inside each wave unless parallel sessions are explicitly approved | 120-300 phút | Silver wave run results |
| 1G.18 | Run Gold manual block only after Silver wave success is documented | 60-180 phút | Gold run result |
| 1G.19 | Capture duration per object from Enterprise ETL `AuditLog` and compare with current VN `RunLog` where available | 60-120 phút | runtime comparison |
| 1G.20 | Save final manual run script/manifest evidence into repo artifact folder before Phase 1 signoff | 45 phút | reproducible manual refresh pack |

Exit gate Phase 1G:

- Bronze/Silver/Gold can run from Enterprise ETL wrapper entrypoints or generated manual SQL scripts.
- No new Fabric pipeline is required.
- Script order matches manifest order, not alphabetical order.
- Silver runs by ascending `wave_number`; Gold does not run before Silver dependencies are complete.
- `Meta.usp_GenericLoad` is not called in Enterprise ETL target path.
- Enterprise ETL logs identify object, command, start/end/error.

#### Phase 1H — Parity validation và semantic smoke

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1H.01 | Build table-level schema parity queries | 60 phút | schema parity script |
| 1H.02 | Run schema parity for Bronze | 30-60 phút | Bronze schema result |
| 1H.03 | Run schema parity for Silver | 60-90 phút | Silver schema result |
| 1H.04 | Run schema parity for Gold | 45-75 phút | Gold schema result |
| 1H.05 | Build row-count parity queries by table and business slice | 90 phút | row-count parity script |
| 1H.06 | Run row-count parity for Bronze/Silver/Gold | 120-240 phút | row-count report |
| 1H.07 | Build key/grain duplicate checks using existing grain rules | 90 phút | key/grain script |
| 1H.08 | Run key/grain duplicate checks | 120-240 phút | duplicate/grain report |
| 1H.09 | Build null distribution and date coverage checks for critical columns | 90 phút | null/date script |
| 1H.10 | Run null/date coverage checks | 120 phút | null/date report |
| 1H.11 | Build metric/KPI parity queries for semantic-critical Gold tables | 120 phút | KPI parity script |
| 1H.12 | Run KPI parity on `ForecastAccuracy_DW`, `InventoryHealth_DW`, `Shared_DW` | 120-240 phút | KPI parity report |
| 1H.13 | Run DAX smoke queries against `sc_control_tower` if source tables affected | 60-120 phút | semantic smoke result |
| 1H.14 | Check DirectLake refresh/framing status for affected semantic model | 30-60 phút | refresh/framing result |
| 1H.15 | Check report visual/queryRef compatibility for critical report pages | 60-120 phút | report smoke result |
| 1H.16 | Triage parity failures into framework issue vs existing data drift vs approved exception | 120-240 phút | exception triage |

Exit gate Phase 1H:

- Parity đạt ngưỡng đã approve.
- Không có KPI/04_semantic/report break.
- Mọi mismatch có owner và classification rõ.

#### Phase 1I — Cutover readiness nhưng chưa port Phase 2

| ID | Bước chi tiết | Thời lượng dự kiến | Output bắt buộc |
|---|---:|---:|---|
| 1I.01 | Confirm Enterprise ETL path có đủ runbook: how to run Bronze/Silver/Gold, how to inspect logs, how to rollback | 60 phút | runbook section |
| 1I.02 | Confirm old VN runtime path vẫn runnable hoặc export được để rollback | 45 phút | rollback validation |
| 1I.03 | Confirm schedules remain disabled/not switched unless explicitly approved | 15 phút | schedule safety check |
| 1I.04 | Produce Phase 1 completion report with object counts, gaps, parity, exceptions, runtime durations | 120 phút | Phase 1 report |
| 1I.05 | Review with Aric/Enterprise ETL/Rakesh | 60-120 phút | signoff notes |
| 1I.06 | Mark `Meta.usp_GenericLoad` as fallback-only in documentation, not as deleted/decommissioned | 30 phút | doc update |
| 1I.07 | Create Phase 2 backlog only for DQ/Data Lineage/Wave; no implementation in Phase 1 | 60 phút | Phase 2 backlog |
| 1I.08 | Package SLA/email alert readiness mapping for SupplyChain Enterprise ETL rows: `Modified`, `RefreshRate`, `JobServer`, `JobName`, `SchemaName`, `TableName` | 45-60 phút | alert-readiness note |
| 1I.09 | Wait at least 5 calendar days or until Aric starts Phase 2 explicitly | 5 ngày calendar | stability/observation window |

Exit gate Phase 1I:

- Phase 1 Enterprise ETL path is documented, validated, and reviewable.
- `Meta.usp_GenericLoad` is fallback/rollback only.
- Phase 2 is intentionally deferred.
- SLA/email alert field mapping is documented, but actual email scheduler/channel integration remains deferred unless explicitly approved.
- No old metadata or runtime object is destroyed.

#### Phase 1 acceptance checklist

- [Verified] Local `ETL_Framework` has enough approved Enterprise ETL core contract for the active SupplyChain runtime path.
- [Verified] `Option A` did not reduce the final active SupplyChain scope; hub-only gaps are implemented, standardized out, or deferred outside the active runtime path.
- [Verified] Local Enterprise ETL `TableDictionary` registers active approved Silver/Gold curated objects; Bronze/source contracts are represented in mart DQ/catalog docs and source notes.
- [Verified] Bronze/source path points to `Enterprise_Lakehouse` for active source objects.
- [Verified] Silver path points to `SupplyChain_Processing_Warehouse`.
- [Verified] Gold path points to `SupplyChain_Gold_Warehouse`.
- [Verified] Active load patterns have Enterprise ETL-compatible execution coverage: overwrite via `usp_RefreshCuratedTableFromView`, incremental/date-key patterns via `usp_IncrementalTableLoad`.
- [Verified] Current business SQL/table/view/semantic contract was preserved except DA-approved live SQL changes that were synced from Fabric into repo.
- [Verified] Enterprise ETL wrappers run without calling `Meta.usp_GenericLoad`; `Meta.usp_GenericLoad` remains fallback only.
- [Verified] Manual execution manifests and wrapper SQL exist under `03_operations/orchestration/`; final SQL Agent order is documented in the root README and main orchestration README.
- [Verified] Manual SQL execution order is wrapper-based: Forecast Silver -> Forecast Gold -> Inventory Silver -> Inventory Gold; Silver wrappers embed `ReferenceMaster_Enh` Wave 00 and Gold wrappers embed `Shared_DW` Wave 00.
- [Verified] No new Fabric pipeline is required for Phase 1 manual/full refresh; SQL Server Agent can call the four wrapper procedures.
- [Verified] Enterprise ETL `AuditLog` shows migrated object activity: latest full run has `56 Process Start` + `56 Process Complete`, `0` errors.
- [Verified] `TableDictionary` is clean for the active runtime: `46` active curated rows, `46` `_Wrk.v_*` refs, `0` active error rows.
- [Verified] Post-run compile/parity smoke passed: `92/92` active target/source checks, no `queryinsights` non-success entries since run start.
- [Verified] `sc_control_tower` read-only smoke passed; item exists and remains Direct Lake on `SupplyChain_Gold_Warehouse`.
- [Verified] Rollback/fallback knowledge is preserved in repo archive and `Meta` is not deleted.
- [Verified] DQ/Data Lineage/Wave enhancement work remains in backlog for Phase 2 and was not half-ported inside Phase 1 closeout.

### Giai đoạn 2 — Port DQ / Data Lineage / Wave sang Enterprise ETL extensions

Mục tiêu: sau khi Enterprise ETL baseline chạy ổn, mới nâng cấp các capability VN thật sự đáng giữ vào Enterprise ETL ecosystem. Không port toàn bộ control plane.

Thời điểm bắt đầu: **không bắt đầu trong Phase 1**. Theo cập nhật hiện tại, Phase 2 được defer ít nhất khoảng **5 ngày calendar** sau Phase 1 để có observation window và để Aric xử lý riêng.

Nhiệm vụ:

- Thiết kế Enterprise ETL DQ extension:
  - `DQRule`
  - `DQGateRun`
  - fail/warn mode
  - post-load hook vào Enterprise ETL wrapper.
- Thiết kế Enterprise ETL Data Lineage extension:
  - source-to-target lineage
  - table/view/proc dependencies
  - 04_semantic/report downstream mapping.
- Thiết kế Enterprise ETL Wave extension:
  - dependency graph
  - wave number
  - execution group
  - optional parallelism/batch size.
- Sửa `PipelineRunLog`/Fabric job-history reconciliation trước khi dùng logs cho ops dashboard.
- Chuyển các extension outputs vào enterprise-facing ops views.

Tiêu chí thoát phase:

- Enterprise ETL path vẫn chạy Bronze/Silver/Gold thành công.
- DQ status trả lời được từ Enterprise ETL-facing surface.
- Lineage trả lời được source -> Bronze -> Silver -> Gold -> 04_semantic/report.
- Wave Planner giữ được dependency-safe execution mà không gọi lại `Meta.usp_GenericLoad`.

### Giai đoạn 3 — Cutover, semantic hardening, và decommission target path cũ

Mục tiêu: chuyển operational ownership sang Enterprise ETL path sau khi Enterprise ETL baseline và extensions đều pass parity.

Nhiệm vụ:

- Chốt canonical semantic path: `sc_control_tower` hoặc repaired legacy model.
- Rebind/fix `Forecast Accuracy Gold` theo PBIR/TMDL validation.
- Bật schedule owner chính thức cho Enterprise ETL path.
- Freeze old VN runtime as rollback-only.
- Document cutover checklist và rollback decision points.

Tiêu chí thoát phase:

- Enterprise ETL path là primary runtime được approve.
- Không 04_semantic/report break.
- Không KPI drift.
- Old VN runtime không còn là primary path, chỉ còn rollback trong window đã approve.

### Giai đoạn 4 — Governance & Observability

Mục tiêu: đạt mức vận hành production-grade.

Nhiệm vụ:

- Enable DQ gate modes: `Off`, `WarnOnly`, `CriticalStops`.
- Activate source contract runs.
- Kết nối Fabric job history reconciliation.
- Thêm capacity/cost monitoring.
- Define alerting path.
- Define Purview/Fabric lineage review.
- Define security matrix và owner model.

Tiêu chí thoát phase:

- Failures route tới owner.
- Dictionary/report trả lời được operational questions.
- Security và DQ ownership được approve.

### Giai đoạn 5 — Tối ưu & nâng cấp tương lai

Mục tiêu: nâng maturity sau khi migration an toàn.

Nhiệm vụ:

- Optimize large Delta tables cho Direct Lake.
- Evaluate materialized lake views chỉ như future enhancement, không phải first migration step.
- Expand incremental/datekey patterns ở nơi source contracts hỗ trợ.
- Adopt Git/deployment pipelines từng bước.
- Retire compatibility/legacy artifacts chỉ sau khi được approve.

Tiêu chí thoát phase:

- Framework migration hoàn tất.
- Legacy components được 99_archive/disable an toàn.
- Roadmap chuyển sang optimization, không còn rescue.

---

## 11. Rủi ro và phương án giảm thiểu

| Rủi ro | Bằng chứng | Tác động | Giảm thiểu |
|---|---|---|---|
| Business logic drift | Migration chạm vào framework quanh SQL | KPI mismatch | copy SQL chính xác, diff definitions, parity tests |
| Semantic break | legacy model fail `CogsRollingHelper`; report vẫn bind legacy | report outage | baseline TMDL/PBIR, rebind/fix legacy, DAX smoke |
| Mất năng lực Control Plane | Enterprise ETL chưa thấy equivalents cho waves/DQ/lineage | operational regression | port DQ/Lineage/Wave vào Enterprise ETL extensions sau Phase 1 |
| Hub target rỗng | `SupplyChain_Warehouse` tồn tại nhưng chưa có user tables | false readiness | xem là landing zone, chưa phải implemented platform |
| Pipeline log mismatch | Fabric failed, Meta vẫn running | ops visibility sai | thêm job-history reconciliation/finalizer |
| Source object drift | failures do thiếu `SupplyChain_Enh_1.*` | load failure | validate source paths trước migration |
| Scalar UDF limitation | live failures từ scalar UDF unavailable | runtime instability | bỏ UDF dependency khỏi pipeline-critical paths |
| DQ inactive/incomplete | `SourceContractRun=0` | bad data có thể publish | activate gates từng bước |
| CI/CD chưa trưởng thành | repo chưa full IaC, ADO blockers | manual drift | adopt Git/deployment theo phase |
| Security chưa định nghĩa | workspace/semantic grants chưa thiết kế đầy đủ | compliance/access risk | security matrix trước production cutover |
| Capacity/concurrency | capacity/race failures trước đây | run instability | giữ waves/batch controls |
| Manual EXEC sai thứ tự | SQL script chạy top-to-bottom nếu order không được generate từ wave/dependency | downstream table sai hoặc fail do thiếu prerequisite | freeze execution manifest từ `AssetRegistry.depends_on` + `SilverDagWaveRuntime`; validate dependency order trước run |
| Không được tạo pipeline mới | Enterprise ETL không approve thêm Fabric item | không có manual orchestration surface mới | dùng SQL-only wrapper/manual run script trong local `ETL_Framework`; future pipeline chỉ gọi wrapper nếu được approve |
| Destructive cleanup | legacy assets vẫn là dependencies | data/report loss | không delete/drop nếu chưa có explicit approval |

---

## 12. Chiến lược Rollback

### 12.1 Nguyên tắc rollback

- Không có irreversible migration step nếu chưa backup/export.
- Không destructive delete/drop trong migration phases.
- Giữ VN current path chạy được đến khi Enterprise ETL path chứng minh parity.
- Giữ 04_semantic/report rollback artifacts.

### 12.2 Lớp rollback

| Lớp | Cách rollback |
|---|---|
| SQL definitions | restore CREATE VIEW/PROC scripts trước đó |
| Metadata | restore registry/TableDictionary snapshot |
| Pipelines | restore Fabric `getDefinition` payload trước đó |
| Semantic model | restore TMDL `getDefinition` trước đó |
| Report | restore PBIR binding trước đó |
| Scheduling | disable Enterprise ETL trigger mới, chỉ re-enable VN trigger đã biết sau approval |
| Data | không overwrite old target trước khi new target pass validation; ưu tiên side-by-side tables |

### 12.3 Điều kiện kích hoạt rollback

Rollback nếu xảy ra bất kỳ điều kiện nào:

- KPI parity fail ngoài tolerance.
- DirectLake refresh fail.
- Critical report visual break.
- Xuất hiện DQ critical failure.
- Row count/grain mismatch.
- Framework logging không identify được failure owner.

---

## 13. Chiến lược Kiểm thử

### 13.1 Kim tự tháp kiểm thử

```text
SQL definition diff
  -> schema/metadata tests
  -> execution manifest / dependency-order tests
  -> row-count/key/grain tests
  -> metric/KPI tests
  -> DQ/contract tests
  -> semantic DAX smoke
  -> report binding smoke
  -> end-to-end pipeline run
```

### 13.2 Kiểm thử bắt buộc theo object

- Object tồn tại ở source và target.
- Column names/types compatible.
- Primary/alternate keys khớp expected grain.
- Duplicate behavior khớp existing output.
- Null distribution không thay đổi bất thường.
- Min/max dates và required history window khớp.
- Row counts khớp theo business slice, không chỉ total.
- DQ rules pass hoặc được accept rõ ràng như warnings.
- Runtime duration nằm trong threshold.
- `TableDictionary`, `AuditLog`, DQ/Lineage/Wave extension outputs đều được update theo phase tương ứng.

### 13.3.1 Kiểm thử execution manifest bắt buộc trong Phase 1

- Manifest có đủ các cột tối thiểu: `run_sequence`, `layer`, `project`, `wave_number`, `schema_name`, `object_name`, `depends_on`, `source_objects`, `enterprise_etl_exec_command`.
- Không có object active nào trong `AssetRegistry` bị thiếu khỏi manifest nếu thuộc migration scope.
- Mọi dependency nội bộ từ `depends_on` phải nằm ở earlier layer/wave hoặc earlier sequence.
- Silver phải được sort theo `project`, `wave_number`, rồi sequence đã approve; không sort theo tên bảng.
- Gold chỉ được xuất hiện sau tất cả Silver dependencies liên quan.
- Script/manual wrapper phải stop-on-failure trước khi qua wave tiếp theo hoặc Gold.
- Manifest version phải được ghi trong run artifact để future rerun biết đang dùng order nào.

### 13.4 Kiểm thử bắt buộc theo 04_semantic/report

- TMDL table references khớp physical Gold tables.
- Measures được PBIR reference đều tồn tại.
- Critical DAX queries trả về expected values.
- DirectLake refresh thành công.
- Report mở không có missing field/measure errors.

---

## 14. Tiêu chí nghiệm thu

### 14.1 Nghiệm thu business

- [Need-verify] Cùng inputs tạo ra cùng outputs.
- [Need-verify] KPIs giống trước migration.
- [Need-verify] Không ảnh hưởng report/dashboard consumers.
- [Need-verify] Business owner sign off parity.

### 14.2 Nghiệm thu engineering

- [Need-verify] Enterprise ETL `TableDictionary` có complete approved rows cho migrated objects.
- [Need-verify] Enterprise ETL `AuditLog`/`TableDictionary_UpdateLog` reconcile với Fabric job history.
- [Need-verify] DQ gates chạy theo mode đã thống nhất.
- [Need-verify] Lineage trả lời được source -> Bronze -> Silver -> Gold -> 04_semantic/report.
- [Need-verify] Rollback artifacts tồn tại và đã được test.
- [Need-verify] Không còn destructive cleanup pending nếu chưa có approval.

### 14.3 Nghiệm thu semantic

- [Need-verify] `sc_control_tower` là approved live semantic contract hoặc legacy model đã được sửa đầy đủ.
- [Need-verify] `Forecast Accuracy Gold` không còn bind vào failing legacy dataset, trừ khi được accept rõ ràng.
- [Need-verify] DirectLake refresh history green sau migration.

### 14.4 Nghiệm thu vận hành

- [Need-verify] Schedule owner được document.
- [Need-verify] Alert owner và escalation channel được document.
- [Need-verify] Failed runs không bị treo `running`.
- [Need-verify] Capacity/concurrency policy được document.

---

## 15. Roadmap tương lai sau khi hoàn tất Migration

### Thắng nhanh

- Sửa stale `inventoryHistory_Enh` project rows về canonical taxonomy.
- Sửa `PipelineRunLog` stuck-running reconciliation.
- Quyết định/sửa report binding khỏi legacy `Supply Chain Control Tower`.
- Thêm enterprise-facing ops view trên Enterprise ETL `TableDictionary + AuditLog + UpdateLog`.
- Document trạng thái rỗng hiện tại của `SupplyChain_Warehouse` và target owner.

### Cải tiến trung hạn

- Populate Enterprise ETL path side-by-side bằng exact SQL logic cho Bronze/Silver/Gold.
- Port source contracts và DQ gates vào Enterprise ETL extension ở `WarnOnly`, sau đó `CriticalStops`.
- Thêm Enterprise ETL-native AuditLog/UpdateLog sync.
- Thêm semantic contract tests vào CI checklist.
- Build security/access matrix.

### Tiến hóa dài hạn

- Adopt Fabric Git/deployment pipelines ở nơi item support đã mature.
- Thêm Purview/Fabric lineage integration.
- Thêm cost/performance baselines.
- Evaluate materialized lake views cho future declarative dependency management sau khi SQL parity hiện tại stable.
- Retire legacy models/pipelines/dataflows chỉ sau explicit approval và rollback window.

---

## Khuyến nghị có bằng chứng

### Khuyến nghị 1 — Local Enterprise ETL-first, không hybrid runtime

[Likely] Dùng local `Enterprise SupplyChain-Dev.ETL_Framework` làm nền, nâng lên full Enterprise ETL contract, apply Enterprise ETL Framework 100% cho Bronze/Silver/Gold trước, rồi mới port DQ/Data Lineage/Wave như extensions.

Lý do:

- Enterprise ETL framework là enterprise-recognized operating pattern.
- Local `ETL_Framework` đã tồn tại nên nên tận dụng làm bootstrap thay vì tạo full framework từ zero.
- Local `ETL_Framework` hiện còn partial và đang trỏ legacy `SCP_Core`, nên phải diff/sync với `EnterpriseData-Dev.ETL_Framework` trước khi register 3 layers hiện tại.
- Giữ `Meta.usp_GenericLoad` làm runner chính sẽ khiến migration vẫn là VN framework, chưa phải Enterprise ETL framework.
- VN có runtime features đáng giữ, nhưng nên port chọn lọc sau khi Enterprise ETL baseline chạy ổn: DQ, Data Lineage, Wave.

### Khuyến nghị 2 — Xem `SupplyChain_Warehouse` là landing zone rỗng

[Verified] Hub `SupplyChain_Warehouse` tồn tại nhưng chưa có user tables/routines.

Vì vậy:

- Không claim migration đã xảy ra.
- Chỉ dùng làm side-by-side target build sau khi có owner/naming/schema decisions.

### Khuyến nghị 3 — Sửa 04_semantic/report debt trước cutover framework lớn

[Verified] Report vẫn bind vào failing legacy dataset.

Vì vậy:

- Không migrate framework khi report contract còn mơ hồ.
- Hoặc rebind sang `sc_control_tower` sau PBIR/DAX validation, hoặc repair legacy model.

### Khuyến nghị 4 — Bảo toàn SQL business logic như nguyên tắc bắt buộc

[Verified] Ràng buộc của user nói business logic không được thay đổi.

Vì vậy:

- Framework migration work packages phải ghi rõ “SQL text copied unchanged” hoặc giải thích mọi deviation như change request riêng ngoài scope.

### Khuyến nghị 5 — Thêm đối soát vận hành trước khi bật schedule

[Verified] Fabric job history và `Meta.PipelineRunLog` lệch nhau đối với failed runs ngày 2026-06-17.

Vì vậy:

- Sửa finalizer/reconciliation trước khi bật lại schedules.

---

## Quyết định còn mở

1. [Need-verify] Enterprise ETL/Rakesh muốn `EnterpriseData-Dev.SupplyChain_Warehouse` host chỉ shared Silver, hay cả một số Gold/serving objects?
2. [Need-verify] Wave Planner nên được port sang Enterprise ETL extension tables hay encode trong Enterprise ETL wrapper procs?
3. [Need-verify] Schedule owner chính thức là ai: Enterprise ETL/enterprise scheduler, Fabric schedules, hay hybrid?
4. [Need-verify] Semantic model canonical là model nào: `sc_control_tower` hay legacy `Supply Chain Control Tower` đã được repair?
5. [Need-verify] DQ gate mode được accept cho first production migration là gì: `WarnOnly` hay `CriticalStops`?

---

## Lập trường cuối

[Verified] Migration nên thay **runtime/load framework và orchestration/governance ownership**, không thay business.

[Likely] Kiến trúc thắng là:

```text
Local ETL_Framework được nâng lên full Enterprise ETL
+ Enterprise ETL Framework 100% cho Bronze/Silver/Gold execution
+ VN DQ / Data Lineage / Wave làm extension sau Phase 1
+ Meta.usp_GenericLoad chỉ là fallback/rollback
+ existing SQL business logic được bảo toàn
+ existing Medallion layers được bảo toàn
+ 04_semantic/report compatibility được bảo vệ
```

Bất kỳ hướng nào khác đều tạo thêm rủi ro không cần thiết cho một platform đã có working data products và downstream consumers đang hoạt động.

---

## Phase 1+ Addendum — Enterprise `_Wrk` Contract Cleanup

[Verified] Phase 1 remains operationally complete. A later live Enterprise pattern scan on 2026-06-23 found one naming-contract cleanup item: the current SupplyChain Silver/Gold warehouses are operationally valid, but still carry legacy duplicate base-schema `v_*` views that are not clean against the Enterprise curated/domain warehouse contract.

Target contract:

- Final curated/domain schemas expose physical final tables only.
- `_Wrk` schemas expose `v_<TableName>` work/source views for `ETL_Framework`.
- Existing duplicate base-schema `v_*` views are compatibility artifacts and must be removed only after dependency audit.

Acceptance:

- `SupplyChain_Processing_Warehouse` base domain schemas have no required `v_*` views.
- `SupplyChain_Gold_Warehouse` base serving schemas have no required `v_*` views.
- `_Wrk.v_<TableName>` views exist for all framework-loaded final tables.
- `TableDictionary` rows continue to point to final `DatabaseName` + `SchemaName` + `TableName`.
- `sc_control_tower` refresh and DAX smoke still pass after any approved Gold cleanup.

Governance:

- Do not rewrite business SQL.
- Do not rename physical final tables.
- Do not change semantic/report table contracts.
- Do not execute `DROP VIEW` cleanup until zero-ref dependency audit is saved and Aric approves the exact drop list.
