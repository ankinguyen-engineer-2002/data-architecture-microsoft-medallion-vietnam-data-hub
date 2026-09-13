# UC catalog `edw_dev` — slice schemas

Mirrored to OneLake **[Verified]**. Table names below match
`Enterprise_Lakehouse.<schema>.<table>` files in `02_marts`.

| UC schema | Fabric shortcut schema | Jobs |
|---|---|---|
| `masterdata_dw` | `MasterData_DW` | `sc_master_dims` |
| `masterdata_productknowledge` | `MasterData_ProductKnowledge` | `sc_master_dims` |
| `itemmaster_afi` | `ItemMaster_AFI` | `sc_master_dims`, on-hand extras |
| `purchasing_afi` | `Purchasing_AFI` | `sc_master_dims` |
| `customerorders_afi` | `CustomerOrders_AFI` | `sc_master_dims` |
| `customers` | `Customers` | `sc_master_dims` |
| `wholesale_codis_afi` | `Wholesale_Codis_AFI` | `sc_master_dims`, `sc_codis_orders` |
| `wholesale_productsourcing_afi` | `Wholesale_ProductSourcing_AFI` | `sc_master_dims` |
| `wholesale_productsourcing` | `Wholesale_ProductSourcing` | `sc_master_dims` |
| `saleshistory_afi_enh` | `SalesHistory_AFI_Enh` | `sc_sales_invoices` |
| `supplychain_enh` | `SupplyChain_Enh` | forecast, ATP, PO, Logility, supply plan, inventory daily |
| `inventory_enh_history` | `Inventory_Enh_History` | `sc_inventory_onhand` |
| `manufacturing_inventory_afi` | `Manufacturing_Inventory_AFI` | `sc_transfers_cdc` |
| `manufacturing_productionplanning_afi` | `Manufacturing_ProductionPlanning_AFI` | `sc_supply_inbound` |

Grants: `data-sc-engineers` `USE CATALOG` + `MODIFY` on these schemas.
`data-sc-analysts` has **no** UC write; they read Fabric Gold.
