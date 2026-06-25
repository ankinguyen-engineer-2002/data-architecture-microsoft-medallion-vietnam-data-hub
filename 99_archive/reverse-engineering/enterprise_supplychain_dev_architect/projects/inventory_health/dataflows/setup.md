# Dataflow Gen2 setup — pull EDW sources → `SupplyChain_Lakehouse.dbo.*`

> **Status:** Build-ready setup guide · **Created:** 2026-05-12 · **Source artifact:** [`inventory_health_source_kpi_mapping_2026-05-12.xlsx`](../artifacts/source_inputs/inventory_health_source_kpi_mapping_2026-05-12.xlsx) sheet `EDW_vs_Lakehouse`

## Overview

Của 31 EDW sources cần cho 30 KPIs inventory_health, **24 đã có trên Enterprise_Lakehouse** (13 Mapped + 11 Renamed) → dùng shortcut trực tiếp.

**6 bảng/cột cần Dataflow Gen2** kéo từ EDW lên `SupplyChain_Lakehouse.dbo.*`:

| # | Source EDW | Lý do cần kéo | Priority | KPIs ảnh hưởng |
|---|-----------|--------------|----------|----------------|
| 1 | `Wholesale_ProductSourcing_AFI.PoDetail` | Schema có trên Enterprise_Lakehouse nhưng **0 rows** trong dev — cần kéo full data | **P0** | #2, #3, #4, #15, #17 |
| 2 | `Wholesale_ProductSourcing_AFI.PoMaster` | **Không có trên lake** — cần kéo mới (confirm tên upstream: POMAST / PoHeader / PurchaseOrderMaster) | **P0** | #2, #3, #17 |
| 3 | `ItemMaster_AFI.ITBEXT` (cột CRHLD, DLHLD, TOHLD) | 3 cột hold = 0 toàn 3.39M rows — kéo lại với mapping cột đầy đủ nếu EDW có data thật | **P0** | #20e, #27 |
| 4 | `ItemMaster_AFI.ITEMBL` (cột PHYOH) | Cột = 0 toàn 3.40M rows — kéo lại nếu EDW có data (workaround MOHTQ đã có) | **P1** | #1 fallback |
| 5 | `ItemMaster_AFI.ITBEXT` (cột ATPQT) | Cột = 0 toàn 3.39M rows — kéo lại nếu EDW có data (workaround ATPSUM.APAT01 đã có) | **P1** | #23b fallback |
| 6 | `DemandFulfilmentCommonContain_Logility.ItemStatus` | Logility raw chưa load — kéo nếu Robert chốt cần past tracking cho Inactive/SLOB/Lifecycle | **P2 conditional** | #17, #18, #20a past |

