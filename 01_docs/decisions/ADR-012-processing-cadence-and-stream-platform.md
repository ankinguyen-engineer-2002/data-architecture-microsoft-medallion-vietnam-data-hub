# ADR-012: Processing Cadence Split And Stream Platform Placement

Date: 2026-09-13

Status: **Accepted as architecture boundary**

Confidence:

- **[Verified]** Lakehouse cadence, objects, and cost-control patterns in this
  repository (Fabric runtime, marts, `ETL_Framework`, DQ windowing).
- **[Owner-confirmed]** True streaming for operational control runs on a
  **separate platform** (Kafka → Flink), not as always-on Databricks.
- **[Likely / Need-verify]** Exact AWS account, MSK cluster name, Flink
  runtime, and plant/CDC edge hosts. Do not invent instance IDs.

This ADR does **not** change Bronze/Silver/Gold SQL, wrappers, or DQ gates.

## Context

The operating repository is Fabric-heavy by design (`ADR-007`). Upstream Azure
and Databricks are documented as enterprise compute, not copied as platform
code. Recent DE narrative work over-weighted “streaming on the lakehouse.”
That conflicts with three facts:

1. **Volume on the DE path is batch-scale.** ADR-011 records live Bronze
   `SupplyChain_Enh.DemandForecastSnapshotDaily` at ~11.0B rows; InvoiceDetail
   ~296.7M; InvoiceHeader ~63.2M. Incremental forecast staging uses
   `usp_IncrementalTableLoad` / `UpdateMethod = DateRange` / **30-day** window
   (`final_enterprise_etl_runtime_architecture.md`). DQ **must not**
   full-scan billion-row Bronze. Spark exists to shuffle and curate **this**
   class of table, including multiple SCM tables in one night.
2. **Consumers of this repo are hour/overnight.** Forecast Accuracy and
   Inventory Health Gold wrappers are handed to SQL Server Agent. Planner
   grain is snapshot day/week, not sub-second.
3. **Always-on Spark is the expensive option.** Databricks Structured
   Streaming can run as `availableNow` (process backlog, **exit**) or as a
   long-running query. The latter holds jobs compute 24/7 and increases cloud
   storage listing/commit cost. That is the wrong default for furniture SCM
   planning data.

Meanwhile, Ashley-style operations (Make-to-Stock + Make-to-Order, CDC/RDC,
ADS fleet, ASRS/sorter, mill) **do** have true-stream problems: dock
assignment, multi-pack divert, ATP + cube lock, sawmill cut. Those loops
close on **PLC / WCS / driver app / web slot**, with SLA in milliseconds to
low seconds. They are owned by Software Engineering / OT, not by the Fabric
mart runtime.

## Decision

Split processing into **four cadences**. Put each cadence on the platform
that matches SLA, cost, and who actuates the next step.

| Cadence | SLA | Platform | Compute posture | DE ownership |
|---|---|---|---|---|
| A. Batch | hours / overnight | Azure landing → Databricks Spark/Delta → Fabric | Large jobs cluster, **terminate** | **Owned** (ingest/curate/publish + SCM marts) |
| B. Micro-batch | ~5–15 minutes | Databricks Structured Streaming / Auto Loader with `trigger(availableNow=True)` or a short `processingTime`, still **job-scoped** | Cluster runs the backlog, **exits** | **Owned** as incremental lakehouse ingestion, not as plant control |
| C. Operational stream | < 1–2 s, often sub-second | **AWS MSK (Kafka) → Apache Flink** (+ Redis/DynamoDB where a hot key is required) | Always-on, **narrow**, next to the decision | **Keys only today**: SKU, warehouse, transfer, cube, PO/container, weekly ATP. No live Gold→Flink job in this repo. Not the Flink cluster |
| D. Edge / OT loop | < 100 ms–sub-second on the line | **On-prem industrial host** on the plant/CDC OT VLAN (IPC / WCS server), optional Flink/PLC gateway | Always-on **beside the conveyor/gate**, not in a public VPS | **Not owned.** DE may land *history* of those events into Bronze later |

Cadences A and B are the Azure → Databricks → Fabric thread already in
`three_platform_operating_model.md`. Cadences C and D are an **adjacent**
operational plane. They must not be drawn as extra Spark jobs inside this
repo’s runtime.

## AWS vs VPS vs edge — choice and rejection

### Production operational stream (Case 1 yard, Case 3 ATP+cube, inbound dock)

**Choose AWS MSK + Flink** (managed Kafka, not a self-built broker on a VM).

Why AWS rather than “put Kafka on Azure Event Hubs” or “VPS”:

- The inbound-truck control loop already described by operations uses
  **AWS MSK topic `inbound-truck-events`** and a command topic
  `dock-assignment-commands`. Matching that bus avoids a second enterprise
  Kafka.
- MSK is Kafka-protocol, multi-AZ, IAM, private subnets, and has a documented
  sink path (S3 → later Azure Data Lake / Auto Loader). Event Hubs can
  *speak* Kafka, but the control plane for WCS/ADS apps is the MSK bus, not
  the lakehouse.
