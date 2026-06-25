# ADR-006: Repo Restructure for Documentation-Repo Maturity (Path A)

Date: 2026-05-05

Status: **Accepted** — execution in same session, see commit log

## Context

Trong session 2026-05-05, danh gia hai truc doc lap:

- Truc A — Runtime Architecture (cai ma docs mo ta): ~85-89% (Staff/Principal),
  da cham trong ADR-004.
- Truc B — Repo Infrastructure (folder layout cua repo nay): ~60% (Mid-level),
  chua duoc danh gia o ADR nao truoc day.

Hai path nang cap Truc B da duoc xet:

- Path A — Giu lam Architecture Documentation Repo
- Path B — Nang thanh Fabric IaC Repo (Git Integration + check-in TMDL/Lakehouse/Warehouse defs)

Aric chon **Path A** (2026-05-05) vi:

- IT dang block Azure DevOps/CI-CD permissions (xem `feedback_it_blockers.md`).
- Muc dich chinh cua repo la decision/evidence trail + handover artifact, khong phai deploy target.
- Workspace that song tren Fabric, repo nay document no.

Path B se duoc xet lai khi IT unblock CI/CD permissions, ADR rieng.

## Decision

Ap 4 nhom thay doi de Truc B tu ~60% len ~85% (Senior level cho documentation repo).

### 1. Folder taxonomy phan tang (thay vi flat 16 numbered docs)

Hien trang: 16 file `01_..._md` den `16_..._md` flat trong `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/`.

Target:

```text
99_archive/reverse-engineering/enterprise_supplychain_dev_architect/
|-- 00_overview/
|   |-- 01_super_plan_medallion_refactor.md
|   |-- 02_architecture_blueprint_mermaid.md
|   `-- 03_v9_feature_parity_checklist.md
|-- 10_evidence/
|   |-- 05_deep_audit_protocol.md
|   |-- 06_v9_source_inventory_and_chronology.md
|   `-- 07_v9_capability_evidence_ledger.md
|-- 20_proposals/
|   |-- 04_revised_enterprise_etl_standards_proposal.md
|   |-- 08_v10_gap_matrix.md
|   |-- 09_enterprise_etl_standards_mapping_matrix.md
|   |-- 10_final_v10_amendment_plan.md
|   `-- 12_v10_object_classification_mapping.md
|-- 30_runbook/
|   |-- 11_v10_implementation_readiness_pack.md
|   |-- 13_v10_build_blueprint_after_readiness.md
|   |-- 14_v10_step_by_step_implementation_runbook.md
|   |-- 15_v10_edw_supplement_exit_strategy.md
|   `-- 16_v10_readiness_scorecard_and_v9_cleanup.md
|-- artifacts/
|   |-- enterprise_etl_standards_rebuild/   (xem section 2)
|   |-- build_runs/
|   |-- detail_clone_v9_forecast/
|   `-- readiness_exports/
|-- diagrams/                    (rename tu mermaid/)
|-- 05_tools/
`-- INDEX.md                     (moi - xem section 4)
```

Nguyen tac:

- So prefix giu nguyen de preserve `git log --follow` track lai duoc.
- Khong doi noi dung file, chi `git mv`.
- Gom theo **chuc nang tai lieu** (overview / evidence / proposal / runbook),
  khong gom theo timeline.

### 2. Tach src vs generated trong enterprise_etl_standards_rebuild

Hien trang: `gen_views.py` (source) cung cho voi output (CSV/JSON/SQL).

Target:

```text
artifacts/enterprise_etl_standards_rebuild/
|-- src/
|   `-- gen_views.py
`-- output/
    |-- column_mapping.csv
    |-- ctas_tables.sql
    |-- gold_columns.json
    |-- processing_columns.json
    `-- row_counts.json
```

Output van commit (Aric muon luu evidence trail). Khong gitignore.

### 3. Cleanup .gitignore

Them:

```text
99_archive/reverse-engineering/enterprise_supplychain_dev_architect/.vfscache/
```

(`.vfsmeta/` va `.stubs/` da co roi.)

### 4. Navigation index

Tao moi `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/INDEX.md` — single entry point liet ke 16 docs
theo group + 1-line abstract moi doc. Do phai doc README 38KB.

### 5. Repo naming honesty (DEFERRED)

Ten hien tai `20260413_Fabric_Refactor_Architect` implies infrastructure-as-code.
Path A = documentation repo. Co the rename luc handover thanh
`Fabric_v10_Architecture_Documentation` hoac giu ten cu + clarify scope trong README.

→ **Defer** — ADR rieng neu can. Khong thay doi trong ADR nay.

## Consequences

Positive:

- Truc B tu ~60% len ~85% (Senior documentation repo).
- Onboard nguoi moi nhanh hon: nhin 4 folder hieu structure thay vi scan 16 file.
- Evidence vs proposal vs runbook tach bach — handover Enterprise ETL/Rakesh de hon.
- Source vs generated tach bach — review code change de hon.

Negative / Risks:

- `git mv` 16 file + folder rename → diff lon. Mitigation: 5 commit doc lap
  rollback duoc, message ro "rename only, no content change".
- Link cross-reference giua cac doc co the vo (relative paths). Mitigation:
  grep `](.*\.md)` va `](mermaid/.*)` sau restructure, fix tat ca.
- Mermaid file duong dan trong `02_architecture_blueprint_mermaid.md` reference
  `mermaid/*.mmd` → doi thanh `../diagrams/*.mmd` sau khi rename folder.
- ADR-001..005 hien tai reference `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/XX_*.md` → can update
  paths thanh `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/<group>/XX_*.md`.

## Implementation Plan

Mot session, ~1-2 hour, chia 5 commit doc lap rollback duoc:

1. **Commit 1**: ADR-006 + tao 4 folder + INDEX.md skeleton.
2. **Commit 2**: `git mv` 16 docs vao folder tuong ung. Khong doi noi dung.
3. **Commit 3**: `git mv mermaid/ diagrams/` + move artifact folders vao
   `artifacts/`. Update relative paths trong cac .md.
4. **Commit 4**: Tach `enterprise_etl_standards_rebuild/` thanh `src/` + `output/`.
5. **Commit 5**: Update ADR-001..005 + `.gitignore` (.vfscache) + INDEX.md
   noi dung day du.

Khong dung `99_archive/architectures/v9_april/` (archived).
Khong dung workspace Fabric (Path A scope).

## Rejected Alternatives

### Restructure thanh Path B (Fabric IaC) ngay

Rejected per Aric decision 2026-05-05. IT block CI/CD; Path B effort 5-10
session vs Path A 1-2 session. Path B co the lam sau khi unblock IT.

### Doi prefix so (vd 01-04 → A1-A4)

Rejected. Giu so `01-16` de git history `git log --follow` van track duoc.

### Flatten them — gop ADR vao `99_archive/reverse-engineering/enterprise_supplychain_dev_architect/`

Rejected. ADR thuoc ve repo-level decisions, khong thuoc ve mot version cu
the. Giu `01_docs/decisions/` o root dung convention.

### Gom theo timeline (April-evidence/May-proposal/May-runbook)

Rejected. Timeline-based grouping khong tra loi cau hoi "doc nay de lam gi?"
ma reader can. Function-based grouping (overview/evidence/proposal/runbook)
intent-driven hon.

## References

- [Verified] ADR-004: Architecture Maturity Assessment (Truc A baseline)
- [Verified] Session 2026-05-05 review (Truc B audit)
- [Verified] `feedback_it_blockers.md` (memory) — IT block CI/CD context
- [Verified] adr.github.io — ADR convention reference
