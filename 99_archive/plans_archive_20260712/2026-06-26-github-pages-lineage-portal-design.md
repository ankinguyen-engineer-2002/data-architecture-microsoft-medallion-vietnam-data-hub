# GitHub Pages Lineage Portal Design

> Status: approved direction, pending implementation plan.
> Scope: build a hosted lineage portal for the current Enterprise ETL runtime without Streamlit and without local hosting.

## 1. Decision

Build a static GitHub Pages lineage portal backed by a scheduled GitHub Actions scanner.

The browser UI must never connect directly to Fabric SQL endpoints, Fabric REST APIs, Power BI REST APIs, Azure OpenAI, or any other credentialed service. GitHub Actions owns all live scanning and writes a sanitized static snapshot for the page to render.

## 2. Goals

- Scan the live `Enterprise SupplyChain-Dev` workspace, not stale repo-local SQL.
- Reconstruct the current Enterprise ETL lineage:
  - Bronze/source: `Enterprise_Lakehouse`
  - Silver: `SupplyChain_Processing_Warehouse` final tables and `_Wrk.v_<TableName>` views
  - Gold: `SupplyChain_Gold_Warehouse` final tables and `_Wrk.v_<TableName>` views
  - Semantic: single current semantic model `sc_control_tower`
- Auto-classify marts and waves so future marts can be added without hand-building the graph.
- Render a polished, solution-architecture-grade lineage UI on GitHub Pages.
- Keep scanner code under `05_tools` so it remains part of the operating toolset.

## 3. Non-Goals

- No Streamlit.
- No local-hosted app as the operating target.
- No browser-side Fabric, SQL, Power BI, or OpenAI credential.
- No live data mutation, refresh trigger, stored-procedure execution, table DDL/DML, or semantic-model update.
- No reliance on legacy `Meta.AssetRegistry` or `Meta.LineageEdge` as the current runtime source.

## 4. Source Of Truth

The scanner reads live metadata from these current Enterprise ETL surfaces:

1. Fabric REST workspace item inventory for `Enterprise SupplyChain-Dev`.
2. `ETL_Framework.DW_Developer.TableDictionary`.
3. `ETL_Framework.DW_Developer.AuditLog` and `TableDictionary_UpdateLog` where useful for status fields.
4. `SupplyChain_Processing_Warehouse`:
   - final tables
   - `_Wrk` views
   - `sys.sql_modules` definitions for views/procs visible to the scanning identity
5. `SupplyChain_Gold_Warehouse`:
   - final tables
   - `_Wrk` views
   - `sys.sql_modules` definitions for views/procs visible to the scanning identity
6. `Enterprise_Lakehouse` table inventory for Bronze/source nodes.
7. Fabric/Power BI semantic model definition for `sc_control_tower`.
8. Repo manifests only as optional hints when live metadata cannot infer mart/wave cleanly:
   - `03_operations/orchestration/*/manifest.yaml`
   - `03_operations/orchestration/*/manifest.json`
   - generated `run_order.json`

Repo-local `02_marts` remains a shape template for expected presentation, not the primary scan source.

## 5. Architecture

```text
GitHub Actions
  -> Python scanner in 05_tools/06_lineage_portal/scanner/
  -> live Fabric REST + live SQL endpoint reads
  -> normalized lineage snapshot JSON
  -> static site build
  -> GitHub Pages deployment

GitHub Pages
  -> static HTML/CSS/JS
  -> reads lineage_snapshot.json
  -> renders graph, filters, and detail drawers
```

## 6. Proposed Repo Structure

```text
05_tools/06_lineage_portal/
  README.md
  scanner/
    __init__.py
    config.py
    auth.py
    fabric_rest.py
    sql_reader.py
    semantic_reader.py
    dependency_parser.py
    classifier.py
    wave_builder.py
    snapshot_writer.py
    cli.py
  site/
    package.json
    vite.config.ts
    index.html
    src/
      main.tsx
      App.tsx
      graph/
      panels/
      styles/
    public/
      lineage_snapshot.json
  tests/
    test_classifier.py
    test_dependency_parser.py
    test_wave_builder.py
.github/workflows/lineage-portal.yml
```

## 7. Snapshot Contract

The scanner writes a deterministic JSON artifact:

```json
{
  "generated_at_utc": "2026-06-26T00:00:00Z",
  "workspace": {
    "id": "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0",
    "name": "Enterprise SupplyChain-Dev"
  },
  "nodes": [],
  "edges": [],
  "layers": [],
  "marts": [],
  "warnings": [],
  "scan_evidence": {}
}
```

Each node carries:

- `id`
- `display_name`
- `full_name`
- `workspace`
- `database`
- `schema`
- `object_name`
- `object_type`
- `layer`
- `mart`
- `wave`
- `load_method`
- `source_sql`
- `row_count`
- `last_modified`
- `status`

Each edge carries:

- `source`
- `target`
- `relationship_type`
- `confidence`
- `evidence`

## 8. Classification Rules

Layer classification is deterministic first:

- `Enterprise_Lakehouse.*.*` -> `Bronze`
- `SupplyChain_Processing_Warehouse.<schema>.<table>` -> `Silver`
- `SupplyChain_Gold_Warehouse.<schema>.<table>` -> `Gold`
- `SemanticModel.sc_control_tower.<table>` -> `Semantic`

Mart classification uses ordered rules:

1. Schema-to-mart naming conventions:
   - `ForecastAccuracy_DW` -> `forecast_accuracy`
   - `InventoryHealth_DW` -> `inventory_health`
