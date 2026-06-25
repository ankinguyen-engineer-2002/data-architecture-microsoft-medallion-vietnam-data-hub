# V9 Forecast Detail Clone Summary

- Timestamp: `20260501_092846`
- Workspace ID: `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0`
- Warehouse: `SupplyChain_Warehouse` / `e146ffe2-d907-46a7-9b7e-3e739a31b24e`
- Scope: live SupplyChain v9 Forecast Accuracy evidence clone.
- Safety: read-only REST and read-only SQL metadata export; no business data rows exported.
- Deletion status: no delete/drop/truncate/update operation executed.

## Workspace Counts

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

## Focus Items

| Type | Display name | ID |
| --- | --- | --- |
| Report | Forecast Accuracy Gold | 23718231-b394-4b84-a215-50c302043ed0 |
| SemanticModel | SupplyChain_Gold | b4b302e7-65d7-464d-9083-aaef9d88dfc2 |
| SemanticModel | Supply Chain Control Tower | 3eecf594-a75e-46ab-9162-63c95ee68e45 |
| SemanticModel | SC_Control_Tower | a52841ee-d853-46df-b2f7-2a2cc4493d60 |
| SQLEndpoint | Enterprise_Lakehouse | 22bf1a2c-6810-4228-b69b-7a0f7853cd73 |
| Warehouse | SupplyChain_Warehouse | e146ffe2-d907-46a7-9b7e-3e739a31b24e |
| SQLEndpoint | SupplyChain_Lakehouse | cf6f1c4a-43ab-4e95-a78e-d99897be56da |
| Lakehouse | Enterprise_Lakehouse | 584e7d2c-46ca-49dc-bb6c-68df6ef4f424 |
| Lakehouse | SupplyChain_Lakehouse | 62a3081e-4093-4f46-856c-f50aa58732fa |
| DataPipeline | pl_sc_bronze | 1bdbaebb-7222-4e9c-a45d-3e632bba846d |
| DataPipeline | pl_sc_silver | 46437ae6-3a15-4697-957d-f1f44ba10633 |
| DataPipeline | pl_sc_gold | 94fc130e-f327-46a9-b7ba-cd2aa328c0da |
| DataPipeline | pl_sc_master | 319a8160-3f3a-4b87-8ad6-75ac4f3ec184 |
| DataPipeline | pl_sc_silver_wave | 57a09720-21a2-49b5-a472-1e19abd14f76 |
| DataPipeline | pl_dq_check | c32dc18d-d027-4672-9872-f73404cd7c6f |
| DataPipeline | pl_sc_mart | 9a1e7a12-30ab-465c-a45d-b051619193ac |

## V9 Registry Summary

| Layer | Schema | Project | Load type | Frequency | Active | Count |
| --- | --- | --- | --- | --- | --- | --- |
| BRZ | bronze | supplychain | overwrite | daily | 1 | 7 |
| GLD | gold | supplychain | overwrite | daily | 1 | 2 |
| REF | bronze | supplychain | overwrite | daily | 1 | 1 |
| REF | bronze | supplychain | overwrite | monthly | 1 | 10 |
| SLV | silver | supplychain | overwrite | daily | 1 | 8 |

## Object Counts

| Schema | Object type | Count |
| --- | --- | --- |
| bronze | SQL_STORED_PROCEDURE | 1 |
| bronze | USER_TABLE | 22 |
| bronze | VIEW | 18 |
| dbo | SERVICE_QUEUE | 3 |
| dbo | SQL_STORED_PROCEDURE | 9 |
| dbo | USER_TABLE | 8 |
| dbo | VIEW | 1 |
| gold | USER_TABLE | 2 |
| gold | VIEW | 2 |
| meta | SQL_SCALAR_FUNCTION | 3 |
| meta | SQL_STORED_PROCEDURE | 11 |
| meta | USER_TABLE | 11 |
| meta | VIEW | 2 |
| queryinsights | VIEW | 5 |
| SCP_Core | SQL_STORED_PROCEDURE | 4 |
| SCP_Core | USER_TABLE | 13 |
| SCP_Core_Wrk | VIEW | 12 |
| silver | USER_TABLE | 8 |
| silver | VIEW | 8 |
| test_sp | USER_TABLE | 7 |
