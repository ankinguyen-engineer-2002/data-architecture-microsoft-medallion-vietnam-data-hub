# Readiness Exports

This folder is intentionally excluded from Git except for this README.

The local readiness exports contain live Fabric evidence such as workspace item metadata, pipeline definitions, SQL result snapshots, object inventories, lineage exports, DQ rules/results, run history, and semantic model metadata. They are useful for architecture verification, but they can expose internal environment details and should not be committed to a public or broadly shared repository without explicit approval.

Referenced local baseline:

```text
Enterprise_SupplyChain_Dev_architect/readiness_exports/20260430_230936/
```

If reviewers need to validate the evidence, regenerate a fresh local baseline with:

```bash
python3 Enterprise_SupplyChain_Dev_architect/05_tools/export_v10_readiness_baseline.py
```

Do not commit generated export folders unless the repository visibility and data-sharing policy have been explicitly approved.
