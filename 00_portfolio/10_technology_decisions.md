# Technology decisions and engineering rationale

This page explains why the end-to-end data product crosses each boundary. It is a
technical interview aid, not a vendor inventory. The current repository is
Fabric-heavy by design: upstream Azure/Databricks implementation lives in the
enterprise platform, while this repo owns the Fabric operating contract.

| Area | Technology/pattern | Problem solved | Why this choice fits | Deliberate boundary |
|---|---|---|---|---|
| Enterprise compute | Azure + Databricks Spark | ingest/curate the **two-mart Bronze slice** (~33 tables, seven jobs) | DateRange 30-day on ~11B snapshot, CDC on transfers, jobs terminate | job JSON is reconstructed (ADR-013), not a workspace export |
| Operational stream | AWS MSK + Apache Flink; plant/CDC edge | sub-second dock, divert, ATP+cube, CNC — delay is billed as detention or jammed line | Spark 24/7 and generic VPS fail SLA or cost; Flink/edge sit next to the actuator | DE does not own MSK/Flink; instance IDs `[Need-verify]`; no second Bronze in this repo |
| Serving platform | Microsoft Fabric Lakehouse/Warehouse | provide governed Supply Chain processing and serving surfaces | OneLake integration, SQL, Direct Lake and workspace security fit DA/BI usage | Fabric is not automatically the enterprise scheduler |
| Data architecture | Bronze/Silver/Gold | separate source, conformance and serving responsibilities | protects business grain and makes ownership visible | no layer is proof of freshness by itself |
| ETL runtime | Enterprise ETL `TableDictionary` + `AuditLog` | metadata, audit and repeatable curated loads | aligns the value stream with enterprise operating standards | metadata does not replace DQ or semantic validation |
| Work-view contract | `<Schema>_Wrk.v_<Table>` | stable source projection for curated tables | keeps business SQL composable and loader-compatible | `_Wrk` is not a user-facing business table |
| Orchestration | dependency manifests and wrapper procedures | deterministic run order across shared and mart-specific assets | makes DataOps reviewable and fail-fast | full refresh is never inferred from a successful wrapper alone |
| Quality | persisted DQ results and blocking publish gates | prevent failed/stale data from becoming an approved product | explicit PASS/FAIL evidence and exact-run traceability | DQ status does not grant data access |
| Lineage | live scanner + repository manifest + graph | compare runtime truth with intended source-controlled paths | supports drift detection and sanitized communication | public graph never contains raw credentials or SQL |
| Semantic analytics | Power BI/TMDL/DAX | preserve business measures, relationships and fiscal logic | DA and governed AI share one metric authority | model instructions cannot override permissions or DQ |
| Copilot | Data Agent, Copilot Studio, Agent Flows | give users conversational access to governed analytics | orchestration and presentation sit above deterministic data contracts | AI cannot invent KPI values or authorize writes |
| AIOS runtime | FastAPI + React/Vite + ports/adapters | productize chat, evidence and artifacts around domain data | modular monolith is easier to validate before scale-out | provider, identity and production gates remain explicit |
| Execution safety | isolated subprocess and bounded schemas | support calculations/visuals without running generated code in-process | limits blast radius and makes failure behavior testable | no unrestricted shell/browser/system actions |

## How to discuss these choices

Start with the business constraint, then the data contract, then the technology.
For example: “The planner needs a weekly inventory decision, so the source and
grain stay weekly; the semantic model owns the measure; AI only resolves intent
and explains the evidence.”
