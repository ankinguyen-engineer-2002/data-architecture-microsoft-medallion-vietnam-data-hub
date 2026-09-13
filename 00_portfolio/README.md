# Portfolio layer

This folder is the interview and presentation entry point for the repository.
It does not replace the operating source under `01_docs/`–`05_tools/`; it explains
what was built, why it exists, how it evolved, and where the technical proof lives.

## Start here

DE: [CLAIMS](../03_operations/CLAIMS.md), [azure](../03_operations/azure/README.md),
[databricks](../03_operations/databricks/README.md), [walkthrough](07_interviewer_walkthrough.md).
AIOS/Copilot: [AI enablement](05_ai_enablement.md) **after** marts.

## Reading paths

| Audience | Start here | Continue with |
|---|---|---|
| Hiring manager | [profile](01_profile.md) | [timeline](02_timeline.md), [case studies](04_case_studies.md) |
| Data/Analytics Engineer | [platform map](03_platform_map.md) | [evidence matrix](06_evidence_matrix.md), mart and operations READMEs |
| AI/platform interviewer | marts + Gold first, then [AI enablement](05_ai_enablement.md) | Copilot package; AIOS nested MVP last |
| Presenter | [interviewer walkthrough](07_interviewer_walkthrough.md) | selected diagrams and case studies |

## Evidence policy

Showcase pages use business-neutral names and rounded/semantic measures. Exact
IDs, raw SQL, credentials, private evidence, and sensitive row-level data remain
in the protected technical/evidence surfaces. A claim is not called live unless
its source and verification state are explicit.

## Canonical source map

- Platform architecture: `01_docs/architecture/ashley/` and `01_docs/architecture/current/`
- Business data products: `02_marts/forecast_accuracy/` and `02_marts/inventory_health/`
- DataOps/runtime: `03_operations/` and `05_tools/`
- Semantic/AI enablement: `04_semantic/` and `06_enterprise_control_tower/`
- Historical/reference material: `99_archive/` and the nested-repository registry

## Portfolio diagrams

- [Master portfolio map](diagrams/00_master_portfolio_map.svg) — showcase map,
  two planes and the current upstream → downstream path.
- [Responsibility stack](diagrams/06_responsibility_stack.svg) — phase, problem,
  ownership, proof and status.

- [Lifecycle diagram](diagrams/01_lifecycle.mmd) — the chronological story from
  Azure/Databricks through Fabric, analytics, Copilot, and AIOS.
- [Operating layers](diagrams/02_operating_layers.mmd) — how orchestration,
  runtime, DQ, lineage, semantic contracts, and AI experiences relate.
- [Data product lifecycle](diagrams/03_data_product_lifecycle.mmd) — how a
  business requirement becomes a DA-consumable governed product.
- [Copilot enablement](diagrams/04_copilot_enablement.mmd) — how a question
  reaches evidence and where clarification, refusal, and approval occur.
- [Four cadences](diagrams/08_four_cadence.svg) — plane 1 this git vs plane 2
  OT/AWS (pattern). Shared keys, not a Gold→Flink job.

Additional content maps:

- [Technology decisions](10_technology_decisions.md)
- [Business and user map](11_business_and_user_map.md)
- [DataOps ownership](12_operations_and_dataops.md)
- [Maturity and claim language](13_content_maturity_matrix.md)
- [Diagram catalog](14_diagram_catalog.md)
- [Resume bridge](15_resume_bridge.md)
- [File-to-capability map](16_file_to_capability_map.md)
- [Presentation script](17_presentation_script.md)
- [Stage-by-stage detail](18_stage_detail.md)

For the complete repository boundary and nested-repository classification, see
[repository inventory](09_repository_inventory.md).

This layer is intentionally progressive: one master page for orientation, then
technical details in canonical files. Không cần đọc toàn bộ 18 trang để hiểu
portfolio.
