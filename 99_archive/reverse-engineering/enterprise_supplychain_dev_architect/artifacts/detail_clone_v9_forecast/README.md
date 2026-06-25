# V9 Forecast Detail Clone

Local-only evidence folder for read-only snapshots of the live SupplyChain v9 Forecast Accuracy implementation.

This folder is intentionally ignored by Git except for this README because exports can contain internal workspace IDs, SQL definitions, pipeline JSON, and operational metadata. Do not commit timestamped clone outputs unless the content is reviewed and explicitly approved.

Use:

```bash
python3 Enterprise_SupplyChain_Dev_architect/05_tools/clone_v9_forecast_detail.py
```

Safety boundary:

- Read-only Fabric REST item inventory and Data Pipeline definition export.
- Read-only SQL metadata export from `SupplyChain_Warehouse`.
- No table data rows are exported from business schemas.
- No Fabric item, SQL object, pipeline, warehouse, lakehouse, semantic model, or report is deleted or modified.
