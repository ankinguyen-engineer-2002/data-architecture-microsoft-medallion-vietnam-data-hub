-- Live TABLE DDL — SupplyChain_Processing_Warehouse
-- Generated 2026-05-22
-- 57 tables

-- ForecastHistory_Enh.ForecastDemandMonthly (11 cols)
CREATE TABLE [ForecastHistory_Enh].[ForecastDemandMonthly] (
    [ItemSKU] varchar(50),
    [WarehouseCode] varchar(10),
    [CustomerGroupCode] varchar(50),
    [FSCMonthFirst] date,
    [FSCMonthLast] date,
    [Snapshot] date,
    [HorizonCode] varchar(10),
    [QtyForecast] float,
    [VersionCode] varchar(20),
    [StatusCode] varchar(20),
    [LoadDT] datetime2
);
GO

-- ForecastHistory_Enh.NaiveForecastMonthly (9 cols)
CREATE TABLE [ForecastHistory_Enh].[NaiveForecastMonthly] (
    [ItemSKU] varchar(8000),
    [WarehouseCode] varchar(8000),
    [CustomerGroupCode] varchar(8000),
    [FSCMonthFirst] date,
    [FSCMonthLast] date,
    [QtyDemand] int,
    [StatusCode] varchar(14) NOT NULL,
    [VersionName] varchar(14) NOT NULL,
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.AwdHelper (8 cols)
CREATE TABLE [InventoryHistory_Enh].[AwdHelper] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [AsOfDate] date,
    [Fwd13WForecastQty] decimal(18,4),
    [Hist13WShippedQty] decimal(18,4),
    [AwdQty] decimal(18,4),
    [AwdSource] varchar(20),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.ForecastSnapshotWeekly (10 cols)
CREATE TABLE [InventoryHistory_Enh].[ForecastSnapshotWeekly] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [SnapshotDate] date,
    [FiscalMonth] int,
    [FiscalMonthDate] date,
    [ForecastQty] decimal(18,4),
    [PermComptQty] decimal(18,4),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.ForecastSnapshotWeeklySat (9 cols)
CREATE TABLE [InventoryHistory_Enh].[ForecastSnapshotWeeklySat] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [SnapshotDate] date,
    [FiscalMonth] int,
    [FiscalMonthDate] date,
    [ForecastQty] decimal(18,4),
    [PermComptQty] decimal(18,4),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128)
);
GO

