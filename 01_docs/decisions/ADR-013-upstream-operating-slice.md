# ADR-013: Upstream Azure / Databricks operating slice

Date: 2026-09-13

Status: **Accepted**

## Context

This git is the Fabric Supply Chain **operating** repository: two live marts
(Forecast Accuracy, Inventory Health), `_Wrk` contracts, Agent wrappers, DQ.
Azure and Databricks are the real compute/landing path in the enterprise, but
their workspace code is not copied here. Portfolio weight therefore looked
Fabric-only. Interviewers outside this company will not treat “shortcut +
SQL warehouse” as a full DE loop.

Dumping the whole Ashley hub (`Source_Data` 64 schemas / 636 tables) would
be both a sanitization failure and a lie about scope. The honest demo is
**the sources those two marts already bind**.

## Decision

1. Reconstruct Azure and Databricks **operating folders** as peers of Fabric
   under `03_operations/azure/` and `03_operations/databricks/`, reverse-mapped from:
   - `02_marts/*/01_bronze/01_enterprise_lakehouse/`
   - catalog `lineage_edges.json` / `run_order.json`
   - `usp_IncrementalTableLoad` (DateRange, CDC DB2/`JO*`)
   - ADR-011 row-scale and bounding columns
   - enterprise scan notes: ADLS `ashleydevlake`, ADF `ashleyv2datafactory`,
     UC catalog `edw_dev` mirror
2. Treat the slice as **demo coverage**, not the company data estate.
   About thirty Bronze objects. Not Retail/HR/Maximo unless a mart SQL
   file references them.
3. Label every upstream artefact:
   - **[Verified]** name or contract exists in this git or a dated live scan
   - **[Reconstructed]** job JSON, notebook, ADLS path, cluster posture —
     inferred from the contract so a DE can operate the slice, **not** an
     export of the live Databricks workspace
4. Do not add Kafka/Flink/VPS/Eventstream into `03_operations/`. ADR-012
   stays an adjacent pattern. Daily DE work for these marts is batch +
   incremental Spark, then Fabric wrappers.
5. Do not invent Entra titles. Access language stays “data-platform
   operations on the slice.”
6. Databricks **versioning and promotion** are documented in
   `03_operations/databricks/cicd_and_promotion.md`: job code + Runtime pin +
   Delta tables are three axes; CI in this git is the slice validator; CD of
   jobs is not implemented here; Dev→Prod is catalog/workspace change, not
   `.dacpac` and not copying Dev Delta to Prod. Do not invent a production
   catalog name (`edw_prod` is not in this git).

## Consequences

- Interview path: Bronze object → Spark job → ADLS/UC → shortcut → `_Wrk`
  → Agent step. Same keys, two platforms.
- Fabric SQL/DQ/Agent remain the serving runtime. Upstream files do not
  schedule Gold.
- If a live Databricks export later appears, it **replaces** reconstructed
  notebooks; it does not sit beside them as a second truth.

## Rejected

- Copying hub warehouses (Retail, Wholesale 200+ tables) into this repo.
- Pretending reconstructed `jobs/*.json` were pulled from Databricks API.
- Always-on streaming jobs for GPS/dock as DE-owned runtime in this git.
