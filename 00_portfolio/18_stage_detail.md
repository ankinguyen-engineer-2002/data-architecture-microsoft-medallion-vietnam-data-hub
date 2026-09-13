# Stage-by-stage detail

This is the bridge between the concise timeline and the deep technical folders.

## Stage 1 — Data Engineer (SCM)

The starting point was an SCM data-engineering responsibility: understand the
business source systems, define usable data, and make downstream analysis
repeatable. The primary output is not a dashboard; it is a trustworthy data
contract with an owner, grain, refresh expectation and consumer.

## Stage 2 — Azure and Databricks

The enterprise context spans Azure foundation services, enterprise source
systems and Databricks Spark jobs that terminate after the load. Databricks is
the processing/curation layer for super-large SCM tables, not a 24/7 dock
controller. Exact upstream service inventory is only claimed where the
repository or live evidence verifies it. See
`01_docs/architecture/ashley/overall_architecture_ashley.md` and
`01_docs/architecture/four_cadence_operating_model.md`.

## Stage 3 — Fabric Supply Chain platform

Fabric provides the value-stream serving environment: source/shortcut exposure,
Processing Warehouse, Gold Warehouse and semantic/report handoff. The design
keeps Bronze/Silver/Gold responsibilities distinct and prevents report logic
from becoming an ungoverned second ETL layer.

## Stage 4 — DataOps and platform operation

The work expanded from transformations to operation: dependency-safe wrappers,
metadata registry, audit trail, DQ and freshness gates, lineage, SQLPROJ build
handoff, drift checking, dry-run-first execution and recovery procedures.

## Stage 5 — Data products

Forecast Accuracy and Inventory Health package business logic into reusable
products. Each product has source contracts, Silver/Gold objects, a run order,
DQ expectations, catalog/lineage and semantic impact.

## Stage 6 — DA enablement

The platform is designed so DAs can build semantic models and reports without
repeating source joins or inventing business definitions. Measures, date logic,
relationships, RLS expectations and report contracts are documented separately
from physical ETL.

## Stage 7 — Copilot and governed AI

When the organization moved toward Copilot, the engineering problem became safe
conversational access: connect the correct Fabric/semantic surfaces, teach the
business vocabulary, constrain tools, preserve evidence, and refuse unsupported
questions. Copilot is a consumer of governed data, not a replacement for it.

## Stage 8 — Operational automation

Automation is treated as a separate risk tier. Read-only analysis can be enabled
before write-capable actions. Any future action path needs identity, approval,
policy, idempotency, precondition checks, execution receipt and rollback.

## Stage 9 — AIOS Workbench MVP

AIOS generalizes the interaction layer: chat, specialist routing, semantic
planning, research, files, artifacts, execution and durable work. It remains an
MVP for development/high-level testing and inherits the same data, evidence and
security discipline rather than redefining the user's core Data Engineer role.
