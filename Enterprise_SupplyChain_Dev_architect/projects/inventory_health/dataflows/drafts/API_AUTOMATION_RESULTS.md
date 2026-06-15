# Dataflow API automation — results + Microsoft documentation findings

**Date:** 2026-05-12, **updated 2026-05-18** · **Status:** 7 dataflows created via REST API in workspace `Enterprise SupplyChain-Dev`

## Microsoft Learn docs research (via MCP `microsoft-docs-search` + `microsoft_docs_fetch`)

### Source: [Public APIs capabilities for Dataflow Gen2](https://learn.microsoft.com/fabric/data-factory/dataflow-gen2-public-apis)

**Known limitation (confirmed in official docs, "Current limitations" section):**

> "Run APIs can be invoked, but **the actual run never succeeds**."

→ Refresh `POST /jobs/instances?jobType=Refresh` luôn fail với error generic `"Job instance failed without detail error"`. **Đây là bug đã document của Microsoft**, không phải lỗi script.

**Confirmed by test on PoDetail_v2** (đã work qua UI Save+Refresh): API refresh vẫn fail sau khi UI đã publish thành công.

### Source: [List Connections REST API](https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections)

GET `/v1/connections` trả về 3 EDW SQL connections trong account Aric:
- `d7322e75-1e84-4aed-a08a-fc1a0862dc4a` (lowercase `ashley_edw`)
- `67192c57-5e5c-4ad4-8801-858e75656fe4` (uppercase `ASHLEY_EDW`)
- `a52e46f8-41ac-4770-a14f-af6735e3cab9` (AzureSqlMI variant)

All `ShareableCloud` + `OAuth2` → có thể reference trong queryMetadata.json của dataflow mới.

## Approach implemented

1. **Explicit connection binding** trong queryMetadata.json — dùng cluster/datasource IDs extracted from forecast `df_brz_SalesHistory` (proven working). New dataflows inherit auth, user không cần re-pick credential trong UI.

2. **`.schedules` part included** — auto-refresh daily 01:00 SE Asia Standard Time. Bypasses Microsoft's API-refresh limitation by using internal Fabric scheduler (scheduled jobs DO work, only on-demand API trigger fails).

3. **Result**: 5 dataflows created, scheduled. User just opens each once, clicks Save → auto-refresh kicks in next day at 01:00.

## Created items (workspace `c8d9fc83-...`)

| # | Dataflow | Item ID | Target Lakehouse table | Priority |
|---|----------|---------|------------------------|----------|
| 1 | `df_brz_PoDetail_v2` | `689271c0-b11d-433e-b9f0-fd767a38f08a` | `podetail_v2` | **P0** (verified working by Aric, 53 cols, 99+ rows) |
| 2 | `df_brz_PoMaster` | `585b4cbd-6e8e-4dcd-89e9-ac915984138d` | `pomaster` | **P0** |
| 3 | `df_brz_ITBEXT_Reloaded` | `f6d601e3-76bd-49d0-af95-1f90a7ac647b` | `itbext_reloaded` | **P0** |
| 4 | `df_brz_ITEMBL_PHYOH_Reloaded` | `d3d87cbe-252b-47f0-9d64-5c99be4b4192` | `itembl_phyoh_reloaded` | **P1** |
| 5 | `df_brz_Logility_ItemStatus` | `d409ee6f-4009-4a40-b9f1-6f69fc2d33d4` | `logility_itemstatus` | **P2** conditional |
| 6 | `df_brz_ItemBalance` | `7254bbc6-deb8-44e9-859d-67c11cfeec75` | `itembalance` | **P1** (added 2026-05-18) |
| 7 | `df_brz_PurchaseOrderSnapshot` | `35814293-0b87-4e21-a4ec-1a681c8032a0` | `purchaseordersnapshot` | **P2** (added 2026-05-18, Phase 2 PO-as-of feature) |

## Action required from Aric (per dataflow)

