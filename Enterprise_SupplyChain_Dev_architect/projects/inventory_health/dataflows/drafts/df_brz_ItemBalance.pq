// ============================================================================
// Dataflow Gen2 — df_brz_ItemBalance
// ============================================================================
// Project:     inventory_health (Phase 1B, P1)
// Source:      ashley-edw.database.windows.net / ASHLEY_EDW
//              Inventory_Enh_History.ItemBalance  (verify schema after first refresh)
// Destination: SupplyChain_Lakehouse (62a3081e-...) / Table itembalance
// Reason:      Historical inventory primary source per BRD. Schema MIA on
//              Lakehouse mirror (Inventory_Enh_History not exposed) — need to
//              workaround via EDW raw pull until DE US loads the schema.
// KPIs:        Historical OnHand for week-over-week comparison, primary backup
//              source cho InventorySnapshotWeekly (currently uses
//              DemandInventorySnapshotWeekly fallback).
// ============================================================================
// Reuses same connection IDs as df_brz_PoDetail_v2:
//   - SQL EDW: ClusterId=e6436dba-643f-44c3-ad6f-51a8cbc45b81,
//              DatasourceId=67192c57-5e5c-4ad4-8801-858e75656fe4
//   - Lakehouse: ClusterId=e6436dba-..., DatasourceId=b4311980-...
// ============================================================================
// IMPORTANT — verify on first refresh:
//   1. Confirm EDW có schema 'Inventory_Enh_History' và table 'ItemBalance'
//   2. Nếu fail "Invalid object name" → query SSMS direct on EDW:
//      SELECT TOP 1 * FROM INFORMATION_SCHEMA.TABLES
//      WHERE TABLE_NAME='ItemBalance'
//      → use actual schema name (likely MasterData_ItemMaster_AFI or Inventory_*)
// ============================================================================

[StagingDefinition = [Kind = "FastCopy"]]
section Section1;

[DataDestinations = {
  [Definition = [Kind = "Reference", QueryName = "Inventory_Enh_History ItemBalance_DataDestination", IsNewTarget = true],
   Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]
}]
shared #"Inventory_Enh_History ItemBalance" = let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW"),
    RawQuery = Value.NativeQuery(Source, "SELECT * FROM Inventory_Enh_History.ItemBalance")
in
    RawQuery;

shared #"Inventory_Enh_History ItemBalance_DataDestination" = let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null]),
  Navigation_1 = Pattern{[workspaceId = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "62a3081e-4093-4f46-856c-f50aa58732fa"]}[Data],
  TableNavigation = Navigation_2{[Id = "itembalance", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
