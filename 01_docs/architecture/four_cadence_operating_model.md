# Two planes, four cadences

Decision: [`../decisions/ADR-012-processing-cadence-and-stream-platform.md`](../decisions/ADR-012-processing-cadence-and-stream-platform.md).
Lakehouse runtime (unchanged): [`current/final_enterprise_etl_runtime_architecture.md`](current/final_enterprise_etl_runtime_architecture.md).
Portfolio map: [`../../00_portfolio/diagrams/08_four_cadence.mmd`](../../00_portfolio/diagrams/08_four_cadence.mmd).

This page is for **presentation and boundary**. It does not replace mart SQL.

## Mapping status (read this first)

The previous draft mixed three things on one picture: (1) objects this git
operates, (2) Spark jobs that live in enterprise Databricks but are not source
in this repo, (3) an OT/AWS control bus the owner described. That looks
complete and is easy to over-claim.

| Plane | What it is | In this git? | Safe to present as |
|---|---|---|---|
| **1. Lakehouse** | Azure landing → Databricks Spark → Fabric hub → SCM Bronze/Silver/Gold | **Yes** — contracts, SQL, wrappers, DQ | Built and operated (`live-user` for marts; Azure/Databricks as upstream hand-off) |
| **2. Operational control** | AWS MSK → Flink; plant/CDC edge to PLC/WCS | **No runtime here** | Adjacent plane, **owner-confirmed pattern**. Instance names `[Need-verify]` |

Inside plane 1, two cadences share Spark:

| Cadence | SLA | Evidence in this repo |
|---|---|---|
| **A. Batch** | hours / overnight | SQL Agent handoff in `03_operations/orchestration/main/` (11 fail-fast steps as of current ops README; Phase 1 closeout was four wrappers). DateRange 30-day forecast staging; ADR-011 ~11B snapshot rows; Gold marts |
| **B. Micro-batch / incremental** | minutes, job then **exit** | `usp_IncrementalTableLoad` DateRange + **CDC DB2/AS400** (`JO*` columns). Auto Loader / `availableNow` is the Databricks *pattern* for files — job JSON is **not** in this Fabric repo (`[Need-verify]` on enterprise Databricks) |

Inside plane 2:

| Cadence | SLA | Evidence |
|---|---|---|
| **C. AWS MSK + Flink** | seconds | Owner-confirmed (inbound-truck topics). Not scanned in Azure/Fabric |
| **D. Plant / CDC edge** | sub-second | Industrial pattern (WCS/PLC). Not a VPS. Not in this git |

**Do not draw** a live arrow “Gold warehouse → Flink cluster.” What exists today
is **shared business keys** (SKU, warehouse, transfer, cube, PO/container). A
feed into Flink state would be a **future publish contract**, not a current
pipeline in `03_operations/`.

## Picture to show (two planes)

```text
PLANE 1 — this repository                          PLANE 2 — adjacent (not this git)
hours / overnight + incremental minutes            seconds / sub-second
                                                   owner: OT / software engineering

AS400/AS600, ERP, files                            GPS/ELD, OCR, POS, scanners, PLC
        │                                                   │
        ▼                                                   ▼
Azure landing (ADLS, ADF, SQL)                     C. AWS MSK (Kafka) → Flink
        │                                              yard, inbound dock, ATP+cube
        ▼                                              (Redis/DynamoDB = hot key only)
Databricks Spark  [jobs EXIT]
  A batch  |  B incremental CDC / files                     │
        │                                                   ▼
        ▼                                            D. Edge on plant/CDC VLAN
Fabric EnterpriseData hub                              WCS / IPC / PLC
  shortcuts = logical Bronze                           divert, CNC — not a VPS
        │
        ▼                                          Hand-off (keys, not a live job):
SCM workspace (this repo)                          ItemSku, WarehouseCode,
  Silver _Wrk → Gold marts                         TransferNumber, TransferCube,
  Agent wrappers → DA                              container / PO, weekly ATP
```

Showcase: [`../../00_portfolio/diagrams/08_four_cadence.svg`](../../00_portfolio/diagrams/08_four_cadence.svg).

Lakehouse-only slide (no AWS): [`../../00_portfolio/diagrams/07_platform_handoff.svg`](../../00_portfolio/diagrams/07_platform_handoff.svg).

## Why Spark is not the dock / diverter

Furniture planning (MRP, forecast, inventory, settlement) is **hour or
overnight**. One Bronze snapshot already sits at ~**11.0B** rows (ADR-011);
invoices are hundreds of millions; many SCM tables move the same night.
Always-on Databricks would bill **warehouse time** to chase GPS. Detention
and a jammed sorter bill **operations**. Those are different wallets and
different SLAs.

So: Spark **starts, processes, exits**. Flink/edge **stay up** and stay
narrow.

## Plane 1 — mapped to objects (verified)

