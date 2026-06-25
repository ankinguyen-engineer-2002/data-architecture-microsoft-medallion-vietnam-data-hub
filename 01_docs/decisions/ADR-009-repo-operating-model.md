# ADR-009 — Repo Operating Model

Date: 2026-06-23  
Status: Accepted

## Context

After Phase 1 of the Enterprise ETL Framework migration completed, the repository still looked like a reverse-engineering workspace: old architecture versions, live evidence folders, local tool caches, Enterprise ETL guide docs, context logs, mart definitions, and operational scripts all sat near the root.

That shape was useful during discovery, but it was not a clean operating repository.

## Decision

The repo is now organized as a documentation + operations repository.

Current source of truth:

- `01_docs/architecture/current/` — final Enterprise ETL-aligned architecture and generated diagrams.
- `01_docs/enterprise-etl-framework/` — Enterprise ETL guide source and local interpretation.
- `02_marts/` — mart-level SQL definitions, lineage, run order, and history.
- `03_operations/` — ad-hoc/manual orchestration manifests, tools, and operational apps.
- `04_semantic/` — shared semantic model notes and artifacts.
- `00_CONTEXT/` — split context logs, with `00_CONTEXT/current.md` as active append target.
- `99_archive/` — historical architecture snapshots, reverse-engineering evidence, external refs, and local tool state.

## Consequences

- Root-level clutter is intentionally minimized.
- Old v9/v10 knowledge is preserved, not deleted.
- Reverse-engineering evidence remains available, but no longer competes with current architecture docs.
- Manual refresh tooling must use `03_operations/orchestration/*/manifest.json` and dry-run by default.
- Future agents should start from `AGENTS.md`, `00_CONTEXT/current.md`, `README.md`, and `01_docs/architecture/current/`.

## Rejected Alternatives

- Keep the old top-level reverse-engineering folders: rejected because it made the repo look unfinished and ambiguous.
- Delete old evidence: rejected because the migration history is still valuable and deletion would be unsafe.
- Put all docs under one huge folder: rejected because mart operations, architecture, Enterprise ETL framework, and archive need separate ownership boundaries.

