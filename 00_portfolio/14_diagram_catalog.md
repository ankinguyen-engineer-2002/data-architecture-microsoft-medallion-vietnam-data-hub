# Diagram catalog

Each diagram has one audience and one job. Do not merge all architecture into a
single unreadable “everything” picture.

| Diagram | Audience | Question answered | Disposition / source |
|---|---|---|---|
| Master portfolio map | all | what exists from upstream to AIOS, and what is outside this git? | **Redrawn after 2026-09-13 audit**: `diagrams/00_master_portfolio_map.mmd` + `.svg` |
| Responsibility stack | hiring manager/interviewer | what did Aric own in each phase? | **Redrawn showcase**: `diagrams/06_responsibility_stack.mmd` + `.svg` |
| Platform hand-off | DE interviewer | why do Azure, Databricks and Fabric coexist? | **Redrawn showcase**: `diagrams/07_platform_handoff.mmd` + `.svg` |
| Four cadences | DE interviewer | lakehouse (this git) vs OT/AWS plane (pattern only)? | **Redrawn showcase**: `diagrams/08_four_cadence.mmd` + `.svg` |
| Upstream slice | DE interviewer | which Spark jobs feed the two marts? | **Redrawn showcase**: `diagrams/09_upstream_slice.mmd` + `.svg` |
| Lifecycle | all | how did the work evolve? | `diagrams/01_lifecycle.mmd` |
| Operating layers | DE/architect | where do scheduler, runtime, DQ, lineage and semantic contracts sit? | `diagrams/02_operating_layers.mmd` |
| Data product lifecycle | DA/DE | how does a business requirement become a governed product? | `diagrams/03_data_product_lifecycle.mmd` |
| Copilot enablement | AI/platform | where does AI enter and where is it blocked? | `diagrams/04_copilot_enablement.mmd` |
| Azure → Databricks → Fabric | enterprise/data | what is the end-to-end infrastructure context? | **Keep as technical detail**: `01_docs/architecture/ashley/overall_architecture_ashley.md` |
| Fabric runtime | DE/ops | how do `_Wrk`, loaders, wrappers and final tables interact? | **Keep as technical detail**: `01_docs/architecture/current/final_enterprise_etl_runtime_architecture.md` |
| Mart anatomy | DA/DE | what does one business mart contain? | **Keep as technical detail**: `01_docs/architecture/current/readme_mart_package_anatomy.mmd` |

## Disposition rules

- **Redrawn showcase** diagrams use conceptual names, short labels and a white
  background so a recruiter can read them without company context.
- **Keep as technical detail** diagrams remain the source of truth for engineers;
  they are linked only after the master page.
- Diagrams under `99_archive/` are **historical/reference-only**. They are not
  reused as current architecture and are not edited for the portfolio.
- Discovery material under the protected Control Tower tree is **confidential**;
  only the sanitized AIOS portfolio pages are public-facing.

## Audit of existing visual material

| Existing family | Audit result | Portfolio treatment |
|---|---|---|
| `01_docs/architecture/ashley/overall_architecture_ashley*` | Strong technical context; detailed labels assume company knowledge and mix current/legacy confidence levels. | Keep all originals for engineering evidence; use the new Master map for interviews. |
| `01_docs/architecture/current/readme_*` and `final_enterprise_etl_runtime_architecture*` | Useful runtime truth and contract detail; too granular for a first-read narrative. | Keep as technical drill-down; link from platform/DataOps pages. |
| `99_archive/.../diagrams/*` | Historical design exploration and reverse-engineering snapshots; not current runtime truth. | Leave untouched under archive; label historical/reference-only. |
| Existing portfolio diagrams `01`–`04` | Good focused explainers but previously lacked one ownership view. | Keep as secondary explainers; Master map + Responsibility stack become the first-read pair. |

The two new showcase diagrams were rendered from Mermaid to SVG and inspected at
large width. They intentionally use short conceptual labels, a white canvas and
separate lanes so the reader can identify flow and ownership without internal
workspace names. Technical diagrams are not silently replaced or re-labelled.

The public diagrams use conceptual names. Exact object names stay in the linked
technical layer.
