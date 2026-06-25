// ============================================================================
// Dataflow Gen2 — df_brz_PurchaseOrderSnapshot
// ============================================================================
// Project:     inventory_health (Phase 2, P2)
// Source:      ashley-edw.database.windows.net / ASHLEY_EDW
//              SupplyChain_Enh.PurchaseOrderSnapshot
// Destination: SupplyChain_Lakehouse (62a3081e-...) / Table purchaseordersnapshot
// Reason:      EDW-only source per Track A doc — "anh sếp dùng cho PO-as-of query".
//              Lake không có. Unlock Phase 2 PO-as-of feature.
// KPIs:        Historical PO snapshot for time-travel queries (e.g., "what was
//              the open PO on 2026-04-01?"). Complements current
//              v_PurchaseOrderSnapshotDaily which captures forward only.
// ============================================================================
// Reuses same connection IDs as df_brz_PoDetail_v2:
//   - SQL EDW: ClusterId=e6436dba-643f-44c3-ad6f-51a8cbc45b81,
//              DatasourceId=67192c57-5e5c-4ad4-8801-858e75656fe4
//   - Lakehouse: ClusterId=e6436dba-..., DatasourceId=b4311980-...
// ============================================================================
// IMPORTANT — verify on first refresh:
//   1. Confirm EDW có schema 'SupplyChain_Enh' và table 'PurchaseOrderSnapshot'
//   2. Nếu fail "Invalid object name" → query SSMS direct on EDW
//      → use actual schema name
// ============================================================================

[StagingDefinition = [Kind = "FastCopy"]]
section Section1;

[DataDestinations = {
  [Definition = [Kind = "Reference", QueryName = "SupplyChain_Enh PurchaseOrderSnapshot_DataDestination", IsNewTarget = true],
   Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]
}]
shared #"SupplyChain_Enh PurchaseOrderSnapshot" = let
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW"),
    RawQuery = Value.NativeQuery(Source, "SELECT * FROM SupplyChain_Enh.PurchaseOrderSnapshot")
in
    RawQuery;

shared #"SupplyChain_Enh PurchaseOrderSnapshot_DataDestination" = let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null]),
  Navigation_1 = Pattern{[workspaceId = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "62a3081e-4093-4f46-856c-f50aa58732fa"]}[Data],
  TableNavigation = Navigation_2{[Id = "purchaseordersnapshot", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
