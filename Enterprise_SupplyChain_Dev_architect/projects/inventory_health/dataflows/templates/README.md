# Dataflow templates — reference from `forecast/` project

Full part-by-part definition of `df_brz_SalesHistory_AFI_InvoiceDetail` (workspace `Enterprise SupplyChain-Dev`, item ID `7b906c80-6984-4c29-90f1-f3660368f21d`) extracted 2026-05-12 via Fabric REST API `getDefinition`.

## Files

| File | Purpose |
|------|---------|
| `queryMetadata.json` | Dataflow metadata: connections, query groups, destination references |
| `mashup.pq` | Full Power Query M code: source query + destination block + StagingDefinition + DataDestinations |
| `.schedules` | Daily 05:00 SE Asia Standard Time refresh schedule |
| `.platform` | Fabric item platform metadata |

## Key extracts (verified 2026-05-12)

**EDW connection** (reuse for all inventory_health dataflows):
```m
Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW")
```

ConnectionId from `queryMetadata.json`:
```json
"connections": [
  {
    "path": "ashley-edw.database.windows.net;ASHLEY_EDW",
    "kind": "SQL",
    "connectionId": "{\"ClusterId\":\"e6436dba-643f-44c3-ad6f-51a8cbc45b81\",\"DatasourceId\":\"179c470b-1f8c-4a73-82b6-5206a4a5a5cc\"}"
  }
]
```

**Lakehouse destination** (target `SupplyChain_Lakehouse`):
```m
let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null]),
  Navigation_1 = Pattern{[workspaceId = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "62a3081e-4093-4f46-856c-f50aa58732fa"]}[Data],
  TableNavigation = Navigation_2{[Id = "<target_table_name_lowercase>", ItemKind = "Table"]}?[Data]?
in
  TableNavigation
```

**StagingDefinition** (use FastCopy for large tables):
```m
[StagingDefinition = [Kind = "FastCopy"]]
```

**DataDestinations** (paired with `_DataDestination` query):
```m
[DataDestinations = {
  [Definition = [Kind = "Reference", QueryName = "<MainQueryName>_DataDestination", IsNewTarget = true],
   Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]
}]
```

## How to adapt for inventory_health

1. **Copy** the `df_brz_SalesHistory_AFI_InvoiceDetail` dataflow in Fabric UI (Save As)
2. **Rename** to `df_brz_<Schema>__<Table>` matching new pattern
3. **Replace** the SELECT body in `mashup.pq` with the inventory_health query (see [../setup.md](../setup.md))
4. **Re-point destination** TableNavigation `Id = "<target>"` to target Lakehouse table name (lowercase, e.g. `podetail`, `pomaster`, `itbext_reloaded`)
5. **Adjust schedule** if needed (forecast uses 05:00; inventory_health may use 01:00 to finish before `pl_sc_master` at 02:00)

## Why keep these templates in repo

- Forecast dataflows are LIVE production — these templates are the "verified working" pattern
- Future marts (inventory_health, sales_health, etc.) can clone from these
- Connection IDs + Lakehouse pattern are concrete (no guessing during build)
- If dataflow Gen2 patterns change in Fabric over time, these templates document the v10 baseline