- Flink is the engine for keyed state, CEP, and geofencing. Spark
  micro-batch is the wrong latency class (see Consequences).

### Production sub-second plant/sorter/mill (Case 2 divert, Case 4 CNC)

**Choose on-prem edge next to the equipment**, on the OT network.

A public-cloud round trip (even AWS in the same continent) is not the
primary path for a 1.5–2.5 m/s sorter or a sawmill scan at several m/s.
The actuator is a PLC/WCS on the local VLAN. Cloud Flink may still *see*
a copy of events for site-wide decisions; the **diverter command** stays
local.

### VPS (generic VM / “host Kafka myself”)

**Rejected for production.** A VPS does not give plant VLAN adjacency,
MSK-grade disk/ISR, enterprise identity, or an OT change window. It is a
lab shape, not a CDC/RDC control plane.

**Optional, labelled only:** a laptop or internal lab VM may run a single-node
Kafka/Flink **emulation** for contract tests. That is not an architecture
claim and must not appear on the production diagram.

## Mapping to this repository (do not invent a second Bronze)

Lakehouse objects that **feed** or **are constrained by** the stream plane:

| Stream / ops concern | Repo object / contract [Verified] | How they meet |
|---|---|---|
| Forecast / demand snapshots (batch spine) | `Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily`; staging DateRange 30 days; Gold `ForecastAccuracy_DW` | Stream must **not** restated this grain; planners drink Gold |
| On-hand book | `Enterprise_Lakehouse.Inventory_Enh_History.ItemBalance` → Silver `InventoryHistory_Enh` → `InventoryHealth_DW` | GPS/scan **never** overwrite on-hand; optional as-of in-transit column from OT history |
| Transfers / holds | `Manufacturing_Inventory_AFI.TFRHDR` + `TFRDTL`; `v_HoldingTransferSnapshotDaily` | Journal CDC + yard events are faster cousins of the same transfer key |
| ATP weekly vs ATP-now | `SupplyChain_Enh.ATPWeekEnding`; `v_AtpWeekEnding`; ATP forward **removed** from Gold (2026-06-01) | Case 3 Redis lock is a **different surface** than weekly ATP |
| Inbound container / ASN | `SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`; `PurchaseOrderSnapshot` | Same keys a dock job would join; **no** scanned Flink pipeline from Gold |
| Production orders | `Manufacturing_ProductionPlanning_AFI.MOMAST` | Mill/line downtime history can land; CNC loop does not |
| Wholesale orders | `Wholesale_Codis_AFI.EXTORD` / `EXTORIT` / `COMAST` | Status stream ≠ Forecast actual history |
| AS400 CDC | `usp_IncrementalTableLoad` `UpdateMethod='CDC'` `SourcePlatform='DB2'`; strip `JO*` journal columns | Micro-batch/incremental **sổ**, not Flink divert |
| Spark cluster metadata | `TableDictionary` columns `DataBricksClusterVersion`, `DataBricksNodeType`, `DataBricksClusterRange` | Batch/micro-batch jobs, not 24/7 plant stream |
| Publish | `Enterprise_Lakehouse` shortcuts; UC `edw_dev` mirror [enterprise scan]; SQL Agent wrapper order in `03_operations/orchestration/main/` | OT commands do not go through Agent |

## What this repo will and will not contain

- **Will:** cadence diagram, this ADR, hand-off language in the three-platform
  model, portfolio-safe wording, Bronze/Silver/Gold as today.
- **Will not:** Kafka topic configs, Flink job JARs, MSK Terraform, or a fake
  `02_marts` “realtime ATP” fact that contradicts the 2026-06-01 Gold contract.
- **Will not:** Fabric Eventstream 24/7 for ADS GPS as a DE cost center.

## Consequences

- Interview / portfolio language: Databricks = **Spark batch + micro-batch on
  super-large tables**. True stream = **AWS MSK + Flink**, edge for the line.
- Cost: DBU spend stays on terminated jobs. Always-on spend stays on the
  **narrow** Kafka/Flink (and plant IPC), where delay is billed as detention,
  jammed sorter, or over-cubed truck — not as a Spark warehouse.
- Dual-scheduler rule unchanged: SQL Agent owns mart refresh. Flink owns
  dock/divert commands. Neither schedules the other.
- Open verification: MSK cluster, Flink namespace, edge host standard, and
  the exact S3/ADLS sink that lands OT history into `ashleydevlake`.

## References

- `01_docs/architecture/four_cadence_operating_model.md` (companion)
- `01_docs/architecture/three_platform_operating_model.md`
- `01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md`
- `01_docs/decisions/ADR-011-dq-system-runtime-and-gate-contract.md`
- `05_tools/03_gold_parity/runs/20260714T040440Z_proc_usp_IncrementalTableLoad.sql`
- Databricks: batch vs streaming; `availableNow` vs continuous; cost of
  always-on streaming
- Microsoft: ingest/ETL/stream with Databricks (Event Hubs/IoT as *ingestion*,
  not as WCS actuator)
