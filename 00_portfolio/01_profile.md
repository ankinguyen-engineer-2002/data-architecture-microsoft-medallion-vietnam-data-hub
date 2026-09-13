# Profile — Data Engineer (SCM) to Data Platform Builder

## One-sentence profile

I am a Supply Chain Data Engineer who builds and operates the Azure → Databricks → Fabric data platform that
allows analysts, planners, and operations teams to work with trusted SCM data.
My core strengths are data engineering, DataOps, platform architecture, semantic
analytics, and translating business decisions into reliable data products. AI and
Copilot are later capability layers on top of that governed foundation.

## What I own technically

- Azure control plane: Entra (PIM for Global Admin / Fabric Administrator),
  subscription DATAWAREHOUSE PROD, ADLS, Azure Databricks workspace, SQL
  Agent host. Workspace RBAC snapshot is Contributor on SCM-Dev — tenant
  admin is elevate-then-revert, not a daily login.
- Databricks Spark jobs for the Forecast + Inventory source slice (seven nightly
  jobs, DateRange/CDC, clusters exit), then Fabric serving. Job JSON in git is
  reconstructed from Bronze contracts (ADR-013), not a workspace export.
- Always-on dock/sorter/ATP control is an adjacent OT/AWS pattern (ADR-012),
  not nightly mart runtime.
- Fabric data flow and platform boundaries.
- Bronze/Silver/Gold data products and business grain.
- Metadata-driven ETL, orchestration, DQ, lineage, audit, and release safety.
- Semantic models, metric authority, and DA/report enablement.
- Copilot context, governed tools, Agent Flows, and bounded automation.
- AIOS as a later, still-MVP, AI-native workbench extension.

## What I do not claim

This repository does not by itself prove a formal enterprise-wide architect title,
ML model training expertise, autonomous production AI, or production readiness of
every AIOS capability. Those claims require separate organizational or live evidence.

## Ownership and AI-assisted development

AI tools were used as implementation accelerators for scaffolding, refactoring,
test drafting, and documentation drafting. Human ownership remains with the
business problem, data definitions, grain and metric contracts, architecture
decisions, security boundaries, acceptance criteria, verification, and release
judgment. The portfolio labels local, live, prototype, historical, and blocked
evidence separately.
