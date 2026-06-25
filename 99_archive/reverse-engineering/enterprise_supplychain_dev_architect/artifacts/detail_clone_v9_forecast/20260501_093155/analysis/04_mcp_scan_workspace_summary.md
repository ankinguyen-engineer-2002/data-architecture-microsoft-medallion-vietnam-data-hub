# MCP Workspace Scan Summary

This note records the MCP checks used before and alongside the REST/SQL clone.

## Fabric Dynamic MCP `scan_workspace`

Workspace: `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`

| Item type | Count |
| --- | --- |
| DataPipeline | 19 |
| Dataflow | 18 |
| Lakehouse | 3 |
| Notebook | 80 |
| Reflex | 1 |
| Report | 1 |
| SQLEndpoint | 3 |
| SemanticModel | 4 |
| Warehouse | 4 |

SupplyChain v9 focus items found:

- `pl_sc_master`
- `pl_sc_mart`
- `pl_sc_bronze`
- `pl_sc_silver`
- `pl_sc_silver_wave`
- `pl_sc_gold`
- `pl_dq_check`
- `Enterprise_Lakehouse`
- `SupplyChain_Lakehouse`
- `SupplyChain_Warehouse`
- `SupplyChain_Gold`
- `Forecast Accuracy Gold`

## Fabric Official MCP `onelake_list_table_namespaces`

Warehouse item: `SupplyChain_Warehouse` / `e146ffe2-d907-46a7-9b7e-3e739a31b24e`

Namespaces returned:

- `SCP_Core`
- `SCP_Dim`
- `bronze`
- `dbo`
- `gold`
- `meta`
- `silver`
- `test_sp`

## Fabric Dynamic MCP `query_warehouse`

Status: unavailable in this session.

The MCP returned that `query_warehouse` requires a Warehouse SQL connection via TDS/ODBC and that the `mssql` MCP server must be configured for Warehouse queries. Because of that, SQL evidence was exported through the existing Azure token + pyodbc path used by the v10 readiness script.

## Safety

No MCP action modified the workspace. MCP calls were discovery-only.
