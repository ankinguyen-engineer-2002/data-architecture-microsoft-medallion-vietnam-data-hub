// ============================================================================
// Dataflow Gen2 — df_brz_PoDetail
// ============================================================================
// Project:     inventory_health (Phase 1, P0-1)
// Source:      ashley-edw.database.windows.net / ASHLEY_EDW
//              Wholesale_ProductSourcing_AFI.PoDetail (53 cols, EDW upstream)
// Destination: SupplyChain_Lakehouse (62a3081e-...) / Table podetail
// Reason:      Schema có trên Enterprise_Lakehouse nhưng 0 rows trong dev →
//              cần kéo full data từ EDW
// KPIs:        #2 Transfer In-Transit, #3 PO In-Transit, #4 PO On Order,
//              #15 Container Count, #17 Inactive Item Logic
// ============================================================================
// Setup: Fabric workspace → + New item → Dataflow Gen2 →
//        Advanced editor → paste ENTIRE content below → Save & Refresh
// ============================================================================

[StagingDefinition = [Kind = "FastCopy"]]
section Section1;

[DataDestinations = {
  [Definition = [Kind = "Reference", QueryName = "Wholesale_ProductSourcing_AFI PoDetail_DataDestination", IsNewTarget = true],
   Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]
}]
shared #"Wholesale_ProductSourcing_AFI PoDetail" = let
    // 1. Kết nối nguồn dữ liệu — EDW SQL Server
    Source = Sql.Database("ashley-edw.database.windows.net", "ASHLEY_EDW"),

    // 2. Native SQL Query — pull full bảng PoDetail (53 cols)
    // SELECT * trước để verify EDW có data thật; sau khi confirm → switch sang
    // explicit column list với TRIM/CAST như df_brz_SalesHistory_AFI_InvoiceDetail
    RawQuery = Value.NativeQuery(Source, "
        SELECT *
        FROM Wholesale_ProductSourcing_AFI.PoDetail
        -- Optional date filter (uncomment khi confirm column tên):
        -- WHERE CreatedDate >= '2023-01-01'
        --    OR PoCreatedDate >= '2023-01-01'
    ")
in
    RawQuery;

shared #"Wholesale_ProductSourcing_AFI PoDetail_DataDestination" = let
    Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null]),
    Navigation_1 = Pattern{[workspaceId = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"]}[Data],
    Navigation_2 = Navigation_1{[lakehouseId = "62a3081e-4093-4f46-856c-f50aa58732fa"]}[Data],
    TableNavigation = Navigation_2{[Id = "podetail", ItemKind = "Table"]}?[Data]?
in
    TableNavigation;

// ============================================================================
// AFTER FIRST REFRESH — verify on Lakehouse SQL endpoint:
//
//   SELECT COUNT(*) AS row_count,
//          COUNT(DISTINCT PoNumber) AS distinct_po,  -- adjust col name
//          MIN(CreatedDate) AS earliest,
//          MAX(CreatedDate) AS latest
//   FROM SupplyChain_Lakehouse.dbo.PoDetail;
//
// Expect: row count > 0 (vs current 0 rows on Enterprise_Lakehouse mirror)
// ============================================================================
