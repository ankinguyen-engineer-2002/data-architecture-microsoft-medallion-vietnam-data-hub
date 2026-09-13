# Repository inventory and reading boundaries

This is the navigation inventory for the super-repository. It is intentionally
an index, not a second copy of source code.

| Surface | Classification | What it proves | Start here |
|---|---|---|---|
| Root repository | active operating source | SCM data platform, DataOps, marts, semantic contracts | `README.md`, `01_docs/`, `02_marts/`, `03_operations/` |
| `01_docs/` | current technical documentation | architecture, ADRs, onboarding, runbooks | `01_docs/architecture/current/README.md` |
| `02_marts/` | active business data products | Forecast Accuracy and Inventory Health contracts | each mart `README.md` |
| `03_operations/` | active operations package | orchestration, wrappers, SQLPROJ and registries | `03_operations/README.md` |
| `04_semantic/` | active analytics/AI contract | TMDL, DAX, semantic and Copilot boundaries | `04_semantic/README.md` |
| `05_tools/` | active repeatability tooling | DQ, parity, sync, lineage and packaging utilities | `05_tools/README.md` |
| `06_enterprise_control_tower/AIOS-Workspace` | nested active product MVP | AI-enabled workbench and capability runtime | nested `README.md`, `docs/portfolio/README.md` |
| `06_enterprise_control_tower/ChainOS` | historical predecessor | earlier Supply Chain assistant and salvage source | nested `README.md` |
| Control Tower discovery repo | confidential historical evidence | report/decision discovery and business intelligence research | nested repo README; do not treat as runtime |
| `AIOS-Workspace-Plan-legacy` | legacy plan | superseded AIOS planning material | archive metadata only |
| `enterprisedata-dev-docs` | external reference snapshot | EnterpriseData documentation and reverse-engineering reference | external README; not current SupplyChain truth |
| `99_archive/` | retained history | provenance, prior designs, old evidence | archive README and linked source |

## Classification rules

- `active-operating-source`: current implementation and operational contracts.
- `active-product-mvp`: implementable product whose live/production gates are explicit.
- `historical`: useful provenance, not a deployment source.
- `reference-only`: external or imported material, not ownership evidence.
- `confidential`: never copy to public showcase surfaces.

If a historical snapshot conflicts with current live evidence, current live truth
and the current contract win. The archive remains preserved for provenance.
