# How VN team consumes Bob's hub data via shortcuts

> Operational runbook. How `Enterprise SupplyChain-Dev` workspace reads from `EnterpriseData-Dev` (Bob's hub).

## Pattern: OneLake shortcut aggregator

Bob's enterprise hub uses the **shortcut aggregator pattern** for cross-workspace data sharing:

```
🇺🇸 EnterpriseData-Dev (hub — data lives here)
├── Wholesale_Warehouse.SalesHistory_AFI.InvoiceDetail
├── Wholesale_Warehouse.CustomerOrders_AFI.OpenOrderHeader
├── MasterData_Warehouse.MasterData_DW.DimDate
├── MasterData_Warehouse.MasterData_DW.DimItemMaster
├── Source_Data.SupplyChain_DW.* (Bronze)
└── ...

🇻🇳 Enterprise SupplyChain-Dev (VN workspace — read via shortcut)
└── Enterprise_Lakehouse (shortcut aggregator)
    ├── MasterData_DW.* ← shortcut to hub
    ├── Customers.* ← shortcut to hub
    ├── Wholesale_Codis_AFI.* ← shortcut to hub
    ├── Wholesale_ProductSourcing_AFI.* ← shortcut to hub
    └── SupplyChain_DW.* ← shortcut to hub Source_Data
```

## How shortcuts work

- Created via Fabric UI or REST API
- Read-only from VN side (data lives in hub, not duplicated)
- Updates in hub propagate immediately (no sync delay)
- Cross-WS 3-part naming works: `Enterprise_Lakehouse.MasterData_DW.DimDate`

## Reading from VN-side queries

### Inside VN's Processing Warehouse views:
```sql
-- Example: Silver view reads hub Master Data via shortcut
CREATE VIEW ReferenceMaster_Enh.v_Calendar AS
SELECT
    -- 75 columns projected
    DateKey, MapicsDate, DateID, ...
FROM Enterprise_Lakehouse.MasterData_DW.DimDate    -- ← shortcut to hub
WHERE DateKey IS NOT NULL;
```

### Cross-WH 3-part name for Bronze sources:
```sql
-- Open order Silver reads from Wholesale Codis via shortcut
CREATE VIEW Staging_Wrk.v_Codatan AS
SELECT TRIM(ORDNO) AS OrderID, ...
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan
WHERE ORDNO IS NOT NULL;
```

## What VN can read from hub today (current shortcuts)

| VN-side path | Points to (Bob hub) | VN purpose |
|--------------|---------------------|-----------|
| `Enterprise_Lakehouse.MasterData_DW.DimDate` | `MasterData_Warehouse.MasterData_DW.DimDate` | Calendar reference |
| `Enterprise_Lakehouse.MasterData_DW.DimItemMaster` | `MasterData_Warehouse.MasterData_DW.DimItemMaster` | Item master |
| `Enterprise_Lakehouse.Customers.AccountMaster` | `Wholesale_Warehouse.Customers.AccountMaster` | Customer master |
| `Enterprise_Lakehouse.Customers.ShippingLocations` | `Wholesale_Warehouse.Customers.ShippingLocations` | Shipping addresses |
| `Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan` | `Wholesale_Warehouse.CustomerOrders_AFI` (Codis tables) | Open order detail |
| `Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST` | (same) | Order master |
| `Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD` | (same) | Order extension |
| `Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT` | (same) | Order item extension |
| `Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP` | (same) | Order type lookup |
| `Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping` | `Wholesale_Warehouse.ProductSourcing_AFI` | Customer group reference |
| `Enterprise_Lakehouse.SupplyChain_DW.DimAFIWarehouses` | `Source_Data.SupplyChain_DW.DimAFIWarehouses` (Bronze) | Warehouse master |

## What VN CANNOT do today

- **Write** to any hub WH (requires Contributor permission — pending Bob Q1)
- **Cross-DB SP execute** at hub WH (requires execute permission)
- **Schedule/trigger** pipelines in hub workspace (requires Admin)
- **Add new shortcuts** (requires hub-side OneLake admin)

## Future state — bidirectional shortcuts

Once `SupplyChain_Warehouse` is created in hub (per [`../20_proposals/02_supply_chain_warehouse_proposal.md`](../20_proposals/02_supply_chain_warehouse_proposal.md)):

```
🇺🇸 EnterpriseData-Dev (hub)
├── SupplyChain_Warehouse.Forecast_Enh.* ← VN team writes here (scoped Contributor)
│
└── Centralized_Lakehouse (existing aggregator)
    └── (optional NEW shortcut: SupplyChain_Forecast.* ← shortcut to SupplyChain_Warehouse.Forecast_Enh)
        ↑ Bob's team or other value streams consume this for cross-team forecast access
```

## Operational tips

- **Shortcuts are read-only** — never write back via shortcut path
- **Schema names match exact** in hub — typos break shortcut
- **Cross-DB 3-part name works** for both Lakehouse AND Warehouse sources via shortcut
- **Latency: real-time** — no copy/sync delay, queries hit live hub data
- **Cost: storage in hub, compute in VN** — VN team's WH compute reads hub OneLake directly

## Cross-refs

- ADR-008 (VN naming alignment): [`../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md`](../../docs/decisions/ADR-008-bob-alignment-naming-and-integration.md)
- Domain team workflow: [`02_domain_team_workflow.md`](02_domain_team_workflow.md)