For each của 4 dataflow mới (#2-5):

1. Mở Fabric UI → workspace `Enterprise SupplyChain-Dev` → click dataflow
2. **Nếu credential pre-bound** (vì đã include connectionId in metadata): chỉ cần click **Save**
3. **Nếu prompt credential**: pick existing connection `ashley-edw.database.windows.net;ASHLEY_EDW2 NAric` (id `67192c57-...`) → Save
4. (Optional) Click **Refresh** ngay để test, hoặc đợi schedule chạy 01:00 mai

ETA: ~30s per dataflow = ~2 phút total cho 4 dataflows.

## Bug fix iteration (2026-05-12, after Aric's first test)

Aric tested 4 dataflows → 3 lỗi `Invalid object name`:
- `ItemMaster_AFI.ITBEXT` → not found on ASHLEY_EDW
- `ItemMaster_AFI.ITEMBL` → not found on ASHLEY_EDW
- `DemandFulfilmentCommonContain_Logility.ItemStatus` → not found

**Root cause discovered**: BRD spreadsheet's `ItemMaster_AFI.*` paths refer to **Lakehouse mirror schema**, not raw EDW SQL Server schemas. ASHLEY_EDW has different actual schema names (raw EDW). The Lakehouse layer (mirrored via Databricks UC sync per memory) presents the cleaner `ItemMaster_AFI.*` namespace.

**Fix applied** (via REST API `updateDefinition`):

| Dataflow | Old source | New source | Status |
|----------|-----------|-----------|--------|
| `df_brz_ITBEXT_Reloaded` | `ashley-edw / ASHLEY_EDW.ItemMaster_AFI.ITBEXT` | `Lakehouse SQL endpoint / Enterprise_Lakehouse.ItemMaster_AFI.ITBEXT` | ✅ Updated · Aric Save+Refresh |
| `df_brz_ITEMBL_PHYOH_Reloaded` | `ashley-edw / ASHLEY_EDW.ItemMaster_AFI.ITEMBL` | `Lakehouse SQL endpoint / Enterprise_Lakehouse.ItemMaster_AFI.ITEMBL` | ✅ Updated · Aric Save+Refresh |
| `df_brz_Logility_ItemStatus` | `ashley-edw / Logility.ItemStatus` | ⚠️ Not on Lakehouse (P2 conditional, chờ Robert) | Keep as placeholder |

**Important consequence**: ITBEXT + ITEMBL bây giờ kéo từ Lakehouse mirror (live data từ EDW via Databricks sync). Nếu Lakehouse cũng có 0 ở cột PHYOH/CRHLD/DLHLD/TOHLD/ATPQT thì workaround đã document (MOHTQ, ATPSUM, ExtendedOrder, Item_ENV) vẫn cần dùng — dataflow chỉ là confirm/reload chứ không fix dead columns.

**Utility cleanup**: `df_explore_edw_schemas` (discovery dataflow tạo để find correct schemas) — deleted sau khi xác nhận.

## Bug fix iteration #2 (2026-05-12 — Aric SSMS query on EDW)

Aric ran direct SSMS query on EDW to discover ACTUAL schema names. Findings:

| BRD path (Lakehouse mirror) | EDW raw path (REAL) |
|---------------------------|--------------------|
| `ItemMaster_AFI.ITBEXT` | **`MasterData_ItemMaster_AFI.ITBEXT`** (also has `_WVF`, `_MIL`, `_Wrk`, `PowerBI_Distribution` variants) |
| `ItemMaster_AFI.ITEMBL` | **`MasterData_ItemMaster_AFI.ITEMBL`** (canonical) + many `ITEMBL_YYYY_MM_DD_*` snapshots |
| `DemandFulfilmentCommonContain_Logility.ItemStatus` | **`SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility`** (spelling: 2× `l` trong Fulfill**ll**ment; **Container** not Contain — BRD typo) |

**Architecture insight**: EDW raw có `MasterData_*` prefix pattern. Lakehouse mirror simplifies to bare `ItemMaster_AFI.*`. The Databricks UC sync layer does namespace flattening.

**Fix iteration #2 applied** (REST API updateDefinition, all HTTP 200 sync):

| Dataflow | Final SQL |
|----------|----------|
| `df_brz_ITBEXT_Reloaded` | `SELECT * FROM MasterData_ItemMaster_AFI.ITBEXT` (EDW raw) |
| `df_brz_ITEMBL_PHYOH_Reloaded` | `SELECT * FROM MasterData_ItemMaster_AFI.ITEMBL` (EDW raw) |
| `df_brz_Logility_ItemStatus` | `SELECT * FROM SupplyChain_Enh.DemandFulfillmentCommonContainer_Logility` (EDW raw) |

**Hypothesis to verify on first refresh**: EDW raw có data thật trong các cột Lakehouse mirror = 0 (PHYOH, CRHLD/DLHLD/TOHLD, ATPQT). Lakehouse mirror dead có thể do UC sync filter dropped them. EDW raw should preserve original values.

**Validation queries** (run on `SupplyChain_Lakehouse` SQL endpoint after refresh):

```sql
-- ITEMBL PHYOH: hope > 0 non-zero (vs Lakehouse 0 toàn bộ)
SELECT COUNT(*) AS total,
       SUM(CASE WHEN PHYOH<>0 THEN 1 ELSE 0 END) AS phyoh_nonzero,
       MAX(PHYOH) AS phyoh_max
FROM SupplyChain_Lakehouse.dbo.itembl_phyoh_reloaded;

-- ITBEXT hold flags + ATPQT: hope > 0 non-zero
SELECT COUNT(*) AS total,
       SUM(CASE WHEN CRHLD<>0 THEN 1 ELSE 0 END) AS crhld_nz,
       SUM(CASE WHEN DLHLD<>0 THEN 1 ELSE 0 END) AS dlhld_nz,
       SUM(CASE WHEN TOHLD<>0 THEN 1 ELSE 0 END) AS tohld_nz,
       SUM(CASE WHEN ATPQT<>0 THEN 1 ELSE 0 END) AS atpqt_nz
FROM SupplyChain_Lakehouse.dbo.itbext_reloaded;
```

- If **non-zero counts > 0** → EDW raw có data → fix dead column ✓
- If **non-zero counts = 0** → EDW cũng dead → legacy columns, dùng workaround MOHTQ/ATPSUM/ExtendedOrder forever

## Why API refresh không work (Microsoft limitation)

Workaround paths trong tương lai (theo Microsoft docs):
- **Scheduled refresh** (đã implement qua `.schedules` part) — auto-runs daily
- **Pipeline activity wrapper** — Dataflow activity inside Fabric Data Pipeline → pipeline API trigger DOES work (proven: `pl_sc_master` run 42m08s success via API)
- **Manual UI refresh** — always works

## 2026-05-18 — Iteration #3: Add 2 dataflows for Phase 1B/2 sources

Added `df_brz_ItemBalance` + `df_brz_PurchaseOrderSnapshot` via inline `curl + python3` REST API calls (no Python script file). Same connection IDs reused from `df_brz_PoDetail_v2`:
- Lakehouse: `ClusterId=e6436dba-643f-44c3-ad6f-51a8cbc45b81, DatasourceId=b4311980-3d3b-49be-bd11-7e2f8e424e19`
- SQL EDW: `ClusterId=e6436dba-..., DatasourceId=67192c57-5e5c-4ad4-8801-858e75656fe4`

Both dataflows:
1. Created via `POST /workspaces/{ws}/dataflows` (returns dataflowId) — HTTP 201
2. updateDefinition via `POST /workspaces/{ws}/dataflows/{id}/updateDefinition` with 3 parts (queryMetadata.json + mashup.pq + .platform) — HTTP 200

**Source paths** (verify on first refresh — if "Invalid object name" → query EDW SSMS for actual schema):
- `df_brz_ItemBalance`: `Inventory_Enh_History.ItemBalance` (BRD path; may need MasterData_* prefix per iteration #2 pattern)
- `df_brz_PurchaseOrderSnapshot`: `SupplyChain_Enh.PurchaseOrderSnapshot` (per Track A doc "anh sếp dùng cho PO-as-of query")

**Action required from Aric**:
- Mở Fabric portal → mỗi dataflow → click Save (if prompt for credential, pick `ashley-edw.database.windows.net;ASHLEY_EDW` connection id `67192c57-...`)
- Optional manual Refresh để verify EDW schema; nếu fail → adjust SQL in `add_or_update_query_in_dataflow` after Claude restart loads DataFactory.MCP

## DataFactory.MCP setup (added 2026-05-18)

Microsoft official MCP server đã configured: `~/.claude.json` → `mcpServers.datafactory`. Will load on next Claude Code session. Provides:
- `create_dataflow` + `save_dataflow_definition` (full automation, no UI Save)
- `refresh_dataflow_background` (working refresh API — alternative to scheduled-only workaround)
- `create_connection` (with inline credentials)

Setup command was: `claude mcp add datafactory -s user -- /opt/homebrew/Cellar/dotnet/10.0.102/libexec/dnx Microsoft.DataFactory.MCP --yes`

Future dataflow operations should prefer DataFactory.MCP tools over raw REST (cleaner, refresh works).

## Reference

- Source artifact: [`../../artifacts/source_inputs/inventory_health_source_kpi_mapping_2026-05-12.xlsx`](../../artifacts/source_inputs/inventory_health_source_kpi_mapping_2026-05-12.xlsx)
- Setup guide: [`../setup.md`](../setup.md)
- Forecast template: [`../templates/mashup.pq`](../templates/mashup.pq)
- Microsoft docs:
  - https://learn.microsoft.com/fabric/data-factory/dataflow-gen2-public-apis
  - https://learn.microsoft.com/en-us/rest/api/fabric/core/connections/list-connections
  - https://learn.microsoft.com/fabric/data-factory/dataflow-gen2-cicd-and-git-integration
