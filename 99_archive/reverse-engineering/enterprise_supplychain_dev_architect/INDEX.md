# INDEX — v10 May Documentation

Single entry point cho 16 docs theo 4 nhom chuc nang. Restructure per ADR-006.

## 00_overview/ — Big picture, doc dau tien

| # | File | Title |
|---|---|---|
| 01 | [01_super_plan_medallion_refactor.md](00_overview/01_super_plan_medallion_refactor.md) | Super Plan: Hybrid Medallion Refactor Cho Supply Chain v9 |
| 02 | [02_architecture_blueprint_mermaid.md](00_overview/02_architecture_blueprint_mermaid.md) | Architecture Blueprint: Hybrid Medallion v10 |
| 03 | [03_v9_feature_parity_checklist.md](00_overview/03_v9_feature_parity_checklist.md) | v10 Feature Parity Checklist Against v9 |

## 10_evidence/ — Audit, inventory, ledger

| # | File | Title |
|---|---|---|
| 05 | [05_deep_audit_protocol.md](10_evidence/05_deep_audit_protocol.md) | Deep Audit Protocol: v9 To v10 And Bob Standards |
| 06 | [06_v9_source_inventory_and_chronology.md](10_evidence/06_v9_source_inventory_and_chronology.md) | v9 Source Inventory And Chronology |
| 07 | [07_v9_capability_evidence_ledger.md](10_evidence/07_v9_capability_evidence_ledger.md) | v9 Capability Evidence Ledger |

## 20_proposals/ — Gap, mapping, amendment, classification

| # | File | Title |
|---|---|---|
| 04 | [04_revised_bob_standards_proposal.md](20_proposals/04_revised_bob_standards_proposal.md) | Revised Proposal: Apply Bob SQL DW Standards To Fabric v10 |
| 08 | [08_v10_gap_matrix.md](20_proposals/08_v10_gap_matrix.md) | v10 Gap Matrix |
| 09 | [09_bob_standards_mapping_matrix.md](20_proposals/09_bob_standards_mapping_matrix.md) | Bob Standards Mapping Matrix |
| 10 | [10_final_v10_amendment_plan.md](20_proposals/10_final_v10_amendment_plan.md) | Final v10 Amendment Plan After Deep v9/Bob Audit |
| 12 | [12_v10_object_classification_mapping.md](20_proposals/12_v10_object_classification_mapping.md) | v10 Object Classification Mapping |

## 30_runbook/ — Implementation, scorecard

| # | File | Title |
|---|---|---|
| 11 | [11_v10_implementation_readiness_pack.md](30_runbook/11_v10_implementation_readiness_pack.md) | v10 Implementation Readiness Pack |
| 13 | [13_v10_build_blueprint_after_readiness.md](30_runbook/13_v10_build_blueprint_after_readiness.md) | v10 Build Blueprint After Readiness Verification |
| 14 | [14_v10_step_by_step_implementation_runbook.md](30_runbook/14_v10_step_by_step_implementation_runbook.md) | v10 Bob/Rakesh-Aligned Step-by-Step Implementation Runbook |
| 15 | [15_v10_edw_supplement_exit_strategy.md](30_runbook/15_v10_edw_supplement_exit_strategy.md) | v10 EDW Supplement Exit Strategy |
| 16 | [16_v10_readiness_scorecard_and_v9_cleanup.md](30_runbook/16_v10_readiness_scorecard_and_v9_cleanup.md) | v10 Readiness Scorecard And v9 Cleanup Candidate List |
| 18 | [18_v10_da_table_onboarding.md](30_runbook/18_v10_da_table_onboarding.md) | v10 DA Table Onboarding Runbook |
| 19 | [19_legacy_v8_daily_refresh_recovery.md](30_runbook/19_legacy_v8_daily_refresh_recovery.md) | Legacy v8 Daily Refresh Recovery |

## projects/ — Project-specific mart implementations

| Project | Status | Gold schema | Tables (Silver+Gold) | Notes |
|---|---|---|---:|---|
| [forecast](projects/forecast/) | LIVE (doc set last touched 2026-06-02) | `ForecastAccuracy_DW` | 8 + 7 | Forecast mart docs exist, but current v10 04_semantic/report state should be read from [projects/live_audit_2026-06-15_v10_core_stack.md](projects/live_audit_2026-06-15_v10_core_stack.md). |
| [inventory_health](projects/inventory_health/) | **LIVE (doc set last touched 2026-06-02)** | `InventoryHealth_DW` | 12 active Silver + 6 active Gold | Inventory mart docs exist, but current live semantic state is mixed into `sc_control_tower`; see [projects/live_audit_2026-06-15_v10_core_stack.md](projects/live_audit_2026-06-15_v10_core_stack.md). |

## artifacts/ — Outputs khong phai docs

- `artifacts/bob_standards_rebuild/` — Bob Standards rebuild scripts (`src/`) + outputs (`output/`: column_mapping.csv, ctas_tables.sql, gold_columns.json, processing_columns.json, row_counts.json)
- `artifacts/build_runs/` — Fabric build run scripts + JSON outputs (gitignored)
- `artifacts/detail_clone_v9_forecast/` — v9 detail clones, timestamped (gitignored)
- `artifacts/readiness_exports/` — v10 readiness baselines, timestamped (gitignored)

## diagrams/ — Mermaid (rename tu mermaid/)

24 file `.mmd` (10 super_plan + 5 detail 20-24 + 5 template 30-34 + 2 presentation + 1 README + 1 cross_workspace_flow) +
`render_check/` 23 SVG + 2 PNG. Xem [`diagrams/README.md`](diagrams/README.md).

## 05_tools/ — Analysis scripts

`stability_scan.py`, `stability_scan_gold.py`, `snake_check.py`,
`clone_v9_forecast_detail.py`, `export_v10_readiness_baseline.py`.

---

## Cross-references

- ADR repo-level: [`../docs/decisions/`](../docs/decisions/)
  - ADR-001 — Hybrid Medallion v10 (accepted, implemented)
  - ADR-002 — EDW Supplement Exit Strategy
  - ADR-003 — Bob Standards Compliance Audit (resolved)
  - ADR-004 — Architecture Maturity Assessment (Truc A: 89.3%)
  - ADR-005 — Enterprise Promote Pathway
  - ADR-006 — Repo Restructure for Documentation-Repo Maturity (Truc B target ~85%)
- Repo README: [`../README.md`](../README.md)
- v9 archive: [`../99_archive/architectures/v9_april/`](../99_archive/architectures/v9_april/)