**Tổng: 3 P0 (cấp bách) + 2 P1 (có workaround) + 1 P2 (conditional)** = **6 logical entries · 5 physical dataflows** (ITBEXT entries #3 + #5 gộp vào 1 dataflow vì cùng table)

**Trong đó**:
- **2 bảng load full mới hoặc reload toàn bảng**: PoDetail, PoMaster (+ Logility.ItemStatus nếu cần)
- **3 cột chết** trong 2 bảng đã có (ITEMBL, ITBEXT): cần xác nhận với DE US — nếu EDW có data thật thì kéo lại, nếu EDW cũng = 0 thì là cột deprecate, không cần kéo

**Out of scope** (không thuộc dataflow này): file Excel `SS vs Capacity Projections.xlsx` của WH team — phase 2 mới xử lý.

---

## Prereq — EDW + Lakehouse endpoints (CONFIRMED via existing forecast dataflows)

Verified 2026-05-12 by inspecting `df_brz_SalesHistory_AFI_InvoiceDetail` definition (commit `f2b8248f` artifacts in `templates/`):

| Endpoint | Value |
|----------|-------|
| **EDW Server** | `ashley-edw.database.windows.net` |
| **EDW Database** | `ASHLEY_EDW` |
| **EDW Connection ID** | `{"ClusterId":"e6436dba-643f-44c3-ad6f-51a8cbc45b81","DatasourceId":"179c470b-1f8c-4a73-82b6-5206a4a5a5cc"}` (reuse) |
| **Lakehouse target** | `SupplyChain_Lakehouse` (ID `62a3081e-4093-4f46-856c-f50aa58732fa`) |
| **Lakehouse Connection ID** | `{"ClusterId":"e6436dba-643f-44c3-ad6f-51a8cbc45b81","DatasourceId":"1a64c7b8-2c7a-445a-bd7f-ca0fc0b98e9b"}` (reuse) |
| **Workspace ID** | `c8d9fc83-18b6-4e1d-8264-0b49eed36fe0` |
| **Query pattern** | `Sql.Database(...) + Value.NativeQuery(...)` SQL passthrough |
| **Destination pattern** | `Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null])` |
| **Staging** | `[Kind = "FastCopy"]` |
| **Schedule pattern** | Daily 05:00 SE Asia Standard Time (existing forecast dataflows) |
| **Table naming convention** | Snake_case + prefix `brz_` (vd `brz_saleshistory_afi__invoicedetail_ver2`) — but `inventory_health` will use PascalCase `dbo.<TableName>` per Aric design |

**Auth reuse**: connectionId của forecast dataflows đã work, không cần setup mới. Khi tạo dataflow inventory_health, chọn "Existing connection" → pick `ashley-edw.database.windows.net;ASHLEY_EDW`.

**Reference templates**: full M code + metadata cua `df_brz_SalesHistory_AFI_InvoiceDetail` saved tai `templates/` (mashup.pq, queryMetadata.json, .schedules, .platform). Copy and adapt cho 5 dataflows inventory_health.

---

## Query templates

### P0-1 · `dbo.PoDetail` (Wholesale PO line detail)

**Power Query M** (paste vào Dataflow Gen2 Advanced Editor):

```m
let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW",
        [Query="
            SELECT *
            FROM Wholesale_ProductSourcing_AFI.PoDetail
            -- Filter to last 3 years if too large (PO_CreatedDate column TBD)
            -- WHERE PO_CreatedDate >= DATEADD(YEAR, -3, GETDATE())
        ", CreateNavigationProperties=false])
in
    Source
```

**Native SQL** (nếu prefer SQL passthrough):
```sql
SELECT *
FROM Wholesale_ProductSourcing_AFI.PoDetail
-- Optional date filter for incremental:
-- WHERE LastModifiedTS >= ?
```

**Destination**: Lakehouse `SupplyChain_Lakehouse` → Table `PoDetail` (schema = `dbo`, default)  
**Refresh**: Full load lần đầu · Incremental sau (watermark column = `LastModifiedTS` nếu có, hoặc `PO_CreatedDate`)  
**Verify**: `SELECT COUNT(*) FROM SupplyChain_Lakehouse.dbo.PoDetail` — kỳ vọng vài trăm K rows (so với 0 rows hiện tại trên Enterprise_Lakehouse)

---

### P0-2 · `dbo.PoMaster` (Wholesale PO header)

```m
let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW",
        [Query="
            SELECT *
            FROM Wholesale_ProductSourcing_AFI.PoMaster
            -- Tên upstream cần confirm — có thể là PoHeader hoặc PurchaseOrderMaster
        ", CreateNavigationProperties=false])
in
    Source
```

**Destination**: `SupplyChain_Lakehouse.dbo.PoMaster`  
**Refresh**: Full load — table này không có trên lake, lần đầu kéo full  
**Action trước khi chạy**: confirm tên thực tế bên EDW (`PoMaster` vs `PoHeader`). Thường có Status column quan trọng:
- `Firm Status` (cho KPI #4 PO On Order)
- `Document Date`

**Verify**: row count + có column `Status`/`OrderStatus` không (cần cho join với PoDetail)

---

### P0-3 + P1-5 · `dbo.ITBEXT_Reloaded` (Hold flags P0 + ATPQT P1 — gộp 1 dataflow)

Phương án: reload toàn bảng ITBEXT với mapping đầy đủ. **1 dataflow physical** phục vụ 2 logical entries (#3 P0 cho hold cols, #5 P1 cho ATPQT) vì cùng table.

Priority dataflow = **P0** (lấy ưu tiên cao nhất giữa 2 entries) — hold cols không có workaround thay thế phù hợp.

```m
let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW",
        [Query="
            SELECT
                ITNBR,        -- Item number (PK)
                CRHLD,        -- Credit hold flag
                DLHLD,        -- Delivery hold flag
                TOHLD,        -- Total/Type-on hold flag
                ATPQT,        -- Available-to-promise quantity
                -- Add other columns from ITBEXT that hiện ENH side mất data
                *             -- Lấy all để diff với existing
            FROM ItemMaster_AFI.ITBEXT
        ", CreateNavigationProperties=false])
in
    Source
```

**Destination**: `SupplyChain_Lakehouse.dbo.ITBEXT_Reloaded` (suffix `_Reloaded` để không clash với existing shortcut)  
**Refresh**: Full daily (3.39M rows — manageable)  
**Verify trước khi consume**: `SELECT TOP 100 ITNBR, CRHLD, DLHLD, TOHLD, ATPQT FROM dbo.ITBEXT_Reloaded WHERE CRHLD<>0 OR DLHLD<>0 OR TOHLD<>0` — kỳ vọng > 0 rows (chứng tỏ EDW có data, không phải dead trên upstream)

**Fallback nếu EDW cũng dead**: dùng workaround đã document — `ExtendedOrder` + `Item_ENV` cho hold KPI #20e (KPI mapping sheet `Source_to_KPI`).

---

### P1-4 · `dbo.ITEMBL_PHYOH_Reloaded` (Physical on-hand quantity — workaround MOHTQ đã có)

```m
let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW",
        [Query="
            SELECT
                ITNBR, BLDIV, WHSEC,  -- Composite key (Item × Division × Warehouse)
                PHYOH,                 -- Physical on-hand (currently 0 in lake)
                MOHTQ,                 -- Move-on hand total quantity (verified non-zero)
                ITCLS,
                *
            FROM ItemMaster_AFI.ITEMBL
        ", CreateNavigationProperties=false])
in
    Source
```

**Destination**: `SupplyChain_Lakehouse.dbo.ITEMBL_PHYOH_Reloaded`  
**Refresh**: Full daily (3.40M rows)  
**Critical verify**: `SELECT SUM(PHYOH) FROM dbo.ITEMBL_PHYOH_Reloaded` — phải > 0 (hiện trên lake = 0 toàn bộ)

**Fallback**: nếu EDW PHYOH cũng = 0, dùng MOHTQ (đã work) — không cần dataflow này.

---

### P2-6 · `dbo.Logility_ItemStatus` (past lifecycle tracking — conditional)

⚠️ **Conditional** — chỉ load nếu Robert (Demand Planning lead) confirm cần past tracking. Hiện tại workaround dùng `DimItemMaster.AFIItemStatus` (current state only).

```m
let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW",
        [Query="
            SELECT *
            FROM DemandFulfilmentCommonContain_Logility.ItemStatus
            -- Confirm Logility schema exists in EDW
            -- Có thể tên khác — e.g., Logility_Stage.ItemStatus
            WHERE 1=1
            -- AND ChangeDate >= DATEADD(YEAR, -2, GETDATE())  -- Limit history if huge
        ", CreateNavigationProperties=false])
in
    Source
```

**Destination**: `SupplyChain_Lakehouse.dbo.Logility_ItemStatus`  
**Refresh**: Incremental (watermark = `ChangeDate` hoặc `EffectiveStartDate`)  
**Action**: confirm với Robert trước khi build; confirm tên schema thực tế trên EDW.

---

## Dataflow Gen2 — setup steps

Per source:

1. **Open** Fabric workspace `Enterprise SupplyChain-Dev` → `+ New item` → `Dataflow Gen2`
2. **Name** dataflow theo convention: `df_brz_<schema>__<table>` (vd `df_brz_Wholesale_ProductSourcing_AFI__PoDetail`) — đồng bộ với existing pattern
3. **Get data** → SQL Server → paste connection từ existing dataflow (re-use auth)
4. **Advanced editor** → paste M query template ở trên
5. **Configure data destination**:
   - Type: Lakehouse
   - Workspace: `Enterprise SupplyChain-Dev`
   - Lakehouse: `SupplyChain_Lakehouse`
   - Table name: `<target_table>` (default schema = `dbo`)
   - Update method: **Replace** (full refresh) lần đầu · sau đổi sang **Append** + watermark nếu incremental
6. **Schedule**: daily 1:00 AM UTC (chạy trước `pl_sc_master` 2:00 AM để đảm bảo data ready)
7. **Validate**: chạy thử lần đầu → check row count target Lakehouse table

---

## Sau khi Dataflow chạy thành công

1. **Verify counts trên Lakehouse**:
   ```sql
   SELECT 'PoDetail' AS tbl, COUNT(*) AS n FROM SupplyChain_Lakehouse.dbo.PoDetail
   UNION ALL SELECT 'PoMaster', COUNT(*) FROM SupplyChain_Lakehouse.dbo.PoMaster
   UNION ALL SELECT 'ITBEXT_Reloaded', COUNT(*) FROM SupplyChain_Lakehouse.dbo.ITBEXT_Reloaded
   UNION ALL SELECT 'ITEMBL_PHYOH_Reloaded', COUNT(*) FROM SupplyChain_Lakehouse.dbo.ITEMBL_PHYOH_Reloaded;
   ```

2. **Quality check** — đảm bảo các cột "dead" giờ có data:
   ```sql
   SELECT COUNT(*) AS rows_with_hold
   FROM SupplyChain_Lakehouse.dbo.ITBEXT_Reloaded
   WHERE CRHLD <> 0 OR DLHLD <> 0 OR TOHLD <> 0;
   -- Expect > 0
   ```

3. **Update [10_bronze.md](10_bronze.md)** với:
   - Bảng cập nhật status cho 7 sources từ "Cần Dataflow" → "Loaded via df_brz_*"
   - Row count baseline mỗi table

4. **Cross-reference vào `Meta.AssetRegistry`** (khi build Silver):
   ```sql
   -- Example: PoDetail source registration
   INSERT INTO Meta.SourceFeed (...) VALUES (
     'SupplyChain_Lakehouse.dbo.PoDetail',
     '<asset_id_consumer>',  -- e.g., InventoryHistory_Enh.SomeSilverTable
     ...
   );
   ```

---

## Open items trước khi chạy

| # | Item | Owner | Status |
|---|------|-------|--------|
| 1 | ~~Confirm EDW server + database name~~ | — | ✅ Resolved 2026-05-12: `ashley-edw.database.windows.net` / `ASHLEY_EDW` (extracted from `df_brz_*` definitions) |
| 2 | Confirm `PoMaster` upstream tên thực tế (POMAST / PoHeader / PurchaseOrderMaster) | Cherry | Pending |
| 3 | Confirm Logility schema exists + tên (`DemandFulfilmentCommonContain_Logility` vs `Logility_Stage`) | Robert | Pending P2 |
| 4 | Verify ITBEXT (CRHLD/DLHLD/TOHLD/ATPQT) + ITEMBL.PHYOH có data trên EDW (không dead toàn upstream) | Aric (test query) | Pending — first dataflow run sẽ confirm |
| 5 | ~~Setup auth — reuse SPN từ existing dataflow~~ | — | ✅ Resolved 2026-05-12: reuse `ashley-edw.database.windows.net;ASHLEY_EDW` connectionId từ existing dataflows |

---

## References

- Source artifact: [`inventory_health_source_kpi_mapping_2026-05-12.xlsx`](../artifacts/source_inputs/inventory_health_source_kpi_mapping_2026-05-12.xlsx)
- Bronze design: [10_bronze.md](10_bronze.md)
- Open questions: [../docs/open_questions_for_enterprise_etl.md](../docs/open_questions_for_enterprise_etl.md)
- Existing dataflow patterns (workspace scan): 18 dataflows incl. `df_brz_SalesHistory_AFI_InvoiceDetail`, `df_brz_SupplyChain_Enh_1_DemandForecastSnapshotDaily_copy1` (per memory `project_workspace_topology.md`)
