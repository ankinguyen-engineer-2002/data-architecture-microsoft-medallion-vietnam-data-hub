# pl_backup_full_refresh — Live Fabric Sync Runbook

Repo canonical source-of-truth is `pl_backup_full_refresh.json` (this folder). Fabric REST target payload is `pl_backup_full_refresh.fabric_payload.json`, regenerated from the JSON above.

## Current Live Drift

Live definition (audited 2026-07-06 ICT via Fabric REST `getDefinition`) contains:

- `03_Inventory_Silver_W00` calling `[dbo].[Usp_Refresh_InventoryHealth_Silver_W00]` (repo has no source SQL for W00; live W00 body duplicates the two tables that live W01 also refreshes).
- Forecast activities depend on `03_Inventory_Silver_W00` instead of `02_Shared_Staging`.
- No `09_Inventory_Silver_W03` activity; live goes W01 → W02 → Gold, skipping W03 (`AFIStatusSnapshotWeekly, AwdHelper, LastInvoiceWeekly, Cogs52WWeekly`).

Repo canonical 10-step order:

1. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_Shared_ReferenceMaster`
2. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_Shared_Staging`
3. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver_W01`
4. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver_W02`
5. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Silver_W03`
6. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_ForecastAccuracy_Gold`
7. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver_W01`
8. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver_W02`
9. `SupplyChain_Processing_Warehouse.dbo.Usp_Refresh_InventoryHealth_Silver_W03`
10. `SupplyChain_Gold_Warehouse.dbo.Usp_Refresh_InventoryHealth_Gold`

## Live Sync Plan

Two steps, both require explicit Aric approval before execution:

### Step A — Update Fabric pipeline definition (Fabric REST)

Pipeline id: `41948342-d7e7-4166-8638-9af0633e6a49`
Workspace id: `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`

Fabric REST `updateDefinition` requires base64-encoded parts. Dry-run diff first:

```bash
TOKEN=$(az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
PIPELINE_ID=41948342-d7e7-4166-8638-9af0633e6a49
WS_ID=c8d9fc83-18b6-4e1d-8264-0b49eed36fe0

# 1) Fetch current definition (audit only)
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/items/$PIPELINE_ID" \
  --resource https://api.fabric.microsoft.com

# 2) Push canonical definition (LIVE MUTATION — needs approval)
PAYLOAD_B64=$(base64 -i 03_operations/orchestration/backup_pipeline/pl_backup_full_refresh.fabric_payload.json | tr -d '\n')
cat > /tmp/update_definition.json <<JSON
{
  "definition": {
    "parts": [
      {
        "path": "pipeline-content.json",
        "payload": "$PAYLOAD_B64",
        "payloadType": "InlineBase64"
      }
    ]
  }
}
JSON
az rest --method POST \
  --url "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/items/$PIPELINE_ID/updateDefinition" \
  --resource https://api.fabric.microsoft.com \
  --body @/tmp/update_definition.json
```

Post-update verification:

```bash
az rest --method GET \
  --url "https://api.fabric.microsoft.com/v1/workspaces/$WS_ID/items/$PIPELINE_ID/getDefinition" \
  --resource https://api.fabric.microsoft.com
```

Diff against `pl_backup_full_refresh.fabric_payload.json`; activity names 01–10 must match. `Usp_Refresh_InventoryHealth_Silver_W00` must NOT appear.

### Step B — Optional live cleanup of `Usp_Refresh_InventoryHealth_Silver_W00`

If Aric confirms the W00 wrapper is not used anywhere else:

```sql
-- Read-only verification first
SELECT p.name, o.type_desc, m.definition
FROM sys.procedures p
JOIN sys.objects o ON p.object_id = o.object_id
JOIN sys.schemas s ON p.schema_id = s.schema_id
LEFT JOIN sys.sql_modules m ON m.object_id = p.object_id
WHERE s.name = 'dbo' AND p.name = 'Usp_Refresh_InventoryHealth_Silver_W00';

-- Only after approval:
DROP PROCEDURE [dbo].[Usp_Refresh_InventoryHealth_Silver_W00];
```

`Usp_Refresh_InventoryHealth_Silver_W01` already refreshes `InventorySnapshotWeekly` and `AtpWeekEnding`, so dropping W00 is safe once pipeline no longer references it.

## Safety Rules

- Do not run `updateDefinition` while a pipeline job is in progress. Check `jobs/instances?jobType=Pipeline` first.
- Live mutation requires same-conversation Aric approval (per AGENTS.md §4).
- After update, run one full `pl_backup_full_refresh` and verify AuditLog for the missing W03 tables (`AFIStatusSnapshotWeekly`, `AwdHelper`, `LastInvoiceWeekly`, `Cogs52WWeekly`) shows `Process Complete` before Gold.
