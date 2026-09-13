# Interviewer walkthrough

## Five-minute path

1. [CLAIMS](../03_operations/CLAIMS.md) — what is live vs reconstructed vs PIM.
2. [Azure ops](../03_operations/azure/README.md) then one Spark job (`sc_forecast_snapshot.py`).
3. One mart README: Forecast Accuracy or Inventory Health.
4. [11 Agent steps](../03_operations/orchestration/main/README.md) and DQ `50003`.
5. Profile / timeline only if the interviewer wants career context.

## Twenty-minute technical path

1. `03_operations/azure/README.md` — Entra/PIM vs workspace; then Databricks jobs; say reconstructed where labelled
2. `python3 03_operations/tools/validate_upstream_slice.py` then `03_operations/databricks/notebooks/sc_forecast_snapshot.py`. If asked CI/CD or Dev→Prod: `databricks/cicd_and_promotion.md` (not SQLPROJ).
3. `02_marts/forecast_accuracy/README.md`
4. `03_operations/orchestration/main/README.md` (11 Agent steps)
5. DQ standard; Copilot only if asked

## AIOS path (optional, last)

Only after the data foundation is understood, open:

1. `06_enterprise_control_tower/AIOS-Workspace/README.md`
2. `06_enterprise_control_tower/AIOS-Workspace/docs/AIOS-Workspace-San-pham-va-Kien-truc.md`
3. `06_enterprise_control_tower/AIOS-Workspace/docs/review/capability-platform-h1-h9-review-2026-09-05.md`
4. `06_enterprise_control_tower/AIOS-Workspace/docs/review/federated-harness-completion-audit-2026-09-03.md`

The intended conclusion is: strong data engineer who can extend a governed data
platform into AI product experiences, not an AI-first developer detached from data.