2. `_Wrk` schema ownership:
   - `<SchemaName>_Wrk.v_<TableName>` belongs to the final table `<SchemaName>.<TableName>`.
3. `TableDictionary` source-to-target mapping.
4. Repo manifest hints only when live metadata is ambiguous.
5. Unclassified objects become `shared` or `unresolved` with warnings, not silent guesses.

## 9. Wave Inference

Wave generation is graph-based:

1. Parse each `_Wrk` view definition for three-part and two-part object references.
2. Connect Bronze/source -> Silver `_Wrk` -> Silver final table.
3. Connect Silver final table -> Gold `_Wrk` -> Gold final table.
4. Connect Gold final table -> semantic model tables from `sc_control_tower` definition.
5. Topologically sort Silver nodes per mart into wave `0..N`.
6. Topologically sort Gold nodes per mart into wave `0..N`.
7. Mark cycles, missing dependencies, and cross-mart edges explicitly in `warnings`.

Manual manifest/run-order hints can override display order only when recorded as evidence.

## 10. UI Design

The GitHub Pages UI should look like an architecture workbench, not a dashboard toy.

Required views:

- Lineage Map:
  - left-to-right layout: Bronze -> Silver waves -> Gold waves -> `sc_control_tower`
  - grouped swimlanes by mart
  - shared/reference bands clearly labeled
- Table Detail Drawer:
  - full name
  - layer/mart/wave
  - `_Wrk` view SQL
  - final table contract summary
  - upstream/downstream edges
  - scan evidence and warnings
- Search and Filter:
  - table/schema search
  - mart filter
  - layer filter
  - unresolved-only filter
  - impact mode: upstream/downstream for selected node
- Export:
  - JSON snapshot download
  - SVG or PNG graph export if feasible in the chosen library

Preferred frontend stack:

- Vite + React + TypeScript.
- React Flow or Cytoscape.js for graph interaction.
- ELK layered layout for stable textbook-style dependency placement.

## 11. GitHub Actions Design

Workflow: `.github/workflows/lineage-portal.yml`

Triggers:

- `workflow_dispatch`
- scheduled refresh
- optional push trigger when scanner/site code changes

Secrets:

- `FABRIC_TENANT_ID`
- `FABRIC_CLIENT_ID`
- `FABRIC_CLIENT_SECRET`
- `FABRIC_WORKSPACE_ID`
- `FABRIC_SQL_SERVER`
- `AZURE_OPENAI_ENDPOINT` optional
- `AZURE_OPENAI_API_KEY` optional
- `AZURE_OPENAI_DEPLOYMENT` optional

The workflow must:

1. Install Python dependencies.
2. Run scanner read-only.
3. Validate the snapshot schema.
4. Install frontend dependencies.
5. Build static site.
6. Deploy to GitHub Pages.

## 12. Azure OpenAI Usage

Azure OpenAI is optional enrichment, not the primary classifier.

Allowed use:

- summarize long SQL view definitions for detail drawers;
- propose friendly business labels;
- explain unresolved dependencies in plain English.

Forbidden use:

- deciding authoritative lineage when deterministic SQL/Fabric evidence exists;
- writing credentials into generated JSON or frontend bundles;
- calling Azure OpenAI from the browser.

The API key already shared in chat must be rotated and replaced by a GitHub Actions secret before any implementation run.

## 13. Security Rules

- No credential in repo.
- No credential in static site output.
- No raw access token logged.
- No generated snapshot may include secrets, connection strings with passwords, client secrets, API keys, bearer tokens, or private keys.
- Scanner output should include object names, SQL definitions, and lineage metadata only after confirming this is acceptable for the repository visibility mode.
- If the repository remains public, treat SQL definitions and semantic metadata as potentially sensitive and get explicit approval before deploying Pages publicly.

## 14. Testing And Quality Gates

Scanner tests:

- parse SQL references from representative `_Wrk` views;
- classify layers/marts from live-style fixtures;
- topologically sort waves;
- detect cycles and unresolved refs;
- validate snapshot schema.

Workflow tests:

- run scanner in dry-run/fixture mode without live secrets;
- validate JSON artifact;
- build frontend.

UI tests:

- render graph from fixture snapshot;
- verify no blank canvas;
- verify search/filter works;
- Playwright screenshots for desktop and mobile;
- check text does not overlap in key views.

Security tests:

- grep output artifacts for common secret patterns;
- confirm optional Azure OpenAI config stays server-side in Actions.

## 15. Open Risks

- The current Service Principal can read tables/views and `TableDictionary`, but procedure visibility returned `0` in the read-only probe. Wrapper-procedure visibility may require additional grants or a different scanning identity.
- GitHub Pages public visibility may expose lineage, SQL definitions, and model structure if the repo/site is public.
- Fully automatic mart inference will need conservative unresolved states for future marts until naming conventions are stable.

## 16. Acceptance Criteria

- GitHub Actions can generate a live lineage snapshot without local hosting.
- GitHub Pages renders the lineage portal from that snapshot.
- The graph shows Bronze -> Silver waves -> Gold waves -> `sc_control_tower`.
- A user can search a table and inspect full live-derived SQL/evidence.
- Secrets are not present in repo, logs, site bundle, or snapshot artifact.
- The scanner does not mutate Fabric, Power BI, SQL, or GitHub state except committing/deploying generated static site artifacts through the approved workflow.
