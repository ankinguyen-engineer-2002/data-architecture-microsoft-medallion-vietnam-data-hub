# Content maturity and claim language

Use these labels consistently in every README, diagram and presentation.

| Status | Meaning | Safe wording |
|---|---|---|
| `live-user` | current product/runtime used by intended users | built and operated for SCM users |
| `live-verified` | fresh read-back or runtime evidence exists for the stated claim | verified live for the stated scope |
| `implemented-local` | source and offline tests prove local behavior | implemented and locally verified |
| `mvp` | bounded usable slice with explicit limits | bounded MVP |
| `draft` | design/prototype, not runtime authority | prototype/reference implementation |
| `blocked` | work exists but release prerequisites are missing | implementation in progress; runtime blocked |
| `historical` | retained for provenance | historical predecessor/evidence |
| `reference-only` | imported/external material | reference material, not ownership/runtime truth |

## Current product labels

| Product | Label | Do not claim |
|---|---|---|
| SCM data platform | `live-user` | exact freshness without a fresh live check |
| Azure control plane | tenant/sub/UPN `live-verified` 2026-06-21; GA/Fabric Admin `owner-confirmed` PIM | living as Global Admin; Workspace Admin on SCM-Dev (snapshot is Contributor) |
| Azure Databricks ops slice | `reference-only` reconstructed from Bronze/load contracts | that `03_operations/databricks/jobs` is a live workspace export |
| Databricks CI/CD + Dev→Prod | `reference-only` pattern; CI in git = slice validator; no job publish | that this git CDs Spark; that a prod catalog named `edw_prod` exists here |
| AWS MSK / Flink / plant edge | `reference-only` / owner-confirmed pattern | that this repo operates Kafka, Flink, or a VPS; that Gold publishes to Flink today |
| Forecast Accuracy | `live-user` | that every historical snapshot is immutable |
| Inventory Health | `live-user` | that all source anomalies are automatically corrected |
| Enterprise ETL migration | `live-verified` for recorded Phase 1 scope | that every enterprise workspace is migrated |
| Copilot governed analytics | `live-user`/scope-specific | autonomous unrestricted AI |
| Adaptive Card chart | `live-verified` bounded MVP | direct image artifact generation |
| Forecast Exception Alert | `blocked` | deployed production runtime |
| AIOS Workbench | `implemented-local` + `mvp` | production identity, scale-out or autonomous action |

The claim language is intentionally conservative. Precision increases credibility
when an interviewer asks for proof.
