# Open Questions for Bob — pending reply

Date opened: 2026-05-10
Status: Awaiting Bob's response (email not yet sent — draft pending)

These are the only items VN team **cannot** resolve unilaterally. Everything else (naming alignment, view prefix, local AuditLog, extended TableDictionary view) is being executed in parallel without waiting.

---

## Q1 — ETL_Framework write permission + AuditTable DDL

**Need:** Cross-DB write from `Enterprise_SupplyChain Dev.SupplyChain_Processing_Warehouse.Meta.usp_LogRun` to:
- `EnterpriseData-Dev.ETL_Framework.DW_Developer.TableDictionary` → UPDATE `Modified`, `RowCount`, `LastAudit` after each load
- `EnterpriseData-Dev.ETL_Framework.DW_Developer.AuditLog` → INSERT row on error

**Asks Bob:**
1. Grant our service principal / Aric's identity write permission on `ETL_Framework.DW_Developer.TableDictionary` and `AuditLog`?
2. Provide canonical DDL of `AuditLog` table (cols: Description, DateTime, User, Command observed — confirm types/sizes)?
3. Should we register VN's tables (Processing WH + Gold WH) as rows in `TableDictionary` itself, or just write to `Modified`/`RowCount` for already-registered rows?

**Blocks:** P1 task — extend `usp_LogRun` cross-DB write (~2 days work after permission granted).

---

## Q2 — Promote target ownership + dependents

**Need:** When promoting `DimCalendar` / `DimItemMaster` / `DimWarehouse` from VN's Gold WH into `EnterpriseData-Dev.MasterData_Warehouse`.

**Observed:** `MasterData_Warehouse.MasterData_DW.DimDate`, `DimItemMaster`, `DimRetailLocations`, `DimTime` already exist. Schema row counts = 0 in scan, but Modified dates show recent activity (2025-09→2026-01).

**Asks Bob:**
1. Owner of schema `MasterData_DW` in `MasterData_Warehouse` — is it Bob's team, or owned by Retail/Wholesale data products?
2. What are the existing producers/consumers of `DimDate`, `DimItemMaster`? (To assess dependency impact of MERGE)
3. Should we (a) MERGE/extend existing tables, or (b) create a SC-specific schema (e.g., `MasterData_DW_SC`) for our promoted dims?
4. `DimRetailLocations` — does it cover wholesale warehouses (Codis/AFI), or is it retail-stores-only? (Determines if our `DimWarehouse` overlaps)

**Blocks:** P2 phase — Calendar/ItemMaster/Warehouse promote design.

---

## Q3 — `SupplyChain_Warehouse` in EnterpriseData hub

**Email quote:** "I would expect to see some forecast data in a clean state within the **SupplyChain_Warehouse in EnterpriseData** (silver layer)"

**Observed:** `EnterpriseData-Dev` (Bob's hub `5360a935-…`) does NOT contain a `SupplyChain_Warehouse`. Existing siblings: `Retail_Warehouse`, `Wholesale_Warehouse`, `MasterData_Warehouse`, `Distribution_Warehouse`, `Quality_Warehouse`, `Centralized_Warehouse`.

**Asks Bob:**
1. Plan: (a) create fresh `SupplyChain_Warehouse` in `EnterpriseData-Dev` as a sibling, (b) bob's team creates and grants VN team contributor rights, (c) some other plan?
2. Does the existing v8 `Enterprise_SupplyChain Dev.SupplyChain_Warehouse` (id `e146ffe2-…`, Cherry's domain, hosts Control Tower upstream) factor into this?
3. Schema target inside the new WH — `SupplyChain_DW` (matching `Source_Data.SupplyChain_DW` and `MasterData_DW` precedent), `Forecast_AFI`, or different?

**Blocks:** P2 phase — Forecast Silver promote design + Rakesh sign-off.

---

## Q4 — IT unblocks (Mail.Send + Azure DevOps)

**Need (already raised in prior email — pending):**
1. Microsoft Graph **Mail.Send admin consent** for app registration `616bb922-8969-4ff8-8dcf-3667c0ae8e19` — needed for pipeline alerting via Office365 connector
2. **Azure DevOps `Enterprise Data Services` project access** for VN team — required to align with Bob's Git source-of-truth model (workspace `EnterpriseData-Dev` is `ConnectedAndInitialized` to `ashleyfurniture/Enterprise Data Services/Fabric-EnterpriseData`)
3. **Read access** on `EnterpriseData-Dev` workspace for VN team — to audit MasterData_DW columns + Wholesale.SalesHistory_AFI structure before promote

**Asks Bob/Rakesh:**
1. Can you or Rakesh nudge IT on Mail.Send consent + ADO access?
2. For workspace read access, is it OK for VN team (Aric + Cherry + 1-2 others) to be added as Viewer on `EnterpriseData-Dev`?

**Blocks:** Schedule trigger automation, CI/CD pipeline sync, cross-WH audits.

---

## What's NOT being asked (handling unilaterally per Aric DE-lead authority)

These are technical naming/style choices VN team owns:

| Item | Decision | Rationale |
|------|----------|-----------|
| Casing `_ENH` → `_Enh` | Adopt | Evidence: 7+ schemas in Bob's WS use `_Enh` (e.g., `Source_Data.SupplyChain_Enh`, `Retail_Warehouse.MasterData_HR_UKG_Enh`) |
| Casing `_WRK` → `_Wrk` | Adopt | Same — `SalesHistory_AFI_Wrk`, `Retail_Sales_Wrk` |
| `_DW` suffix | Keep ALL CAPS | Bob's `MasterData_DW`, `Source_Data.SupplyChain_DW` use ALL CAPS |
| View prefix `vw_` → `v_` | Adopt | All Bob's views use `v_*` (e.g., `v_InvoiceDetail`) |
| Local `Meta.AuditLog` clone | Build local | Mirror Bob's `ETL_Framework.DW_Developer.AuditLog` schema; sync to Bob's via `usp_LogRun` once Q1 unblocks |
| Extended `Meta.vw_TableDictionary` | Add cols | Match Bob's 65-col schema (ServerName, DatabaseName, ETLTool, RefreshRate, UpdateMethod, UpdateQuery, etc.) |
| Drop AI feature-store proposal | Drop | Bob confirmed AI consumes Semantic Model (per Rich/Louise) |
| Schema name format inside VN WS | Keep current | `SalesHistory_Enh`, `ForecastHistory_Enh`, `OpenOrderHistory_Enh`, `ReferenceMaster_Enh`, `Staging_Wrk` — match Bob's domain-pattern style |

→ All above are being executed via `Enterprise_SupplyChain_Dev_architect/artifacts/bob_alignment_2026-05-10/` scripts.