-- InventoryHistory_Enh.HoldingTransferSnapshotDaily (12 cols)
CREATE TABLE [InventoryHistory_Enh].[HoldingTransferSnapshotDaily] (
    [SnapshotDate] date,
    [TransferNumber] varchar(50),
    [TransferLine] int,
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [TransferQty] decimal(18,4),
    [ShippedQty] decimal(18,4),
    [TransferCube] decimal(18,4),
    [HeaderStatus] varchar(10),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.InventorySnapshotWeekly (15 cols)
CREATE TABLE [InventoryHistory_Enh].[InventorySnapshotWeekly] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [SnapshotDate] date,
    [FiscalMonth] int,
    [FiscalMonthDate] date,
    [OnHandQty] decimal(18,4),
    [SafetyStockTarget] decimal(18,4),
    [IOSafetyStock] decimal(18,4),
    [OrderQty] decimal(18,4),
    [BuildQty] decimal(18,4),
    [ItemStatus] varchar(10),
    [SourceLabel] varchar(50),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.ItemBalanceHistorical (8 cols)
CREATE TABLE [InventoryHistory_Enh].[ItemBalanceHistorical] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [WeekEndingDate] date,
    [OnHandQty] decimal(18,4),
    [ItemStatus] varchar(10),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.LastInvoiceHelper (6 cols)
CREATE TABLE [InventoryHistory_Enh].[LastInvoiceHelper] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [AsOfDate] date,
    [LastInvoiceDate] date,
    [WeeksSinceLastInvoice] int,
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.LogilityItemStatusSnapshotWeekly (10 cols)
CREATE TABLE [InventoryHistory_Enh].[LogilityItemStatusSnapshotWeekly] (
    [WeekEndingDate] date,
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [ItemStatus] varchar(20),
    [FutureStatus] varchar(20),
    [StatusChangeDate] date,
    [IsCertified] bit,
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.ManufacturingOrderSnapshotDaily (12 cols)
CREATE TABLE [InventoryHistory_Enh].[ManufacturingOrderSnapshotDaily] (
    [SnapshotDate] date,
    [MoNumber] varchar(50),
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [StatusCode] varchar(10),
    [OrderQty] decimal(18,4),
    [ReceivedQty] decimal(18,4),
    [MOOnOrderQty] decimal(18,4),
    [DueDateKey] int,
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.MovementFlagHelper (6 cols)
CREATE TABLE [InventoryHistory_Enh].[MovementFlagHelper] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [AsOfDate] date,
    [HasMovementLast17W] bit,
    [MovementCountLast17W] int,
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.PurchaseOrderSnapshotDaily (19 cols)
CREATE TABLE [InventoryHistory_Enh].[PurchaseOrderSnapshotDaily] (
    [SnapshotDate] date,
    [PoNumber] varchar(50),
    [PoLine] int,
    [VendorNumber] varchar(50),
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [StatusCode] varchar(10),
    [StockQty] decimal(18,4),
    [OrderedQty] decimal(18,4),
    [InTransitQtySource] decimal(18,4),
    [POOnOrderQty] decimal(18,4),
    [POInTransitQty] decimal(18,4),
    [TotalOpenPOQty] decimal(18,4),
    [DueDate] date,
    [EstimatedArrivalDate] date,
    [EstimatedDepartureDate] date,
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.PurchaseOrderSnapshotHistorical (10 cols)
CREATE TABLE [InventoryHistory_Enh].[PurchaseOrderSnapshotHistorical] (
    [SnapshotDate] date,
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [VendorNumber] varchar(50),
    [OrderedQty] decimal(18,4),
    [StatusCode] varchar(10),
    [DueDate] date,
    [UnitCost] decimal(18,4),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128)
);
GO

-- InventoryHistory_Enh.SafetyStockHelper (6 cols)
CREATE TABLE [InventoryHistory_Enh].[SafetyStockHelper] (
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [AsOfDate] date,
    [SafetyStockTarget] decimal(18,4),
    [SnapshotCount] int,
    [LoadDT] datetime2
);
GO

-- InventoryHistory_Enh.SalesShipment (12 cols)
CREATE TABLE [InventoryHistory_Enh].[SalesShipment] (
    [InvoiceNumber] decimal(18,0),
    [ItemSequence] decimal(18,0),
    [ItemSku] varchar(50),
    [WarehouseCode] varchar(50),
    [InvoiceDate] date,
    [OrderDate] date,
    [QuantityShipped] decimal(18,4),
    [QuantityOrdered] decimal(18,4),
    [Price] decimal(18,4),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- Meta.ApprovalLog (7 cols)
CREATE TABLE [Meta].[ApprovalLog] (
    [approval_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [approver_name] varchar(256),
    [approval_status] varchar(80),
    [approval_scope] varchar(256),
    [approved_at_utc] datetime2,
    [notes] varchar(2000)
);
GO

-- Meta.AssetAccessPolicy (9 cols)
CREATE TABLE [Meta].[AssetAccessPolicy] (
    [policy_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [access_mode] varchar(80),
    [requires_staging] bit,
    [requires_contract_validation] bit,
    [requires_reconciliation] bit,
    [requires_owner_approval] bit,
    [notes] varchar(2000),
    [is_active] bit
);
GO

-- Meta.AssetRegistry (38 cols)
CREATE TABLE [Meta].[AssetRegistry] (
    [asset_id] varchar(128) NOT NULL,
    [legacy_target_schema] varchar(128),
    [legacy_target_table] varchar(256),
    [legacy_layer] varchar(40),
    [legacy_view_name] varchar(512),
    [legacy_sp_name] varchar(256),
    [canonical_layer] varchar(80),
    [physical_workspace] varchar(256),
    [physical_item] varchar(256),
    [physical_schema] varchar(128),
    [physical_object] varchar(256),
    [access_mode] varchar(80),
    [domain_group] varchar(128),
    [project] varchar(128),
    [frequency] varchar(50),
    [cron_expression] varchar(128),
    [scheduled_hour] int,
    [next_run_time] datetime2,
    [load_type] varchar(80),
    [primary_key] varchar(1000),
    [watermark_column] varchar(256),
    [depends_on] varchar(4000),
    [source_objects] varchar(4000),
    [source_feed_type] varchar(80),
    [edw_exit_status] varchar(80),
    [is_enterprise_reusable] bit,
    [staging_reason] varchar(1000),
    [source_contract_status] varchar(80),
    [approval_status] varchar(80),
    [owner_name] varchar(256),
    [is_active] bit,
    [last_load_date] datetime2,
    [last_watermark_value] varchar(1000),
    [rows_loaded] bigint,
    [date_key] varchar(128),
    [date_range_days] int,
    [created_at_utc] datetime2,
    [updated_at_utc] datetime2
);
GO

-- Meta.AuditLog (10 cols)
CREATE TABLE [Meta].[AuditLog] (
    [AuditID] bigint NOT NULL,
    [AuditDateTime] datetime2 NOT NULL,
    [UserName] varchar(200),
    [Command] varchar(8000),
    [Description] varchar(8000),
    [ErrorMessage] varchar(8000),
    [AssetID] varchar(128),
    [RunID] varchar(128),
    [Severity] varchar(20),
    [LoadDT] datetime2
);
GO

-- Meta.DQGateRun (8 cols)
CREATE TABLE [Meta].[DQGateRun] (
    [dq_gate_run_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [run_id] varchar(128),
    [gate_name] varchar(128),
    [status] varchar(80),
    [checked_at_utc] datetime2,
    [failed_rule_count] int,
    [error_message] varchar(4000)
);
GO

-- Meta.DQRule (12 cols)
CREATE TABLE [Meta].[DQRule] (
    [rule_id] int,
    [rule_name] varchar(512),
    [target_schema] varchar(128),
    [target_table] varchar(256),
    [check_type] varchar(80),
    [column_name] varchar(256),
    [severity] varchar(80),
    [threshold] varchar(128),
    [params] varchar(4000),
    [is_active] bit,
    [layer] varchar(40),
    [source_row_number] int
);
GO

-- Meta.DeploymentChecklist (7 cols)
CREATE TABLE [Meta].[DeploymentChecklist] (
    [checklist_id] varchar(128) NOT NULL,
    [phase_name] varchar(256),
    [check_name] varchar(512),
    [status] varchar(80),
    [owner_name] varchar(256),
    [checked_at_utc] datetime2,
    [notes] varchar(2000)
);
GO

-- Meta.LineageEdge (8 cols)
CREATE TABLE [Meta].[LineageEdge] (
    [edge_id] varchar(128) NOT NULL,
    [source_asset] varchar(512),
    [target_asset] varchar(512),
    [edge_type] varchar(80),
    [transform_type] varchar(80),
    [is_synthetic] bit,
    [created_at_utc] datetime2,
    [notes] varchar(2000)
);
GO

-- Meta.ObjectClassification (6 cols)
CREATE TABLE [Meta].[ObjectClassification] (
    [asset_id] varchar(128) NOT NULL,
    [legacy_layer] varchar(40),
    [canonical_layer] varchar(80),
    [classification] varchar(256),
    [bob_alignment_status] varchar(80),
    [notes] varchar(2000)
);
GO

-- Meta.PerformanceBaseline (6 cols)
CREATE TABLE [Meta].[PerformanceBaseline] (
    [baseline_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [metric_name] varchar(128),
    [metric_value] decimal(38,6),
    [captured_at_utc] datetime2,
    [notes] varchar(2000)
);
GO

-- Meta.PipelineCostLog (8 cols)
CREATE TABLE [Meta].[PipelineCostLog] (
    [cost_log_id] varchar(128) NOT NULL,
    [pipeline_run_id] varchar(128),
    [item_name] varchar(256),
    [capacity_id] varchar(128),
    [duration_seconds] int,
    [estimated_cu_seconds] decimal(38,6),
    [captured_at_utc] datetime2,
    [notes] varchar(2000)
);
GO

-- Meta.PipelineRunLog (8 cols)
CREATE TABLE [Meta].[PipelineRunLog] (
    [pipeline_run_id] varchar(128) NOT NULL,
    [pipeline_name] varchar(256),
    [project] varchar(128),
    [status] varchar(80),
    [start_time_utc] datetime2,
    [end_time_utc] datetime2,
    [trigger_type] varchar(80),
    [error_message] varchar(4000)
);
GO

-- Meta.ReconciliationResult (9 cols)
CREATE TABLE [Meta].[ReconciliationResult] (
    [result_id] varchar(128) NOT NULL,
    [rule_id] varchar(128),
    [run_id] varchar(128),
    [status] varchar(80),
    [source_value] decimal(38,6),
    [target_value] decimal(38,6),
    [variance_value] decimal(38,6),
    [checked_at_utc] datetime2,
    [error_message] varchar(4000)
);
GO

-- Meta.ReconciliationRule (8 cols)
CREATE TABLE [Meta].[ReconciliationRule] (
    [rule_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [source_object] varchar(512),
    [target_object] varchar(512),
    [reconciliation_type] varchar(80),
    [tolerance_value] decimal(18,4),
    [severity] varchar(80),
    [is_active] bit
);
GO

-- Meta.RunLog (12 cols)
CREATE TABLE [Meta].[RunLog] (
    [run_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [object_name] varchar(512),
    [layer_name] varchar(80),
    [status] varchar(80),
    [start_time_utc] datetime2,
    [end_time_utc] datetime2,
    [start_time_cst] datetime2,
    [end_time_cst] datetime2,
    [rows_loaded] bigint,
    [error_message] varchar(4000),
    [load_type] varchar(80)
);
GO

-- Meta.SecurityPolicy (8 cols)
CREATE TABLE [Meta].[SecurityPolicy] (
    [policy_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [security_classification] varchar(128),
    [workspace_role] varchar(128),
    [sql_grant_pattern] varchar(512),
    [semantic_rls_policy] varchar(512),
    [is_active] bit,
    [notes] varchar(2000)
);
GO

-- Meta.SemanticModelContract (9 cols)
CREATE TABLE [Meta].[SemanticModelContract] (
    [contract_id] varchar(128) NOT NULL,
    [gold_asset_id] varchar(128),
    [semantic_model_name] varchar(256),
    [source_mode] varchar(80),
    [direct_lake_required] bit,
    [fallback_allowed] bit,
    [validation_status] varchar(80),
    [last_validated_utc] datetime2,
    [notes] varchar(2000)
);
GO

-- Meta.SilverDagWaveRuntime (9 cols)
CREATE TABLE [Meta].[SilverDagWaveRuntime] (
    [runtime_id] varchar(128) NOT NULL,
    [project] varchar(128),
    [asset_id] varchar(128),
    [physical_schema] varchar(128),
    [physical_object] varchar(256),
    [wave_number] int,
    [dependency_count] int,
    [is_active] bit,
    [computed_at_utc] datetime2
);
GO

-- Meta.SourceContract (10 cols)
CREATE TABLE [Meta].[SourceContract] (
    [contract_id] int,
    [target_table] varchar(256),
    [source_object] varchar(512),
    [column_name] varchar(256),
    [expected_data_type] varchar(128),
    [is_nullable] bit,
    [is_active] bit,
    [created_date] datetime2,
    [last_validated] datetime2,
    [validation_status] varchar(80)
);
GO

-- Meta.SourceContractRun (6 cols)
CREATE TABLE [Meta].[SourceContractRun] (
    [contract_run_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [run_id] varchar(128),
    [validation_status] varchar(80),
    [checked_at_utc] datetime2,
    [error_message] varchar(4000)
);
GO

-- Meta.SourceFeed (13 cols)
CREATE TABLE [Meta].[SourceFeed] (
    [source_feed_id] varchar(128) NOT NULL,
    [asset_id] varchar(128),
    [source_name] varchar(512),
    [source_workspace] varchar(256),
    [source_item] varchar(256),
    [source_schema] varchar(256),
    [source_object] varchar(256),
    [feed_type] varchar(80),
    [is_temporary] bit,
    [exit_status] varchar(80),
    [notes] varchar(2000),
    [is_active] bit,
    [created_at_utc] datetime2
);
GO

-- Meta.TableDictionary (69 cols)
CREATE TABLE [Meta].[TableDictionary] (
    [ServerName] varchar(50) NOT NULL,
    [DatabaseName] varchar(150) NOT NULL,
    [SchemaName] varchar(150) NOT NULL,
    [TableName] varchar(150) NOT NULL,
    [ObjectType] varchar(50),
    [PrimaryKey] varchar(500),
    [AlternateKey] varchar(500),
    [StorageType] varchar(50),
    [RowSToreClusteredKey] varchar(750),
    [AdditionalIndexes] varchar(500),
    [DistributionKey] varchar(500),
    [IndexType] varchar(25),
    [SourceSystem] varchar(150),
    [SourceServer] varchar(100),
    [SourceDatabase] varchar(200),
    [SourceObject] varchar(500),
    [SourceObjectAlias] varchar(100),
    [SourcePlatform] varchar(100),
    [ReplicatedSource] varchar(500),
    [ETLTool] varchar(50),
    [PackageName] varchar(500),
    [TFSPath] varchar(400),
    [JobName] varchar(100),
    [JobServer] varchar(50),
    [RefreshRate] int,
    [RefreshDescription] varchar(50),
    [UpdateMethod] varchar(80),
    [ExtractQuery] varchar(8000),
    [UpdateQuery] varchar(8000),
    [AdditionaNotes] varchar(8000),
    [InvalidCount] decimal(12,0),
    [RowCount] decimal(12,0),
    [CreateDate] datetime2,
    [Modified] datetime2,
    [CreatedBy] varchar(200),
    [ModifiedBy] varchar(200),
    [LastAudit] datetime2,
    [ErrorMsg] varchar(500),
    [CreatedDate] datetime2,
    [Created] datetime2,
    [SourceObjectType] varchar(15),
    [PartitionKey] varchar(200),
    [ColumnStatsCount] int,
    [ColumnCount] int,
    [ColumnStatsLastUpdated] datetime2,
    [DeletedRows] decimal(12,0),
    [DataLake] varchar(200),
    [DataLakeFolder] varchar(200),
    [DataLakeFolderArchive] varchar(500),
    [ReplicatedSourceExpiryHours] int,
    [ReplicatedSourceArchiveExpiryHours] int,
    [StageDataLakeFolder] varchar(150),
    [LastBatchStartDate] datetime2,
    [LibraryList] varchar(500),
    [DateKey] varchar(50),
    [DateRangeDays] int,
    [OperationKey] varchar(128),
    [PII] varchar(8000),
    [ValidKeyValues] bit,
    [SelectColumn] varchar(8000),
    [DataBricksClusterVersion] varchar(30),
    [DataBricksNodeType] varchar(30),
    [DataBricksClusterRange] varchar(10),
    [v9_Layer] varchar(50),
    [v9_ExecutionOrder] int,
    [v9_DependsOn] varchar(500),
    [v9_WatermarkColumn] varchar(100),
    [v9_LastWatermarkValue] varchar(100),
    [v9_IsActive] bit
);
GO

-- Meta.TableDictionary_UpdateLog (9 cols)
CREATE TABLE [Meta].[TableDictionary_UpdateLog] (
    [UpdateLogID] bigint NOT NULL,
    [DatabaseName] varchar(150) NOT NULL,
    [SchemaName] varchar(150) NOT NULL,
    [TableName] varchar(150) NOT NULL,
    [LastUpdated] datetime2 NOT NULL,
    [UpdateQuery] varchar(5000),
    [RowsLoaded] bigint,
    [AssetID] varchar(128),
    [RunID] varchar(128)
);
GO

-- OpenOrderHistory_Enh.OpenOrderLineLevel (26 cols)
CREATE TABLE [OpenOrderHistory_Enh].[OpenOrderLineLevel] (
    [OrderID] varchar(8000),
    [ItemSequenceNum] int,
    [Customer] varchar(8000),
    [ShipToCode] varchar(8000),
    [AccountShipTo] varchar(8000),
    [ItemSKU] varchar(8000),
    [WarehouseCode] varchar(8000),
    [QtyOpenOrder] int,
    [QtyBackorder] int,
    [AmtOpenOrder] decimal(13,2),
    [AmtBackorder] decimal(13,2),
    [OrderTaken] date,
    [OriginalPromise] date,
    [CurrentPromise] date,
    [OriginalRequest] date,
    [CurrentRequest] date,
    [CurrentLoad] date,
    [OrderArrivalCode] varchar(8000),
    [AllocationFlagCode] varchar(200),
    [LoadDateChangesNum] int,
    [LeadTimeDaysNum] int,
    [ShippingInstructionsName] varchar(8000),
    [CustomerSKUName] varchar(8000),
    [AmtOrderFreight] decimal(12,2),
    [PastDueFlagCode] varchar(10) NOT NULL,
    [LoadDT] datetime2
);
GO

-- OpenOrderHistory_Enh.OpenOrderMonthly (14 cols)
CREATE TABLE [OpenOrderHistory_Enh].[OpenOrderMonthly] (
    [ItemSKU] varchar(8000),
    [WarehouseCode] varchar(8000),
    [CustomerGroupCode] varchar(8000),
    [FSCMonthFirst] date,
    [FSCMonthLast] date,
    [QtyOpenOrder] int,
    [QtyBackorder] int,
    [AmtOpenOrder] decimal(38,2),
    [AmtBackorder] decimal(38,2),
    [OrderLines] int,
    [DistinctOrders] int,
    [QtyPastDue] int,
    [AmtPastDue] decimal(38,2),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.Calendar (75 cols)
CREATE TABLE [ReferenceMaster_Enh].[Calendar] (
    [SKDate] int,
    [MapicsDate] int,
    [Date] date,
    [Datetime] date,
    [Calendar] date,
    [CalendarDateName] varchar(8000),
    [CalDateIndicatorNum] int,
    [CalDayOfWeekNum] int,
    [CalDayOfWeekName] varchar(8000),
    [CalDayOfMonthNum] int,
    [CalDayOfYearNum] int,
    [CalWeekNum] int,
    [CalWeekIndicatorNum] int,
    [CalWeekYearNum] int,
    [CalWeekYearName] varchar(8000),
    [CalWeekFirst] date,
    [CalWeekLast] date,
    [CalWeekOfMonthNum] int,
    [CalMonthNum] int,
    [CalMonthIndicatorNum] int,
    [CalMonthYearNum] int,
    [CalMonthName] varchar(8000),
    [CalMonthYearName] varchar(8000),
    [CalMonthFirst] date,
    [CalMonthLast] date,
    [CalQuarterNum] int,
    [CalQuarterName] varchar(8000),
    [CalQuarterIndicatorNum] int,
    [CalQuarterYearNum] int,
    [CalQuarterYearName] varchar(8000),
    [CalSemesterNum] int,
    [CalSemesterYearNum] int,
    [CalYearNum] int,
    [CalYearName] varchar(8000),
    [CalYearIndicatorNum] int,
    [FiscalDate] date,
    [FiscalDateName] varchar(8000),
    [FSCDateIndicatorNum] int,
    [FSCDayOfWeekNum] int,
    [FSCDayOfWeekName] varchar(8000),
    [FSCDayOfMonthNum] int,
    [FSCDayOfYearNum] int,
    [FSCWeekNum] int,
    [FSCWeekIndicatorNum] int,
    [FSCWeekYearNum] int,
    [FSCWeekYearName] varchar(8000),
    [FSCWeekFirst] date,
    [FSCWeekLast] date,
    [FSCWeekOfMonthNum] int,
    [FSCMonthNum] int,
    [FSCMonthIndicatorNum] int,
    [FSCMonthYearNum] int,
    [FSCMonthName] varchar(8000),
    [FSCMonthYearName] varchar(8000),
    [FSCMonthFirst] date,
    [FSCMonthLast] date,
    [FSCQuarterNum] int,
    [FSCQuarterName] varchar(8000),
    [FSCQuarterIndicatorNum] int,
    [FSCQuarterYearNum] int,
    [FSCQuarterYearName] varchar(8000),
    [FSCQuarterFirst] date,
    [FSCQuarterLast] date,
    [FSCSemesterNum] int,
    [FSCSemesterYearNum] int,
    [FSCYearNum] int,
    [FSCYearName] varchar(8000),
    [FSCYearIndicatorNum] int,
    [FSCYearFirst] date,
    [FSCYearLast] date,
    [HolidayIndicatorCode] varchar(8000),
    [HolidayName] varchar(8000),
    [WorkingDayCode] varchar(8000),
    [WeekdayWeekendCode] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.CustomerAccount (54 cols)
CREATE TABLE [ReferenceMaster_Enh].[CustomerAccount] (
    [Cmacustomernumber] varchar(8000),
    [Cmaphone] varchar(8000),
    [Cmafaxtn] varchar(8000),
    [Cmacontact] varchar(8000),
    [Cmaemail] varchar(8000),
    [Cmaprimaryterritory] varchar(8000),
    [Cmaminimumfreightcode] varchar(8000),
    [Cmacreditlimitamount] int,
    [Cmatermscode] varchar(8000),
    [Cmatermsdays] smallint,
    [Cmacreditterritoryid] smallint,
    [Cmacancelbackorders] smallint,
    [Cmaallowpartialshipment] smallint,
    [Cmacustomerclasscode] varchar(8000),
    [Cmalanguagecode] varchar(8000),
    [Cmastatementcode] smallint,
    [Cmaitemcrossreferencecode] varchar(8000),
    [Cmaterritorychangedate] datetime2,
    [Cmacreditauthorizationcode] varchar(8000),
    [Cmamemo] varchar(8000),
    [Cmachgcustar] bit,
    [Cmachgcust] bit,
    [Cmachgcustext] bit,
    [Cmapercentavailablecredit] decimal(3,2),
    [Cmacommaudit] bit,
    [Cmainheritblocking] bit,
    [Cmacustomername] varchar(8000),
    [Usra] varchar(8000),
    [Dtea] datetime2,
    [Usrc] varchar(8000),
    [Dtec] datetime2,
    [Acrec] varchar(8000),
    [Cmalaststatuschangedate] datetime2,
    [Cmabillingaddressid] int,
    [Cmadbaname] varchar(8000),
    [Cmalatechargepercent] decimal(5,4),
    [Cmaminpreapprovalamount] decimal(12,2),
    [Cmacreditaddesscode] varchar(8000),
    [Cmarfctaxidnumber] varchar(8000),
    [Cmadocumentationhold] varchar(8000),
    [Cmaparsbypurchaser] varchar(8000),
    [Cma10digitscheduleb] varchar(8000),
    [Cmatypeofinsurance] varchar(8000),
    [Cmainsexpirationdate] datetime2,
    [Cmainscoveragerequested] decimal(10,2),
    [Cmainscoverageapproved] decimal(10,2),
    [Cmainsurancestatus] varchar(8000),
    [Cmahomestorefacingwhse] varchar(8000),
    [Cmaappcd] int,
    [Cmadeductterritoryid] decimal(2,0),
    [Cmacurrencycode] varchar(8000),
    [Cmaallowallowancecredits] bit,
    [Cmacustomerchannelid] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.CustomerAccountGroup (5 cols)
CREATE TABLE [ReferenceMaster_Enh].[CustomerAccountGroup] (
    [Customer] varchar(8000),
    [CustomerGroupCode] varchar(8000),
    [CustomerGroupLevel3Code] varchar(8000),
    [BusinessTypeCode] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.CustomerGrouping (3 cols)
CREATE TABLE [ReferenceMaster_Enh].[CustomerGrouping] (
    [CustomerGroupCode] varchar(8000),
    [Customer] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.CustomerShippingLocation (88 cols)
CREATE TABLE [ReferenceMaster_Enh].[CustomerShippingLocation] (
    [Commaudit] bit,
    [Commaudit2] bit,
    [Cslcustomernumber] varchar(8000),
    [Cslshiptonumber] varchar(8000),
    [Cslmapicssequencenumber] smallint,
    [Cslname] varchar(8000),
    [Csmshpa1] varchar(8000),
    [Csmshpa2] varchar(8000),
    [Csmshpa3] varchar(8000),
    [Csmshpzp] varchar(8000),
    [Csmshpst] varchar(8000),
    [Csmshpco] varchar(8000),
    [Csmphone] varchar(8000),
    [Csmfaxtn] varchar(8000),
    [Csltaxexempt] varchar(8000),
    [Csmwebsite] varchar(8000),
    [Csmemail] varchar(8000),
    [Cslcommissioncode] varchar(8000),
    [Cslfreightcode] varchar(8000),
    [Cslpricecode] varchar(8000),
    [Csldiscountcode] varchar(8000),
    [Cslcommissionsplit] decimal(7,4),
    [Csldefaultwarehouse] varchar(8000),
    [Cslshippingterritory] varchar(8000),
    [Cslbusinesstype] varchar(8000),
    [Cslshiptype] varchar(8000),
    [Csltranscomprimaryid] varchar(8000),
    [Csmcontact] varchar(8000),
    [Cslcomment1] varchar(8000),
    [Cslcomment2] varchar(8000),
    [Cslterritoryeffectivitydate] datetime2,
    [Cslcrmid] varchar(8000),
    [Csmcsphone] varchar(8000),
    [Csmcsfax] varchar(8000),
    [Csmcscontact] varchar(8000),
    [Csmcsemail] varchar(8000),
    [Cslmemo] varchar(8000),
    [CsmmsaFips] varchar(8000),
    [Csmrmcitynumber] int,
    [Csltranscomalternateid] varchar(8000),
    [Csmdirections] varchar(8000),
    [Csmcrossstreet] varchar(8000),
    [Csmchgaddr] bit,
    [Csmchgship] bit,
    [Csmchgshipext] bit,
    [Csmchgcust] bit,
    [Usra] varchar(8000),
    [Dtea] datetime2,
    [Usrc] varchar(8000),
    [Dtec] datetime2,
    [Acrec] varchar(8000),
    [Csmcounty] varchar(8000),
    [Cslblockreporderentry] bit,
    [Cslcustomersegment] smallint,
    [Csllaststatuschangedate] datetime2,
    [Cslbuyeraddressid] int,
    [Cslpartylocationid] int,
    [Cslrouteaddressid] int,
    [Csldefaultordertype1] varchar(8000),
    [Csldefaultordertype2] varchar(8000),
    [Csldefaultordertype3] varchar(8000),
    [Csldefaultordertype4] varchar(8000),
    [Csmshled] smallint,
    [Csmappcd] int,
    [Cslallowfax] varchar(8000),
    [Csldirectconsumer] varchar(8000),
    [Csldeliveryunitofmeasure] varchar(8000),
    [Csldeliveryunitofmeasurefence] decimal(7,2),
    [Cslexportslclconsolidationflag] varchar(8000),
    [Cslexportsdocumentcountry] varchar(8000),
    [Cslexportsproductonpallets] varchar(8000),
    [Cslexportsappointmentsrequired] varchar(8000),
    [Cslhasdock] bit,
    [Cslhasdockuserdate] varchar(8000),
    [Cslexpressshippingmethod] varchar(8000),
    [Csldirectincludeshipto] varchar(8000),
    [Cslexpresshandlingcharge] decimal(4,3),
    [Cslexpressminimum] decimal(10,2),
    [Cslexpressmaximum] decimal(10,2),
    [Csldefaultlanguage] varchar(8000),
    [Cslexpressservicecontractnumber] varchar(8000),
    [Cslusenegotiatedfreightrate] varchar(8000),
    [Cslusestandardfreightrate] varchar(8000),
    [Csldonotrepriceorders] varchar(8000),
    [Cslpricinguseofflinefiles] varchar(8000),
    [Cslreturnaddressid] int,
    [Cslreturnaddressname] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.ForecastCycle (8 cols)
CREATE TABLE [ReferenceMaster_Enh].[ForecastCycle] (
    [CycleCode] varchar(8000),
    [CycleDescriptionName] varchar(8000),
    [CycleMonthLast] date,
    [ForecastSnapshot] date,
    [ExceptionNoteName] varchar(8000),
    [TsModified] datetime2,
    [TsCreated] datetime2,
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.ForecastHorizon (3 cols)
CREATE TABLE [ReferenceMaster_Enh].[ForecastHorizon] (
    [HorizonCode] varchar(14) NOT NULL,
    [Rank] int NOT NULL,
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.ItemMaster (174 cols)
CREATE TABLE [ReferenceMaster_Enh].[ItemMaster] (
    [RowID] bigint NOT NULL,
    [ItemSKU] varchar(8000) NOT NULL,
    [ItemKey] varchar(8000) NOT NULL,
    [Item] varchar(8000),
    [ItemCode] varchar(8000),
    [SeriesNumber] varchar(8000),
    [ExtSeriesNumber] varchar(8000),
    [FrameNumber] varchar(8000),
    [QtyInBox] decimal(4,0),
    [UOM] varchar(8000),
    [ProductHeightMeters] decimal(7,2),
    [ProductWidthMeters] decimal(7,2),
    [ProductDepthMeters] decimal(7,2),
    [CartonHeightMeters] decimal(7,2),
    [CartonWidthMeters] decimal(7,2),
    [CartonDepthMeters] decimal(7,2),
    [ProductHeightInches] decimal(7,2),
    [ProductWidthInches] decimal(7,2),
    [ProductDepthInches] decimal(7,2),
    [CartonHeightInches] decimal(7,2),
    [CartonWidthInches] decimal(7,2),
    [CartonDepthInches] decimal(7,2),
    [Cubes] decimal(5,2),
    [Seats] decimal(5,2),
    [ItemDescription] varchar(8000),
    [SeriesName] varchar(8000),
    [SeriesColor] varchar(8000),
    [Colors] varchar(8000),
    [ItemDescriptionSeries] varchar(8000),
    [SHItemDescriptionSeries] varchar(8000),
    [SHSeriesDescription] varchar(8000),
    [ItemDescriptionSeriesItemColor] varchar(8000),
    [ChildStyleDescription] varchar(8000),
    [ParentStyleDescription] varchar(8000),
    [SeriesDescription] varchar(8000),
    [ItemName] varchar(8000),
    [ItemConsumerDescription] varchar(8000),
    [RetailTypeDescription] varchar(8000),
    [MainPieceItem] varchar(8000),
    [ItemClass] varchar(8000),
    [ItemClassCode] varchar(8000),
    [ItemClassName] varchar(8000),
    [ProductLine] varchar(8000),
    [RetailCategoryCode] varchar(8000),
    [RetailCategoryDescription] varchar(8000),
    [RetailCategoryName] varchar(8000),
    [RetailDepartmentName] varchar(8000),
    [RetailCategoryGroup] varchar(8000),
    [RetailCategoryChargeType] varchar(8000),
    [AFIFinanceDivision] varchar(8000),
    [AFIFinanceDivisionCode] varchar(8000),
    [AFISalesCategoryCode] varchar(8000),
    [AFISalesCategory] varchar(8000),
    [ItemStyleCode] varchar(8000),
    [ItemStyleGroup] varchar(8000),
    [ItemStyle] varchar(8000),
    [Division] varchar(8000),
    [AFISalesDivisionCode] varchar(8000),
    [AFISalesDivision] varchar(8000),
    [KeyItem] bit,
    [ItemType] varchar(8000),
    [SalesClassCode] varchar(8000),
    [SalesClassDescription] varchar(8000),
    [SalesClass] varchar(8000),
    [DiscountClassCode] varchar(8000),
    [DiscountClassDescription] varchar(8000),
    [DiscountClass] varchar(8000),
    [CommissionClassCode] varchar(8000),
    [CommissionClassDescription] varchar(8000),
    [CommissionClass] varchar(8000),
    [FreightClassCode] varchar(8000),
    [FreightClassDescription] varchar(8000),
    [FreightClass] varchar(8000),
    [AFIItemStatus] varchar(8000),
    [SellableItemFlag] varchar(8000),
    [ManufacturingStatus] varchar(8000),
    [ResponsibleOffice] varchar(8000),
    [ResponsibleOfficeName] varchar(8000),
    [ImportDomesticCode] varchar(8000),
    [CountryofOrigin] varchar(8000),
    [PrimaryVendor] varchar(8000),
    [ManufacturingStatusChangeDate] date,
    [ItemForecastPlannerID] varchar(8000),
    [NewItemFlag] bit,
    [DiscontinuedFlag] bit,
    [DiscontinuedYearPeriod] varchar(8000),
    [CommonCarrierFlag] varchar(8000),
    [ExpressShipFlag] varchar(8000),
    [DiscontinuedDate] date,
    [SeriesDateArchived] date,
    [SeriesDiscontinuedFlag] bit,
    [PreviousStatusCode] varchar(8000),
    [StatusCodeChangeDate] date,
    [CurrentUnitCost] decimal(19,8),
    [CEXCode] varchar(8000),
    [MarketIntroducedAt] varchar(8000),
    [MerchandisingCategory] smallint,
    [PricePoint] int,
    [ItemGrouping] varchar(8000),
    [SeriesGrouping] smallint,
    [MasterGroupCode] varchar(8000),
    [AssociationCode] varchar(8000),
    [MarketingItemStatus] varchar(8000),
    [MarketingStatusDescription] varchar(8000),
    [Lifestyle] varchar(8000),
    [CommodityItem] bit,
    [F123ProductFlag] bit,
    [HSCoreProductFlag] bit,
    [HSProprietaryProductFlag] bit,
    [HSExclusiveFlag] bit,
    [BerklineProductFlag] bit,
    [BenchcraftProductFlag] bit,
    [NewMillenniumProductFlag] bit,
    [BardiniProductFlag] bit,
    [ShanghaiStore] bit,
    [DefaultGroup] bit,
    [GoodBetterBestForPricePoint] varchar(8000),
    [GBBSortId] int,
    [InitialInvoicePeriod] varchar(8000),
    [InitialInvoiceQty] decimal(38,0),
    [MarketBeginDate] date,
    [MarketEndDate] date,
    [Showroom] varchar(8000),
    [ItemImage] varchar(8000),
    [FOBArcPrice] decimal(8,2),
    [DivisionRanking] int,
    [TrendArrow] varchar(8000),
    [ItemMerchGridOverridePhoto] varchar(8000),
    [GroupPriceIncr] decimal(5,0),
    [GroupPricePointType] varchar(8000),
    [ExclusiveComment] varchar(8000),
    [SeriesImage] varchar(8000),
    [SofaTableSeriesFlag] varchar(8000),
    [ReclinerSeriesFlag] varchar(8000),
    [PowerMotionSeriesFlag] varchar(8000),
    [WedgeSeriesFlag] varchar(8000),
    [DiningSeriesFlag] varchar(8000),
    [ItemThirdPartyItem] varchar(8000),
    [SeriesThirdParty] varchar(8000),
    [ItemHomeStoreProductLine] varchar(8000),
    [ItemEcomMerchantNotes] varchar(8000),
    [ItemAmazonBrandOwner] varchar(8000),
    [ItemSupplierDirectShipOnly] varchar(8000),
    [ConsumerChoiceFlag] varchar(8000),
    [EligibleForProtectionPlan] varchar(8000),
    [IsProtectionPlan] varchar(8000),
    [CollectiveClass] varchar(8000),
    [FriendlyDimensions] varchar(8000),
    [Knockout] varchar(8000),
    [Scene7ImageSet] varchar(8000),
    [FluffAFI] varchar(8000),
    [SeriesPrimary] varchar(8000),
    [SeriesMainImage] varchar(8000),
    [StandAloneFlag] varchar(8000),
    [SuppWeightNetWeightLbs] varchar(8000),
    [UnitWeightLbs] varchar(8000),
    [UPC] varchar(8000),
    [RetailBrandName] varchar(8000),
    [MfgWarranty] varchar(8000),
    [Material] varchar(8000),
    [SeriesFeatures] varchar(8000),
    [ItemIsRTA] varchar(8000),
    [PrimaryChannelSku] varchar(8000),
    [PrimarySeriesName] varchar(8000),
    [PrimarySeriesNumber] varchar(8000),
    [ERetailChannelSku] varchar(8000),
    [ERetailSeriesName] varchar(8000),
    [ERetailSeriesNumber] varchar(8000),
    [ItemTableShapeType] varchar(8000),
    [ItemBedSizeType] varchar(8000),
    [ItemBedStyleType] varchar(8000),
    [ItemGeneralColor] varchar(8000),
    [ItemPricePointRating] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.OrderType (21 cols)
CREATE TABLE [ReferenceMaster_Enh].[OrderType] (
    [OTCODE] varchar(8000),
    [OTDES1] varchar(8000),
    [OTDES2] varchar(8000),
    [OTUSER] varchar(8000),
    [OTDATE] decimal(8,0),
    [OORDCL] varchar(8000),
    [OROUTE] varchar(8000),
    [OOTCAT] varchar(8000),
    [OADCHG] varchar(8000),
    [OARFLG] varchar(8000),
    [OWNEXP] varchar(8000),
    [OMINEXC] varchar(8000),
    [OREQMNT] varchar(8000),
    [OFDESCH] varchar(8000),
    [OFDRIMS] varchar(8000),
    [OTRPTYP] varchar(8000),
    [OZNLTIM] varchar(8000),
    [OSPECHND] varchar(8000),
    [OAUTORSCH] varchar(8000),
    [OUSRDFN] varchar(8000),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.Vendor (5 cols)
CREATE TABLE [ReferenceMaster_Enh].[Vendor] (
    [VendorNumber] varchar(50),
    [VendorName] varchar(200),
    [SourceSystem] varchar(64),
    [SourceTable] varchar(128),
    [LoadDT] datetime2
);
GO

-- ReferenceMaster_Enh.Warehouse (9 cols)
CREATE TABLE [ReferenceMaster_Enh].[Warehouse] (
    [AFIWarehousesKey] int,
    [WarehouseCode] varchar(8000),
    [IntransitWarehouse] varchar(8000),
    [ContainerDirectWarehouse] varchar(8000),
    [ControlledWarehouse] int,
    [WarehouseLocation] varchar(8000),
    [WarehouseOrderGroup] varchar(8000),
    [FinanceInventoryReportFlag] int,
    [LoadDT] datetime2
);
GO

-- SalesHistory_Enh.ActualDemandMonthly (10 cols)
CREATE TABLE [SalesHistory_Enh].[ActualDemandMonthly] (
    [ItemSKU] varchar(8000),
    [WarehouseCode] varchar(8000),
    [CustomerGroupCode] varchar(8000),
    [FSCMonthFirst] date,
    [FSCMonthLast] date,
    [QtyDemand] decimal(38,0),
    [AmtDemand] decimal(38,2),
    [StatusCode] varchar(10) NOT NULL,
    [VersionName] varchar(13) NOT NULL,
    [LoadDT] datetime2
);
GO

-- SalesHistory_Enh.ActualDemandWeekly (10 cols)
CREATE TABLE [SalesHistory_Enh].[ActualDemandWeekly] (
    [ItemSKU] varchar(8000),
    [WarehouseCode] varchar(8000),
    [CustomerGroupCode] varchar(8000),
    [FSCWeekFirst] date,
    [FSCWeekLast] date,
    [QtyDemand] decimal(38,0),
    [AmtDemand] decimal(38,2),
    [StatusCode] varchar(10) NOT NULL,
    [VersionName] varchar(13) NOT NULL,
    [LoadDT] datetime2
);
GO

-- SalesHistory_Enh.InvoiceDetailLineLevel (38 cols)
CREATE TABLE [SalesHistory_Enh].[InvoiceDetailLineLevel] (
    [InvoiceID] decimal(9,0) NOT NULL,
    [InvoiceExtended] varchar(8000),
    [OrderID] varchar(8000) NOT NULL,
    [ItemSequenceNum] decimal(7,0),
    [Customer] varchar(8000) NOT NULL,
    [ShipToCode] varchar(8000) NOT NULL,
    [AccountShipTo] varchar(8000),
    [ItemSKU] varchar(8000) NOT NULL,
    [WarehouseCode] varchar(8000) NOT NULL,
    [CustomerGroupCode] varchar(8000),
    [LeadTimeDaysNum] int,
    [QtyShipped] decimal(7,0) NOT NULL,
    [QtyOrdered] decimal(7,0) NOT NULL,
    [QtyBackordered] decimal(7,0) NOT NULL,
    [AmtInvoice] decimal(9,2) NOT NULL,
    [AmtNetSales] decimal(13,3),
    [AmtPrice] decimal(9,2) NOT NULL,
    [AmtStandardPrice] decimal(7,2),
    [AmtContractPrice] decimal(7,2),
    [AmtDiscount] decimal(9,2) NOT NULL,
    [AmtPriceAdjustment] decimal(9,2) NOT NULL,
    [AmtFreight] decimal(9,2) NOT NULL,
    [InvoiceDate] date,
    [OrderDate] date,
    [Request] date,
    [CurrentRequest] date,
    [CurrentPromise] date,
    [OriginalRequest] date,
    [OriginalPromise] date,
    [PromisedDelivery] date,
    [Delivery] date,
    [ActualDelivery] date,
    [OrderTypeCode] varchar(8000),
    [OrderType3Code] varchar(8000),
    [CreditCode] varchar(8000) NOT NULL,
    [ItemClassCode] varchar(8000) NOT NULL,
    [OrderItemStatusCode] varchar(8000),
    [LoadDT] datetime2
);
GO

-- SalesHistory_Enh.InvoiceWeekly (13 cols)
CREATE TABLE [SalesHistory_Enh].[InvoiceWeekly] (
    [AccountShipTo] varchar(8000),
    [ItemSKU] varchar(8000) NOT NULL,
    [WarehouseCode] varchar(8000) NOT NULL,
    [CustomerGroupCode] varchar(8000),
    [FSCWeekFirst] date,
    [FSCWeekLast] date,
    [QtyShipped] decimal(38,0),
    [AmtNetSales] decimal(38,3),
    [AmtInvoice] decimal(38,2),
    [AmtFreight] decimal(38,2),
    [InvoiceLines] int,
    [DistinctInvoices] int,
    [LoadDT] datetime2
);
GO

-- Staging_Wrk.DemandForecastSnapshotDaily (24 cols)
CREATE TABLE [Staging_Wrk].[DemandForecastSnapshotDaily] (
    [dfcItem] varchar(8000) NOT NULL,
    [dfcWarehouse] varchar(8000) NOT NULL,
    [dfcFiscalMonth] decimal(6,0) NOT NULL,
    [dfcMainPiece] varchar(8000) NOT NULL,
    [dfcCollectiveClass] varchar(8000) NOT NULL,
    [dfcResultantForecast] decimal(9,0),
    [dfcPromotionalLift] decimal(9,0),
    [dfcForcedForecast] decimal(9,0) NOT NULL,
    [dfcValidDemandMonths] decimal(3,0) NOT NULL,
    [dfcSnapshot] datetime2,
    [dfcPermComptQty] decimal(11,2),
    [dfcUsr25Text] varchar(8000),
    [dfcUsr32Text] varchar(8000),
    [dfcFCSTTypeCode] varchar(8000),
    [dfcDerivedFCSTID] varchar(8000),
    [dfcDerivedFCSTFctr] decimal(5,3),
    [dfcOrderFutureQty] decimal(9,0),
    [dfcMgmtCode] varchar(8000),
    [usra] varchar(8000),
    [dtea] datetime2,
    [usrc] varchar(8000),
    [dtec] datetime2,
    [DfcCustomerGroups] varchar(8000),
    [LoadDT] datetime2
);
GO

