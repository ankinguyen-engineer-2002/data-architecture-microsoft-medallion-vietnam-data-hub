# Ashley enterprise architecture (end-to-end)

Portfolio context: [`../../../00_portfolio/02_timeline.md`](../../../00_portfolio/02_timeline.md)
and [`../../../00_portfolio/10_technology_decisions.md`](../../../00_portfolio/10_technology_decisions.md).

This is the enterprise-context layer: Azure foundation, Databricks compute and
curation, Fabric hub/value-stream boundaries, and scheduler/control-plane
ownership. Exact service names are marked by evidence level inside the deep dive;
do not promote `Likely` or `Need-verify` language to a runtime fact.

Canonical goal: capture the **end-to-end operating model** (infrastructure + orchestration patterns + responsibility boundaries) so VN domain implementation aligns with US enterprise orchestration.

Lakehouse compute on this path is Spark **batch and micro-batch**. Sub-second
operational loops are documented in
[`../four_cadence_operating_model.md`](../four_cadence_operating_model.md)
and ADR-012 (AWS MSK/Flink + plant edge; not VPS; not always-on Databricks).

## Overview (recommended)

![Overall architecture overview — PNG preview](overall_architecture_ashley_overview.png)

## Scheduling patterns (anti-pattern vs preferred)

![Scheduling patterns (anti-pattern vs preferred)](overall_architecture_ashley_scheduling_patterns.svg)

## Deep dive

- Main doc: `01_docs/architecture/ashley/overall_architecture_ashley.md`
- Legend / glossary: `01_docs/architecture/ashley/overall_architecture_ashley_legend.md`