```text
Azure (ADLS ashleydevlake, ADF ashleyv2datafactory, landing SQL)
  → Databricks Spark / Delta / UC edw_dev
  → Fabric mirror / OneLake
  → Enterprise_Lakehouse          logical Bronze (shortcuts)
  → SupplyChain_Processing_Warehouse   Silver, schema _Wrk.v_<Table>
  → SupplyChain_Gold_Warehouse         ForecastAccuracy_DW, InventoryHealth_DW, Shared_DW
  → SQL Agent: ordered wrapper SPs (see `03_operations/orchestration/main/README.md`)
  → sc_control_tower
```

| Product | Bronze shortcut | Silver | Gold |
|---|---|---|---|
| Forecast Accuracy | `SupplyChain_Enh.DemandForecastSnapshotDaily`, CODIS, sales, master | `ForecastHistory_Enh`, `SalesHistory_Enh`, `OpenOrderHistory_Enh`, `ReferenceMaster_Enh` | `ForecastAccuracy_DW` |
| Inventory Health | `Inventory_Enh_History.ItemBalance`, `ATPWeekEnding`, PO, Logility container, `TFRHDR`/`TFRDTL`, `MOMAST` | `InventoryHistory_Enh` | `InventoryHealth_DW` |

Incremental without restating history: staging forecast uses
`usp_IncrementalTableLoad`, `UpdateMethod=DateRange`, `DateKey=dfcSnapshot`,
**30 days**. Same procedure has `UpdateMethod=CDC` for DB2 journals (strip
`JOSEQN`, `JOENTT`, …). That is **sổ** catching up, not a diverter.

DQ (ADR-011) windows huge facts to three completed UTC months. Do not
full-scan Bronze in a gate.

SQL Agent owns mart refresh. Fabric pipelines must not self-schedule the
same wrappers (Ashley anti-pattern). Flink must not become a second mart
scheduler either.

## Plane 2 — what DE actually owes (pattern, not cluster)

DE does not operate MSK. DE owes **keys and measures that a control loop
would join**, if OT asks:

| Control loop | SLA if batch-only | Join keys that **are** in this repo | Not in this repo |
|---|---|---|---|
| Yard / inbound dock | Truck waits at gate (tens of minutes) | PO / container (`PurchaseOrderSnapshot`, Logility container); transfer id + **TransferCube** (`v_HoldingTransferSnapshotDaily`) | GPS, OCR, dock board, forklift counts, MSK topics |
| ATP + delivery cube | Two channels sell the same Saturday slot | Weekly ATP (`ATPWeekEnding`, `v_AtpWeekEnding`); item **Cubes** on master (used in inventory cube math) | Redis lock, POS clickstream, route fill % |
| Multi-pack divert | 3 s late = carton past the arm | `order_id` / SKU as they appear on outbound orders (CODIS `EXTORD`/`EXTORIT` for wholesale) | SICK/Cognex, PLC, belt state |
| Mill cut / yield | Board is already past the saw | `MOMAST` as production-order context | Moisture/vision stream, CNC path |

Hard constraint: Inventory Health Gold **dropped forward ATP** on 2026-06-01.
Do not add `FactAtpNow` to `InventoryHealth_DW`. ATP-now belongs on the
commerce/OT surface.

Cube **is** in the lakehouse (`TransferCube`, item `Cubes`, PO `TotalCubes` on
some PO paths). Labor/forklift **is not**. Do not present “Gold sends labor
to Flink.”

History of OT decisions can land later as files on ADLS and enter plane 1
as incremental load. That arrow is **optional and unverified** until a sink
path exists.

## Platform choice (one paragraph)

- **AWS MSK + Flink** for site-wide decisions (dock, inbound, ATP+cube):
  matches the inbound-truck bus already described (`inbound-truck-events` →
  `dock-assignment-commands`). Managed Kafka, private, not a home-rolled
  broker.
- **Edge on the OT VLAN** for the arm and the saw: 1.5–2.5 m/s belt cannot
  round-trip a public cloud and still hit the diverter.
- **Not a VPS** for production: no plant VLAN, no multi-AZ Kafka, no OT
  change window. A laptop Kafka is a lab, and must not appear on the prod
  slide.

## Presentation order (keep it small)

1. Slide **lakehouse only** (diagram 07): Azure → Spark jobs that exit →
   Fabric SCM marts. One number: ~11B forecast snapshot rows, 30-day
   DateRange, Agent wrappers in ops order.
2. Slide **two planes** (diagram 08): Spark is not dock control; MSK/Flink
   and edge are adjacent; DE owns keys, not the cluster.
3. If asked “do you run Kafka?”: **No, not in this repo.** Pattern is AWS
   MSK; IDs unverified. I would not put that loop on Databricks 24/7.

## Open verification

- Databricks job that actually uses Auto Loader / `availableNow` (enterprise
  workspace, not this SQL repo).
- AWS account, MSK cluster, Flink runtime, topic list.
- ADLS/S3 path for OT history, if any.
- Edge WCS standard per plant.
