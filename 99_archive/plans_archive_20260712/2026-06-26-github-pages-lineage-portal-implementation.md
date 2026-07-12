# GitHub Pages Lineage Portal Implementation Plan

> **For agentic workers:** implement task-by-task, preserving read-only scanner behavior and keeping all secrets out of the repo and static site.

**Goal:** Build a GitHub Actions-scanned, GitHub Pages-hosted lineage portal for the current Enterprise ETL runtime.

**Architecture:** A Python scanner under `05_tools/06_lineage_portal/scanner/` reads live Fabric REST and SQL endpoint metadata, normalizes it into `lineage_snapshot.json`, and a Vite/React static app renders that snapshot on GitHub Pages. GitHub Actions owns credentialed access; the browser receives only sanitized JSON.

**Tech Stack:** Python 3 stdlib + `pyodbc` for live scan, Vite + React + TypeScript, `@xyflow/react` for graph UI, `elkjs` for layered layout, GitHub Actions Pages deploy.

---

## Task 1: Scanner Core

**Files:**
- Create `05_tools/06_lineage_portal/scanner/*.py`
- Create `05_tools/06_lineage_portal/tests/*.py`
- Create `05_tools/06_lineage_portal/tests/fixtures/minimal_live_input.json`

Steps:

- [x] Add config/auth/Fabric REST/SQL reader modules.
- [x] Add deterministic dependency parser and classifier.
- [x] Add wave builder with cycle/unresolved warnings.
- [x] Add `cli.py` with fixture mode and live mode.
- [x] Add unit tests for parser/classifier/wave builder.
- [x] Run `python3 -m unittest discover -s 05_tools/06_lineage_portal/tests`.

## Task 2: Static UI

**Files:**
- Create `05_tools/06_lineage_portal/site/package.json`
- Create `05_tools/06_lineage_portal/site/vite.config.ts`
- Create `05_tools/06_lineage_portal/site/src/*`
- Create `05_tools/06_lineage_portal/site/public/lineage_snapshot.json`

Steps:

- [x] Build Vite/React app that loads `lineage_snapshot.json`.
- [x] Render ELK-laid-out React Flow graph.
- [x] Add mart/layer/search filters.
- [x] Add detail drawer showing SQL/evidence/warnings.
- [x] Add polished architecture-workbench CSS.
- [x] Run `npm install` and `npm run build`.

## Task 3: GitHub Actions Deployment

**Files:**
- Create `.github/workflows/lineage-portal.yml`
- Update `05_tools/README.md`
- Create `05_tools/06_lineage_portal/README.md`

Steps:

- [x] Add workflow dispatch/schedule triggers.
- [x] Install ODBC driver and Python dependency.
- [x] Run scanner live into `site/public/lineage_snapshot.json`.
- [x] Build static site.
- [x] Upload and deploy Pages artifact.
- [x] Document required GitHub secrets.

## Task 4: Verification And Context

**Files:**
- Update `00_CONTEXT/current.md`

Steps:

- [x] Run Python tests.
- [x] Run scanner fixture mode.
- [x] Run frontend build.
- [x] Grep repo changes for pasted secrets.
- [x] Append context checkpoint.
- [x] Commit implementation.
