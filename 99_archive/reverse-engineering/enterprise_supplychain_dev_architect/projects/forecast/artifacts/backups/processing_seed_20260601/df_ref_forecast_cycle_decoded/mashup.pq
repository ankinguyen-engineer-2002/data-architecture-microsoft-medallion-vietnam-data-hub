[StagingDefinition = [Kind = "FastCopy"]]
section Section1;
[DataDestinations = {[Definition = [Kind = "Reference", QueryName = "df_brz_FcstConsensusCycleDates_DataDestination", IsNewTarget = true], Settings = [Kind = "Automatic", TypeSettings = [Kind = "Table"]]]}]
shared df_brz_FcstConsensusCycleDates = let
    // 1. Kết nối nguồn dữ liệu SharePoint
    Source = SharePoint.Tables("https://masterashley.sharepoint.com/sites/SCPGlobalTeam", [Implementation = "2.0", ViewMode = "All"]),
    #"Navigation 1" = Source{[Id = "94a48657-f48d-4828-a009-a4d635e1657f"]}[Items],

    // 2. Lọc bỏ các dòng có CycleName là null (Tương đương WHERE CycleName IS NOT NULL)
    #"Filtered Rows" = Table.SelectRows(#"Navigation 1", each ([CycleName] <> null)),

    // 3. Chọn các cột cần thiết và thực hiện đổi tên (Tương đương SELECT ... AS ...)
    #"Selected Columns" = Table.SelectColumns(#"Filtered Rows", 
        {"CycleName", "CycleDescription", "CycleMonthLastDate", "FcstSnapshot", "ExceptionNote", "Modified", "Created"}),

    #"Renamed Columns" = Table.RenameColumns(#"Selected Columns", {
        {"CycleName", "code_cycle"}, 
        {"CycleDescription", "name_cycle_description"}, 
        {"CycleMonthLastDate", "dt_cycle_month_last"}, 
        {"FcstSnapshot", "dt_forecast_snapshot"}, 
        {"ExceptionNote", "name_exception_note"}, 
        {"Modified", "ts_modified"}, 
        {"Created", "ts_created"}
    }),

    // 4. Cắt khoảng trắng dư thừa (Tương đương TRIM)
    #"Trimmed Text" = Table.TransformColumns(#"Renamed Columns", {
        {"code_cycle", Text.Trim, type text}, 
        {"name_cycle_description", Text.Trim, type text}, 
        {"name_exception_note", Text.Trim, type text}
    }),

    // 5. Định dạng kiểu dữ liệu (Tương đương CAST ... AS DATE/TIMESTAMP)
    #"Final Typed Table" = Table.TransformColumnTypes(#"Trimmed Text", {
        {"dt_cycle_month_last", type date}, 
        {"dt_forecast_snapshot", type date}, 
        {"ts_modified", type datetime}, 
        {"ts_created", type datetime}
    })
in
    #"Final Typed Table";
shared df_brz_FcstConsensusCycleDates_DataDestination = let
  Pattern = Lakehouse.Contents([CreateNavigationProperties = false, EnableFolding = false, HierarchicalNavigation = null]),
  Navigation_1 = Pattern{[workspaceId = "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"]}[Data],
  Navigation_2 = Navigation_1{[lakehouseId = "62a3081e-4093-4f46-856c-f50aa58732fa"]}[Data],
  TableNavigation = Navigation_2{[Id = "ref_forecast_cycle", ItemKind = "Table"]}?[Data]?
in
  TableNavigation;
