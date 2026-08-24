-- =============================================================================
-- DataQuality.usp_RunForecastAccuracyDQ
-- Live T-SQL runtime for the Forecast Accuracy 3-gate DQ contract.
-- Target database: SupplyChain_Processing_Warehouse (DEV workspace only).
--
-- Persisted Fabric Warehouse runtime for the Forecast Accuracy DQ contract.
-- Gates: BRONZE_TECH (OBJECT/KEY/GRAIN/FRESHNESS),
--        GOLD_TECH (KEY/GRAIN/FRESHNESS + REFERENCE + INVARIANT),
--        BRONZE_GOLD (ForecastQty, CustomerGroupCoverage, ActualDemandQty, Naive SKIPPED).
-- Expected v1.7 shape: 111 checks (full-row duplicate checks retired;
-- Bronze FRESHNESS emits only for explicitly declared recency contracts).
--
-- Fabric Warehouse T-SQL constraints handled here (all verified live 2026-07-22):
--   * No table variables, no INSERT..EXEC  -> #temp only.
--   * INSERT real SELECT FROM crossdb is unsupported (distributed processing)
--     -> compute cross-DB metrics into scalar @vars, INSERT..VALUES into #results,
--        then bridge INSERT real SELECT FROM #results at the end.
--   * Cross-DB scalar assignment to @var works; dynamic cross-DB GROUP BY via
--     sp_executesql with OUTPUT params works (requires SET NOCOUNT ON in child).
--   * Cross-DB INFORMATION_SCHEMA scalar COUNT_BIG works for OBJECT existence,
--     but cannot feed SELECT..INTO (sysname distributed block).
--   * HASHBYTES('SHA2_256') reproduces the Python sha256(...).hexdigest()[:32]
--     DataCutId byte-for-byte (verified c46fa842.. and dfc4d443..).
--
-- Bounding rule (DQ_SYSTEM_STANDARD.md): every fact/large-source scan is limited
-- to the latest three fully completed UTC calendar months. No full-history scan.
--
-- @Persist defaults to 0 (dry-run: returns rows, no INSERT). Set 1 to persist
-- into DataQuality.DQForecastAccuracyGate.
-- =============================================================================
CREATE OR ALTER PROCEDURE [DataQuality].[usp_RunForecastAccuracyDQ]
    @AsOfDate       date = NULL,
    @PipelineRunId  varchar(128) = NULL,
    @DevTolerance   decimal(38,6) = 0.01,
    @FreshnessSLADays int = 1,
    @FreshnessLookbackDays int = 7,
    @ReconciliationTolerancePct decimal(38,6) = 0.05,
    @Persist        bit = 0,
    @EmitResults    bit = 1,
    @DQRunIdOutput  varchar(64) = NULL OUTPUT,
    @DecisionOutput varchar(32) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- -----------------------------------------------------------------------
    -- Environment guard. The SP loses the Python REST workspace guard, so it
    -- asserts the database context by name instead (ADR-011 section 6).
    -- -----------------------------------------------------------------------
    IF DB_NAME() <> N'SupplyChain_Processing_Warehouse'
        THROW 50001, 'usp_RunForecastAccuracyDQ must run in SupplyChain_Processing_Warehouse.', 1;

    -- -----------------------------------------------------------------------
    -- Run identity + rule version
    -- -----------------------------------------------------------------------
    DECLARE @DQRunId     varchar(64)   = CAST(NEWID() AS varchar(64));
    DECLARE @DQRunAtUTC  datetime2(6)  = SYSUTCDATETIME();
    DECLARE @MartCode    varchar(64)   = 'forecast_accuracy';
    DECLARE @RuleVersion varchar(32)   = '1.7.0-dev';

    -- -----------------------------------------------------------------------
    -- Bounded window: latest three fully completed UTC calendar months.
    -- -----------------------------------------------------------------------
    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS date);
    DECLARE @WindowEndExclusive date = DATEFROMPARTS(YEAR(@AsOfDate), MONTH(@AsOfDate), 1);
    DECLARE @WindowStart        date = DATEADD(MONTH, -3, @WindowEndExclusive);
    DECLARE @WindowEnd          date = DATEADD(DAY, -1, @WindowEndExclusive);
    DECLARE @LastCompletedMonth date = DATEADD(MONTH, -1, @WindowEndExclusive);
    DECLARE @FreshnessThreshold date = DATEADD(DAY, -@FreshnessSLADays, @AsOfDate);
    DECLARE @FreshnessTailStart date = DATEADD(DAY, -@FreshnessLookbackDays, @AsOfDate);

    -- Forecast fiscal window (mirrors forecast_fiscal_window in the oracle).
    DECLARE @LowerAnchor date = DATEADD(MONTH, -6, @WindowEndExclusive);
    DECLARE @UpperAnchor date = DATEADD(MONTH,  6, @WindowEndExclusive);
    DECLARE @ForecastFiscalStart date = DATEADD(MONTH, -36, DATEFROMPARTS(YEAR(@LowerAnchor), 1, 1));
    DECLARE @ForecastFiscalEnd   date = DATEADD(MONTH,  12, DATEFROMPARTS(YEAR(@UpperAnchor), 1, 1));

    -- String forms for embedding into dynamic predicates (controlled values).
    DECLARE @WS varchar(10) = CONVERT(varchar(10), @WindowStart, 23);
    DECLARE @WE varchar(10) = CONVERT(varchar(10), @WindowEndExclusive, 23);
    DECLARE @FFS varchar(10) = CONVERT(varchar(10), @ForecastFiscalStart, 23);
    DECLARE @FFE varchar(10) = CONVERT(varchar(10), @ForecastFiscalEnd, 23);

    -- -----------------------------------------------------------------------
    -- Result accumulator. Mirrors DQForecastAccuracyGate 33 columns + OrderSeq.
    -- -----------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#results') IS NOT NULL DROP TABLE #results;
    CREATE TABLE #results
    (
        OrderSeq                int IDENTITY(1,1) NOT NULL,
        DQRunId                 varchar(64) NOT NULL,
        DQRunAtUTC              datetime2(6) NOT NULL,
        LoadDT                  datetime2(6) NOT NULL,
        MartCode                varchar(64) NOT NULL,
        PipelineRunId           varchar(128) NULL,
        DataCutId               varchar(256) NULL,
        RuleVersion             varchar(32) NOT NULL,
        GateCode                varchar(32) NOT NULL,
        CheckType               varchar(32) NOT NULL,
        Tier                    int NOT NULL,
        RuleCode                varchar(256) NOT NULL,
        ParentRuleCode          varchar(256) NULL,
        ObjectOrFlow            varchar(256) NOT NULL,
        IsBlocking              bit NOT NULL,
        Status                  varchar(32) NOT NULL,
        SourceObject            varchar(512) NULL,
        TargetObject            varchar(512) NULL,
        WindowStart             date NULL,
        WindowEnd               date NULL,
        SourceCount             bigint NULL,
        TargetCount             bigint NULL,
        SourceDistinctKeyCount  bigint NULL,
        TargetDistinctKeyCount  bigint NULL,
        SourceMeasure           decimal(38,6) NULL,
        TargetMeasure           decimal(38,6) NULL,
        Difference              decimal(38,6) NULL,
        Tolerance               decimal(38,6) NULL,
        MissingInGold           bigint NULL,
        ExtraInGold             bigint NULL,
        ObservedValue           varchar(4000) NULL,
        ExpectedValue           varchar(4000) NULL,
        Evidence                varchar(8000) NULL,
        ErrorMessage            varchar(4000) NULL
    );

    -- =======================================================================
    -- GATE 1: BRONZE_TECH  (21 DA-defined contracts)
    -- =======================================================================
    IF OBJECT_ID('tempdb..#bronze') IS NOT NULL DROP TABLE #bronze;
    CREATE TABLE #bronze
    (
        Seq       int IDENTITY(1,1) NOT NULL,
        Sch       varchar(128) NOT NULL,
        Tbl       varchar(128) NOT NULL,
        PkCols    varchar(512) NOT NULL,   -- bracketed comma list
        NullPred  varchar(512) NOT NULL,   -- OR of [col] IS NULL
        PkJson    varchar(512) NOT NULL,   -- ["col1","col2"]
        DateCol   varchar(128) NULL,       -- bounding/freshness date column or NULL
        IsLarge   bit NOT NULL DEFAULT 0
    );

    INSERT INTO #bronze (Sch, Tbl, PkCols, NullPred, PkJson, DateCol, IsLarge) VALUES
    ('CustomerOrders_AFI','WarehouseMaster','[Warehouse], [LocationID]','[Warehouse] IS NULL OR [LocationID] IS NULL','["Warehouse","LocationID"]',NULL,0),
    ('Customers','AccountMaster','[cmaCustomerNumber]','[cmaCustomerNumber] IS NULL','["cmaCustomerNumber"]',NULL,0),
    ('Customers','ShippingLocations','[cslCustomerNumber], [cslShiptoNumber]','[cslCustomerNumber] IS NULL OR [cslShiptoNumber] IS NULL','["cslCustomerNumber","cslShiptoNumber"]',NULL,0),
    ('ItemMaster_AFI','AITMCLS','[ITMCL]','[ITMCL] IS NULL','["ITMCL"]',NULL,0),
    ('ItemMaster_AFI','ITBEXT','[ITNBR], [House]','[ITNBR] IS NULL OR [House] IS NULL','["ITNBR","House"]',NULL,0),
    ('ItemMaster_AFI','ITMEXT','[ITNBR]','[ITNBR] IS NULL','["ITNBR"]',NULL,0),
    ('MasterData_DW','DimDate','[DateID]','[DateID] IS NULL','["DateID"]',NULL,0),
    ('MasterData_DW','DimItemMaster','[ItemSKU]','[ItemSKU] IS NULL','["ItemSKU"]',NULL,0),
    ('MasterData_ProductKnowledge','Item_ENV','[ienItemNumber], [ienEnvironmentCode]','[ienItemNumber] IS NULL OR [ienEnvironmentCode] IS NULL','["ienItemNumber","ienEnvironmentCode"]',NULL,0),
    ('Purchasing_AFI','VendorMaster','[VendorNumber]','[VendorNumber] IS NULL','["VendorNumber"]',NULL,0),
    ('SalesHistory_AFI','InvoiceDetail','[InvoiceNumber], [OrderNumber], [ItemSKU], [ItemSequence]','[InvoiceNumber] IS NULL OR [OrderNumber] IS NULL OR [ItemSKU] IS NULL OR [ItemSequence] IS NULL','["InvoiceNumber","OrderNumber","ItemSKU","ItemSequence"]','InvoiceDate',1),
    ('SalesHistory_AFI','InvoiceHeader','[InvoiceNumber], [OrderNumber]','[InvoiceNumber] IS NULL OR [OrderNumber] IS NULL','["InvoiceNumber","OrderNumber"]','InvoiceDate',1),
    ('SupplyChain_Enh','DemandForecastSnapshotDaily','[dfcItem], [dfcWarehouse], [dfcFiscalMonth], [dfcSnapshot], [DfcCustomerGroups]','[dfcItem] IS NULL OR [dfcWarehouse] IS NULL OR [dfcFiscalMonth] IS NULL OR [dfcSnapshot] IS NULL OR [DfcCustomerGroups] IS NULL','["dfcItem","dfcWarehouse","dfcFiscalMonth","dfcSnapshot","DfcCustomerGroups"]','dfcSnapshot',1),
    ('Wholesale_Codis_AFI','AAORDTYP','[OTCODE]','[OTCODE] IS NULL','["OTCODE"]',NULL,0),
    ('Wholesale_Codis_AFI','AshleyWarehouseMaster','[wmaWarehouse]','[wmaWarehouse] IS NULL','["wmaWarehouse"]',NULL,0),
    ('Wholesale_Codis_AFI','COMAST','[ORDNO]','[ORDNO] IS NULL','["ORDNO"]',NULL,0),
    ('Wholesale_Codis_AFI','EXTORD','[XORDNO]','[XORDNO] IS NULL','["XORDNO"]',NULL,0),
    ('Wholesale_Codis_AFI','EXTORIT','[IORD], [ISEQ]','[IORD] IS NULL OR [ISEQ] IS NULL','["IORD","ISEQ"]',NULL,0),
    ('Wholesale_Codis_AFI','codatan','[ORDNO], [ITMSQ]','[ORDNO] IS NULL OR [ITMSQ] IS NULL','["ORDNO","ITMSQ"]',NULL,0),
    ('Wholesale_ProductSourcing','NonPkItems','[npkItemNumber]','[npkItemNumber] IS NULL','["npkItemNumber"]',NULL,0),
    ('Wholesale_ProductSourcing_AFI','CustomerGrouping','[CustomerNumber]','[CustomerNumber] IS NULL','["CustomerNumber"]',NULL,0);

    DECLARE @cnt int = (SELECT COUNT(*) FROM #bronze);
    DECLARE @i int = 1;

    WHILE @i <= @cnt
    BEGIN
        DECLARE @sch varchar(128), @tbl varchar(128), @pk varchar(512),
                @np varchar(512), @pkj varchar(512), @dc varchar(128), @large bit;
        SELECT @sch = Sch, @tbl = Tbl, @pk = PkCols, @np = NullPred,
               @pkj = PkJson, @dc = DateCol, @large = IsLarge
        FROM #bronze WHERE Seq = @i;

        DECLARE @short varchar(256) = @sch + '.' + @tbl;
        DECLARE @full  varchar(512) = 'Enterprise_Lakehouse.' + @short;

        -- OBJECT existence (cross-db INFORMATION_SCHEMA scalar)
        DECLARE @exists bigint = 0;
        DECLARE @estmt nvarchar(max) = N'SET NOCOUNT ON; SELECT @o = COUNT_BIG(*) FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = @s AND TABLE_NAME = @t;';
        EXEC sp_executesql @estmt, N'@s varchar(128), @t varchar(128), @o bigint OUTPUT',
             @s = @sch, @t = @tbl, @o = @exists OUTPUT;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,DataCutId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
            WindowStart,WindowEnd,ObservedValue,ExpectedValue,Evidence)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,NULL,@RuleVersion,
            'BRONZE_TECH','OBJECT',1,'BRONZE_TECH.'+@short+'.OBJECT',@short,1,
            CASE WHEN @exists > 0 THEN 'PASS' ELSE 'FAIL' END, @full,
            @WindowStart,@WindowEnd,
            CASE WHEN @exists > 0 THEN 'EXISTS' ELSE 'MISSING' END,'EXISTS',
            '{"metadata_source":"Enterprise_Lakehouse.INFORMATION_SCHEMA.TABLES"}');

        IF @exists = 0
        BEGIN
            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
                WindowStart,WindowEnd,ErrorMessage)
            SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'BRONZE_TECH',ct,1,'BRONZE_TECH.'+@short+'.'+ct,@short,
                CASE WHEN ct = 'FRESHNESS' THEN 0 ELSE 1 END,'ERROR',@full,
                @WindowStart,@WindowEnd,'Contracted Bronze object is missing'
            FROM (VALUES ('KEY'),('GRAIN'),('FRESHNESS')) v(ct)
            WHERE ct <> 'FRESHNESS' OR @dc IS NOT NULL;
            SET @i += 1;
            CONTINUE;
        END

        -- KEY / GRAIN plus an optional declared Bronze freshness observation.
        DECLARE @sc bigint, @nk bigint, @dr bigint, @mx date,
                @fmx date, @fcol varchar(128), @fexists bigint,
                @poolFound bit;
        DECLARE @scope varchar(64) = CASE WHEN @dc IS NULL THEN 'full_reference_table' ELSE 'three_completed_months' END;
        DECLARE @where nvarchar(400) = N'';
        DECLARE @dateGrp nvarchar(200) = N'';
        DECLARE @dateMax nvarchar(100) = N'CAST(NULL AS date)';
        IF @dc IS NOT NULL
        BEGIN
            SET @where = N' WHERE CAST([' + @dc + N'] AS date) >= ''' + @WS + N''' AND CAST([' + @dc + N'] AS date) < ''' + @WE + N'''';
            SET @dateGrp = N', MAX(CAST([' + @dc + N'] AS date)) AS grp_max_date';
            SET @dateMax = N'MAX(grp_max_date)';
        END

        DECLARE @gstmt nvarchar(max) = N'SET NOCOUNT ON;
        WITH grouped AS (
            SELECT ' + @pk + N', COUNT_BIG(*) AS row_count' + @dateGrp + N'
            FROM [Enterprise_Lakehouse].[' + @sch + N'].[' + @tbl + N']' + @where + N'
            GROUP BY ' + @pk + N'
        )
        SELECT @sc_o = COALESCE(SUM(row_count),0),
               @nk_o = COALESCE(SUM(CASE WHEN ' + @np + N' THEN row_count ELSE 0 END),0),
               @dr_o = COALESCE(SUM(CASE WHEN row_count > 1 THEN row_count - 1 ELSE 0 END),0),
               @mx_o = ' + @dateMax + N'
        FROM grouped;';

        BEGIN TRY
            SET @sc = NULL; SET @nk = NULL; SET @dr = NULL; SET @mx = NULL;
            EXEC sp_executesql @gstmt,
                 N'@sc_o bigint OUTPUT, @nk_o bigint OUTPUT, @dr_o bigint OUTPUT, @mx_o date OUTPUT',
                 @sc_o = @sc OUTPUT, @nk_o = @nk OUTPUT, @dr_o = @dr OUTPUT, @mx_o = @mx OUTPUT;
            SET @sc = COALESCE(@sc,0); SET @nk = COALESCE(@nk,0); SET @dr = COALESCE(@dr,0);

            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
                WindowStart,WindowEnd,SourceCount,ObservedValue,ExpectedValue,Evidence)
            VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'BRONZE_TECH','KEY',1,'BRONZE_TECH.'+@short+'.KEY',@short,1,
                CASE WHEN @nk = 0 THEN 'PASS' ELSE 'FAIL' END,@full,
                @WindowStart,@WindowEnd,@sc,CAST(@nk AS varchar(20)),'0 null-key rows',
                '{"key":'+@pkj+',"scope":"'+@scope+'"}');

            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
                WindowStart,WindowEnd,SourceCount,ObservedValue,ExpectedValue,Evidence)
            VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'BRONZE_TECH','GRAIN',1,'BRONZE_TECH.'+@short+'.GRAIN',@short,1,
                CASE WHEN @dr = 0 THEN 'PASS' ELSE 'FAIL' END,@full,
                @WindowStart,@WindowEnd,@sc,CAST(@dr AS varchar(20)),'0 duplicate rows',
                '{"grain":'+@pkj+',"scope":"'+@scope+'"}');

            -- Bronze freshness is one simple upstream observation. Emit it only
            -- for explicitly declared timestamp contracts; references emit no
            -- synthetic FRESHNESS/N/A result.
            IF @dc IS NOT NULL
            BEGIN
            -- A Bronze contract declares exactly one eligible recency column.
            -- Calendar and lifecycle columns cannot be substituted.
            SET @fmx = NULL; SET @poolFound = 0; SET @fcol = @dc;
            IF LOWER(@fcol) IN ('dtea','dtec','loaddt','goldloaddt','dfcsnapshot','invoicedate','snapshot')
            BEGIN
                SET @fexists = 0;
                SET @estmt = N'SET NOCOUNT ON; SELECT @o = COUNT_BIG(*) FROM Enterprise_Lakehouse.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=@s AND TABLE_NAME=@t AND LOWER(COLUMN_NAME)=LOWER(@c) AND DATA_TYPE IN (''date'',''datetime'',''datetime2'',''smalldatetime'',''datetimeoffset'');';
                EXEC sp_executesql @estmt, N'@s varchar(128),@t varchar(128),@c varchar(128),@o bigint OUTPUT',
                    @s=@sch,@t=@tbl,@c=@fcol,@o=@fexists OUTPUT;
                IF @fexists > 0
                BEGIN
                    SET @poolFound = 1;
                    DECLARE @fstmt nvarchar(max) = N'SET NOCOUNT ON; SELECT @o = MAX(CASE WHEN CAST(['+@fcol+N'] AS date) <= '''+CONVERT(varchar(10),@AsOfDate,23)+N''' THEN CAST(['+@fcol+N'] AS date) END) FROM Enterprise_Lakehouse.['+@sch+N'].['+@tbl+N']' +
                        CASE WHEN @large=1 AND @dc IS NOT NULL THEN N' WHERE CAST(['+@dc+N'] AS date) >= '''+CONVERT(varchar(10),@FreshnessTailStart,23)+N'''' ELSE N'' END + N';';
                    DECLARE @fdate date = NULL;
                    EXEC sp_executesql @fstmt, N'@o date OUTPUT', @o=@fdate OUTPUT;
                    IF @fdate IS NOT NULL AND (@fmx IS NULL OR @fdate > @fmx) SET @fmx=@fdate;
                END
            END
            IF @poolFound = 0
                INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                    GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
                    WindowStart,WindowEnd,ExpectedValue,Evidence)
                VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                    'BRONZE_TECH','FRESHNESS',1,'BRONZE_TECH.'+@short+'.FRESHNESS',@short,0,'ERROR',@full,
                    @WindowStart,@WindowEnd,'Declared freshness column '+@dc+' must be in the recency pool',
                    '{"freshness_scope":"upstream_observation","ownership":"upstream","reporting_severity":"WARN","declared_freshness_column":"'+@dc+'","reason":"no recency pool columns found"}');
            ELSE
                INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                    GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
                    WindowStart,WindowEnd,SourceCount,ObservedValue,ExpectedValue,Evidence)
                VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                    'BRONZE_TECH','FRESHNESS',1,'BRONZE_TECH.'+@short+'.FRESHNESS',@short,
                    0,
                    CASE WHEN @fmx IS NOT NULL AND @fmx >= @FreshnessThreshold THEN 'PASS' ELSE 'FAIL' END,@full,
                    @WindowStart,@WindowEnd,@sc,CASE WHEN @fmx IS NULL THEN NULL ELSE CONVERT(varchar(10),@fmx,23) END,
                    '>= '+CONVERT(varchar(10),@FreshnessThreshold,23)+' (SLA '+CAST(@FreshnessSLADays AS varchar(10))+'d)',
                    '{"freshness_scope":"upstream_observation","ownership":"upstream","reporting_severity":"'+CASE WHEN @fmx IS NOT NULL AND @fmx >= @FreshnessThreshold THEN 'INFO' ELSE 'WARN' END+'","declared_freshness_column":"'+@dc+'","pool_based":true,"tail_bounded":'+CASE WHEN @large=1 AND @dc IS NOT NULL THEN 'true' ELSE 'false' END+'}');
            END

        END TRY
        BEGIN CATCH
            DECLARE @berr varchar(4000) = ERROR_MESSAGE();
            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,
                WindowStart,WindowEnd,ErrorMessage)
            SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'BRONZE_TECH',ct,1,'BRONZE_TECH.'+@short+'.'+ct,@short,
                CASE WHEN ct = 'FRESHNESS' THEN 0 ELSE 1 END,'ERROR',@full,
                @WindowStart,@WindowEnd,@berr
            FROM (VALUES ('KEY'),('GRAIN'),('FRESHNESS')) v(ct)
            WHERE ct <> 'FRESHNESS' OR @dc IS NOT NULL;
        END CATCH

        SET @i += 1;
    END

    -- =======================================================================
    -- GATE 2: GOLD_TECH  (7 targets: KEY/GRAIN/FRESHNESS)
    -- =======================================================================
    IF OBJECT_ID('tempdb..#gold') IS NOT NULL DROP TABLE #gold;
    CREATE TABLE #gold
    (
        Seq      int IDENTITY(1,1) NOT NULL,
        Sch      varchar(128) NOT NULL,
        Tbl      varchar(128) NOT NULL,
        KeyCols  varchar(512) NOT NULL,
        NullPred varchar(512) NOT NULL,
        KeyJson  varchar(512) NOT NULL,
        Pred     varchar(1000) NOT NULL,   -- window predicate (dates baked in)
        Scope    varchar(64) NOT NULL,
        FreshnessMode varchar(32) NOT NULL
    );

    DECLARE @mixedPred varchar(1000) =
        '((StatusCode = ''Forecast'' AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName, 3, 7), ''.'', ''-'') + ''-01'') >= ''' + @WS + ''' AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName, 3, 7), ''.'', ''-'') + ''-01'') < ''' + @WE + ''') OR ((StatusCode <> ''Forecast'' OR StatusCode IS NULL) AND FSCMonthLast >= ''' + @WS + ''' AND FSCMonthLast < ''' + @WE + '''))';
    DECLARE @snapPred varchar(1000) = 'Snapshot >= ''' + @WS + ''' AND Snapshot < ''' + @WE + '''';

    INSERT INTO #gold (Sch,Tbl,KeyCols,NullPred,KeyJson,Pred,Scope,FreshnessMode) VALUES
    ('Shared_DW','DimCalendar','[Date]','[Date] IS NULL','["Date"]','1 = 1','current_dimension','PIPELINE_HEARTBEAT'),
    ('Shared_DW','DimProduct','[ItemSKU]','[ItemSKU] IS NULL','["ItemSKU"]','1 = 1','current_dimension','PIPELINE_HEARTBEAT'),
    ('Shared_DW','DimWarehouse','[WarehouseCode]','[WarehouseCode] IS NULL','["WarehouseCode"]','1 = 1','current_dimension','PIPELINE_HEARTBEAT'),
    ('ForecastAccuracy_DW','DimCustomerGrouping','[Customer]','[Customer] IS NULL','["Customer"]','1 = 1','current_dimension','PIPELINE_HEARTBEAT'),
    ('ForecastAccuracy_DW','DimForecastHorizon','[HorizonCode]','[HorizonCode] IS NULL','["HorizonCode"]','1 = 1','current_dimension','PIPELINE_HEARTBEAT'),
    ('ForecastAccuracy_DW','FactForecastActual','[ItemSKU], [WarehouseCode], [CustomerGroupCode], [FSCMonthLast], [HorizonCode], [VersionName], [StatusCode]','[ItemSKU] IS NULL OR [WarehouseCode] IS NULL OR [CustomerGroupCode] IS NULL OR [FSCMonthLast] IS NULL OR [HorizonCode] IS NULL OR [VersionName] IS NULL OR [StatusCode] IS NULL','["ItemSKU","WarehouseCode","CustomerGroupCode","FSCMonthLast","HorizonCode","VersionName","StatusCode"]',@mixedPred,'three_completed_months','RECENCY_POOL'),
    ('ForecastAccuracy_DW','FactForecastKpi','[ItemSKU], [WarehouseCode], [FSCMonthLast], [HorizonCode], [Snapshot]','[ItemSKU] IS NULL OR [WarehouseCode] IS NULL OR [FSCMonthLast] IS NULL OR [HorizonCode] IS NULL OR [Snapshot] IS NULL','["ItemSKU","WarehouseCode","FSCMonthLast","HorizonCode","Snapshot"]',@snapPred,'three_completed_months','RECENCY_POOL');

    DECLARE @gcnt int = (SELECT COUNT(*) FROM #gold);
    DECLARE @gi int = 1;
    WHILE @gi <= @gcnt
    BEGIN
        DECLARE @gsch varchar(128), @gtbl varchar(128), @gkeys varchar(512),
                @gnp varchar(512), @gkj varchar(512), @gpred varchar(1000), @gscope varchar(64), @gfm varchar(32);
        SELECT @gsch=Sch,@gtbl=Tbl,@gkeys=KeyCols,@gnp=NullPred,@gkj=KeyJson,@gpred=Pred,@gscope=Scope,@gfm=FreshnessMode
        FROM #gold WHERE Seq = @gi;

        DECLARE @gobj  varchar(256) = @gsch + '.' + @gtbl;
        DECLARE @gfull varchar(512) = 'SupplyChain_Gold_Warehouse.' + @gobj;
        DECLARE @tdPrimaryKey varchar(700);
        SELECT @tdPrimaryKey = PrimaryKey
        FROM ETL_Framework.DW_Developer.TableDictionary
        WHERE DatabaseName = 'SupplyChain_Gold_Warehouse'
          AND SchemaName = @gsch
          AND TableName = @gtbl;

        IF @tdPrimaryKey IS NULL
           OR LOWER(REPLACE(REPLACE(REPLACE(@tdPrimaryKey,'[',''),']',''),' ',''))
              <> LOWER(REPLACE(REPLACE(REPLACE(@gkeys,'[',''),']',''),' ',''))
        BEGIN
            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
                WindowStart,WindowEnd,ObservedValue,ExpectedValue,Evidence,ErrorMessage)
            SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'GOLD_TECH',ct,1,'GOLD_TECH.'+@gobj+'.'+ct,@gobj,1,'ERROR',@gfull,
                @WindowStart,@WindowEnd,@gkeys,ISNULL(@tdPrimaryKey,'<missing>'),
                '{"registry":"ETL_Framework.DW_Developer.TableDictionary","declared_key":"'+REPLACE(@gkeys,'"','\\"')+'","governed_key":"'+REPLACE(ISNULL(@tdPrimaryKey,'<missing>'),'"','\\"')+'"}',
                'Runner Gold key differs from governed TableDictionary.PrimaryKey'
            FROM (VALUES ('KEY'),('GRAIN')) v(ct);
            SET @gi += 1;
            CONTINUE;
        END
        DECLARE @gtc bigint, @gnk bigint, @gdr bigint, @gminload varchar(40), @gmaxload varchar(40), @gfreshload varchar(40);

        DECLARE @sumStmt nvarchar(max) = N'SET NOCOUNT ON;
        SELECT @tc_o = COUNT_BIG(*),
               @nk_o = COALESCE(SUM(CASE WHEN ' + @gnp + N' THEN 1 ELSE 0 END),0),
               @mn_o = CONVERT(varchar(33), MIN(LoadDT), 126),
               @mx_o = CONVERT(varchar(33), MAX(LoadDT), 126)
        FROM SupplyChain_Gold_Warehouse.[' + @gsch + N'].[' + @gtbl + N']
        WHERE ' + @gpred + N';';

        DECLARE @dupStmt nvarchar(max) = N'SET NOCOUNT ON;
        WITH d AS (
            SELECT COUNT_BIG(*) AS rc
            FROM SupplyChain_Gold_Warehouse.[' + @gsch + N'].[' + @gtbl + N']
            WHERE ' + @gpred + N'
            GROUP BY ' + @gkeys + N'
            HAVING COUNT_BIG(*) > 1
        )
        SELECT @dr_o = COALESCE(SUM(rc - 1),0) FROM d;';
        -- Operational freshness measures the latest target load independently of
        -- the three-month business-data predicate used by fact technical checks.
        DECLARE @freshStmt nvarchar(max) = N'SET NOCOUNT ON;
        SELECT @o = CONVERT(varchar(33), MAX(CASE WHEN CAST(LoadDT AS date) <= ''' + CONVERT(varchar(10),@AsOfDate,23) + N''' THEN LoadDT END), 126)
        FROM SupplyChain_Gold_Warehouse.[' + @gsch + N'].[' + @gtbl + N'];';

        BEGIN TRY
            SET @gtc=NULL; SET @gnk=NULL; SET @gdr=NULL; SET @gminload=NULL; SET @gmaxload=NULL; SET @gfreshload=NULL;
            EXEC sp_executesql @sumStmt,
                 N'@tc_o bigint OUTPUT, @nk_o bigint OUTPUT, @mn_o varchar(40) OUTPUT, @mx_o varchar(40) OUTPUT',
                 @tc_o=@gtc OUTPUT, @nk_o=@gnk OUTPUT, @mn_o=@gminload OUTPUT, @mx_o=@gmaxload OUTPUT;
            EXEC sp_executesql @dupStmt, N'@dr_o bigint OUTPUT', @dr_o=@gdr OUTPUT;
            EXEC sp_executesql @freshStmt, N'@o varchar(40) OUTPUT', @o=@gfreshload OUTPUT;
            SET @gtc=COALESCE(@gtc,0); SET @gnk=COALESCE(@gnk,0); SET @gdr=COALESCE(@gdr,0);

            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
                WindowStart,WindowEnd,TargetCount,ObservedValue,ExpectedValue,Evidence)
            VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'GOLD_TECH','KEY',1,'GOLD_TECH.'+@gobj+'.KEY',@gobj,1,
                CASE WHEN @gnk=0 THEN 'PASS' ELSE 'FAIL' END,@gfull,
                @WindowStart,@WindowEnd,@gtc,CAST(@gnk AS varchar(20)),'0 null-key rows',
                '{"key":'+@gkj+',"scope":"'+@gscope+'"}');

            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
                WindowStart,WindowEnd,TargetCount,ObservedValue,ExpectedValue,Evidence)
            VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'GOLD_TECH','GRAIN',1,'GOLD_TECH.'+@gobj+'.GRAIN',@gobj,1,
                CASE WHEN @gdr=0 THEN 'PASS' ELSE 'FAIL' END,@gfull,
                @WindowStart,@WindowEnd,@gtc,CAST(@gdr AS varchar(20)),'0 duplicate rows',
                '{"key":'+@gkj+',"scope":"'+@gscope+'"}');

            IF @gfm = 'PIPELINE_HEARTBEAT'
            BEGIN
                DECLARE @heartbeat datetime2(6);
                SELECT @heartbeat = MAX([DateTime])
                FROM ETL_Framework.DW_Developer.AuditLog
                WHERE [Command] = 'Process Complete'
                  AND ([Description] = 'usp_RefreshCuratedTableFromView: ' + @gfull
                    OR [Description] = 'usp_UpdateCuratedTableFromView_DateRange: ' + @gfull);

                INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                    GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
                    WindowStart,WindowEnd,TargetCount,ObservedValue,ExpectedValue,Evidence)
                VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                    'GOLD_TECH','FRESHNESS',1,'GOLD_TECH.'+@gobj+'.FRESHNESS',@gobj,1,
                    CASE WHEN CAST(@heartbeat AS date) >= @FreshnessThreshold THEN 'PASS' ELSE 'FAIL' END,@gfull,
                    @WindowStart,@WindowEnd,@gtc,CONVERT(varchar(33),@heartbeat,126),
                    'successful target refresh on or after '+CONVERT(varchar(10),@FreshnessThreshold,23),
                    '{"freshness_mode":"PIPELINE_HEARTBEAT","audit_source":"ETL_Framework.DW_Developer.AuditLog","claim":"target refresh completed; row-level source-to-target lag is not asserted"}');
            END
            ELSE
                INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                    GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
                    WindowStart,WindowEnd,TargetCount,ObservedValue,ExpectedValue,Evidence)
                VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                    'GOLD_TECH','FRESHNESS',1,'GOLD_TECH.'+@gobj+'.FRESHNESS',@gobj,1,
                    CASE WHEN TRY_CONVERT(date,@gfreshload) >= @FreshnessThreshold THEN 'PASS' ELSE 'FAIL' END,@gfull,
                    @WindowStart,@WindowEnd,@gtc,@gfreshload,
                    '>= '+CONVERT(varchar(10),@FreshnessThreshold,23)+' (SLA '+CAST(@FreshnessSLADays AS varchar(10))+'d)',
                    '{"freshness_mode":"RECENCY_POOL","technical_window_max_load_dt":'+ISNULL('"'+@gmaxload+'"','null')+',"operational_max_load_dt":'+ISNULL('"'+@gfreshload+'"','null')+'}');
        END TRY
        BEGIN CATCH
            DECLARE @gerr varchar(4000) = ERROR_MESSAGE();
            INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
                GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
                WindowStart,WindowEnd,ErrorMessage)
            SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
                'GOLD_TECH',ct,1,'GOLD_TECH.'+@gobj+'.'+ct,@gobj,
                 1,'ERROR',@gfull,
                @WindowStart,@WindowEnd,@gerr
            FROM (VALUES ('KEY'),('GRAIN'),('FRESHNESS')) v(ct);
        END CATCH
        SET @gi += 1;
    END

    -- =======================================================================
    -- GATE 2: GOLD_TECH REFERENCE (FactForecastActual x5, FactForecastKpi x4)
    -- =======================================================================
    BEGIN TRY
        DECLARE @amp int, @amw int, @amc int, @amcal int, @amh int;
        DECLARE @refActual nvarchar(max) = N'SET NOCOUNT ON;
        SELECT
            @p_o = COALESCE(SUM(CASE WHEN P.ItemSKU IS NULL THEN 1 ELSE 0 END),0),
            @w_o = COALESCE(SUM(CASE WHEN W.WarehouseCode IS NULL THEN 1 ELSE 0 END),0),
            @c_o = COALESCE(SUM(CASE WHEN F.CustomerGroupCode IS NOT NULL AND TRIM(F.CustomerGroupCode) <> '''' AND C.CustomerGroupCode IS NULL THEN 1 ELSE 0 END),0),
            @cal_o = COALESCE(SUM(CASE WHEN D.Date IS NULL THEN 1 ELSE 0 END),0),
            @h_o = COALESCE(SUM(CASE WHEN F.StatusCode = ''Forecast'' AND H.HorizonCode IS NULL THEN 1 ELSE 0 END),0)
        FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual AS F
        LEFT JOIN (SELECT DISTINCT ItemSKU FROM SupplyChain_Gold_Warehouse.Shared_DW.DimProduct) AS P ON P.ItemSKU = F.ItemSKU COLLATE Latin1_General_100_BIN2_UTF8
        LEFT JOIN (SELECT DISTINCT WarehouseCode FROM SupplyChain_Gold_Warehouse.Shared_DW.DimWarehouse) AS W ON W.WarehouseCode = F.WarehouseCode COLLATE Latin1_General_100_BIN2_UTF8
        LEFT JOIN (SELECT DISTINCT CustomerGroupCode FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping) AS C ON C.CustomerGroupCode = F.CustomerGroupCode COLLATE Latin1_General_100_BIN2_UTF8
        LEFT JOIN (SELECT DISTINCT Date FROM SupplyChain_Gold_Warehouse.Shared_DW.DimCalendar) AS D ON D.Date = F.FSCMonthLast
        LEFT JOIN (SELECT DISTINCT HorizonCode FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimForecastHorizon) AS H ON H.HorizonCode = F.HorizonCode COLLATE Latin1_General_100_BIN2_UTF8
        WHERE ' + @mixedPred + N';';

        EXEC sp_executesql @refActual,
             N'@p_o int OUTPUT,@w_o int OUTPUT,@c_o int OUTPUT,@cal_o int OUTPUT,@h_o int OUTPUT',
             @p_o=@amp OUTPUT,@w_o=@amw OUTPUT,@c_o=@amc OUTPUT,@cal_o=@amcal OUTPUT,@h_o=@amh OUTPUT;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
            WindowStart,WindowEnd,ObservedValue,ExpectedValue,Evidence)
        SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','REFERENCE',1,'GOLD_TECH.FactForecastActual.'+ref+'.REFERENCE','FactForecastActual.'+ref,1,
            CASE WHEN missing=0 THEN 'PASS' ELSE 'FAIL' END,
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',
            @WindowStart,@WindowEnd,CAST(missing AS varchar(20)),'0 unmatched fact rows',
            '{"reference":"'+ref+'","scope":"three_completed_months"}'
        FROM (VALUES ('product',@amp),('warehouse',@amw),('customer_group',@amc),('calendar',@amcal),('horizon',@amh)) v(ref,missing);
    END TRY
    BEGIN CATCH
        DECLARE @refErrA varchar(4000) = ERROR_MESSAGE();
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,WindowStart,WindowEnd,ErrorMessage)
        SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','REFERENCE',1,'GOLD_TECH.FactForecastActual.'+ref+'.REFERENCE','FactForecastActual.'+ref,1,'ERROR',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',@WindowStart,@WindowEnd,@refErrA
        FROM (VALUES ('product'),('warehouse'),('customer_group'),('calendar'),('horizon')) v(ref);
    END CATCH

    BEGIN TRY
        DECLARE @kp int, @kw int, @kcal int, @kh int;
        DECLARE @refKpi nvarchar(max) = N'SET NOCOUNT ON;
        SELECT
            @p_o = COALESCE(SUM(CASE WHEN P.ItemSKU IS NULL THEN 1 ELSE 0 END),0),
            @w_o = COALESCE(SUM(CASE WHEN W.WarehouseCode IS NULL THEN 1 ELSE 0 END),0),
            @cal_o = COALESCE(SUM(CASE WHEN D.Date IS NULL THEN 1 ELSE 0 END),0),
            @h_o = COALESCE(SUM(CASE WHEN H.HorizonCode IS NULL THEN 1 ELSE 0 END),0)
        FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi AS F
        LEFT JOIN (SELECT DISTINCT ItemSKU FROM SupplyChain_Gold_Warehouse.Shared_DW.DimProduct) AS P ON P.ItemSKU = F.ItemSKU COLLATE Latin1_General_100_BIN2_UTF8
        LEFT JOIN (SELECT DISTINCT WarehouseCode FROM SupplyChain_Gold_Warehouse.Shared_DW.DimWarehouse) AS W ON W.WarehouseCode = F.WarehouseCode COLLATE Latin1_General_100_BIN2_UTF8
        LEFT JOIN (SELECT DISTINCT Date FROM SupplyChain_Gold_Warehouse.Shared_DW.DimCalendar) AS D ON D.Date = F.FSCMonthLast
        LEFT JOIN (SELECT DISTINCT HorizonCode FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimForecastHorizon) AS H ON H.HorizonCode = F.HorizonCode COLLATE Latin1_General_100_BIN2_UTF8
        WHERE ' + @snapPred + N';';

        EXEC sp_executesql @refKpi,
             N'@p_o int OUTPUT,@w_o int OUTPUT,@cal_o int OUTPUT,@h_o int OUTPUT',
             @p_o=@kp OUTPUT,@w_o=@kw OUTPUT,@cal_o=@kcal OUTPUT,@h_o=@kh OUTPUT;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
            WindowStart,WindowEnd,ObservedValue,ExpectedValue,Evidence)
        SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','REFERENCE',1,'GOLD_TECH.FactForecastKpi.'+ref+'.REFERENCE','FactForecastKpi.'+ref,1,
            CASE WHEN missing=0 THEN 'PASS' ELSE 'FAIL' END,
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',
            @WindowStart,@WindowEnd,CAST(missing AS varchar(20)),'0 unmatched fact rows',
            '{"reference":"'+ref+'","scope":"three_completed_months"}'
        FROM (VALUES ('product',@kp),('warehouse',@kw),('calendar',@kcal),('horizon',@kh)) v(ref,missing);
    END TRY
    BEGIN CATCH
        DECLARE @refErrK varchar(4000) = ERROR_MESSAGE();
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,WindowStart,WindowEnd,ErrorMessage)
        SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','REFERENCE',1,'GOLD_TECH.FactForecastKpi.'+ref+'.REFERENCE','FactForecastKpi.'+ref,1,'ERROR',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',@WindowStart,@WindowEnd,@refErrK
        FROM (VALUES ('product'),('warehouse'),('calendar'),('horizon')) v(ref);
    END CATCH

    -- =======================================================================
    -- GATE 2: GOLD_TECH RESTATEMENT SAFETY (2 KPI checks)
    -- =======================================================================
    -- FactForecastKpi is materialized from a view that joins mutable Actuals.
    -- These checks deliberately use FSCMonthLast (target month), not Snapshot,
    -- so NULL/old snapshots cannot hide a frozen Actual vintage.
    BEGIN TRY
        DECLARE @lagBad bigint = 0;
        DECLARE @lagStmt nvarchar(max) = N'SET NOCOUNT ON;
        WITH grouped AS
        (
            SELECT TRIM(ItemSKU) AS ItemSKU,
                   TRIM(WarehouseCode) AS WarehouseCode,
                   FSCMonthLast,
                   MIN(QtyActual) AS MinActual,
                   MAX(QtyActual) AS MaxActual,
                   SUM(CASE WHEN QtyActual IS NULL THEN 1 ELSE 0 END) AS NullActualRows,
                   SUM(CASE WHEN QtyActual IS NOT NULL THEN 1 ELSE 0 END) AS NonNullActualRows
            FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi
            WHERE FSCMonthLast >= ''' + @WS + N'''
              AND FSCMonthLast < ''' + @WE + N'''
              AND HorizonCode IN (''Lag-0'',''Lag-1'',''Lag-2'',''Lag-3'',''Lag-4'')
            GROUP BY TRIM(ItemSKU), TRIM(WarehouseCode), FSCMonthLast
        )
        SELECT @o = COALESCE(SUM(CASE
            WHEN NonNullActualRows > 0
             AND (NullActualRows > 0 OR ABS(MaxActual - MinActual) > 0.000001)
            THEN 1 ELSE 0 END), 0)
        FROM grouped;';

        EXEC sp_executesql @lagStmt, N'@o bigint OUTPUT', @o=@lagBad OUTPUT;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
            WindowStart,WindowEnd,ObservedValue,ExpectedValue,Evidence)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','INVARIANT',1,'GOLD_TECH.FactForecastKpi.ActualEqualityAcrossLags.INVARIANT',
            'FactForecastKpi.ActualEqualityAcrossLags',1,
            CASE WHEN @lagBad=0 THEN 'PASS' ELSE 'FAIL' END,
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',
            @WindowStart,@WindowEnd,CAST(@lagBad AS varchar(20)),
            '0 ItemSKU+WarehouseCode+FSCMonthLast groups with differing Actual across Lag-0..Lag-4',
            '{"scope":"FSCMonthLast within latest three completed months","horizons":"Lag-0..Lag-4","null_snapshot_included":true}');
    END TRY
    BEGIN CATCH
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
            WindowStart,WindowEnd,ErrorMessage)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','INVARIANT',1,'GOLD_TECH.FactForecastKpi.ActualEqualityAcrossLags.INVARIANT',
            'FactForecastKpi.ActualEqualityAcrossLags',1,'ERROR',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',
            @WindowStart,@WindowEnd,ERROR_MESSAGE());
    END CATCH

    BEGIN TRY
        DECLARE @parityBad bigint = 0;
        DECLARE @parityMissing bigint = 0;
        DECLARE @parityExtra bigint = 0;
        DECLARE @parityStmt nvarchar(max) = N'SET NOCOUNT ON;
        WITH persisted AS
        (
            SELECT TRIM(ItemSKU) AS ItemSKU, TRIM(WarehouseCode) AS WarehouseCode,
                   FSCMonthLast, TRIM(HorizonCode) AS HorizonCode, Snapshot,
                   COUNT_BIG(*) AS RowCnt, MAX(QtyForecast) AS QtyForecast,
                   MAX(QtyActual) AS QtyActual, MAX(QtyNaiveForecast) AS QtyNaiveForecast,
                   MAX(AbsPctError) AS AbsPctError
            FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi
            WHERE FSCMonthLast >= ''' + @WS + N''' AND FSCMonthLast < ''' + @WE + N'''
            GROUP BY TRIM(ItemSKU), TRIM(WarehouseCode), FSCMonthLast, TRIM(HorizonCode), Snapshot
        ), current_view AS
        (
            SELECT TRIM(ItemSKU) AS ItemSKU, TRIM(WarehouseCode) AS WarehouseCode,
                   FSCMonthLast, TRIM(HorizonCode) AS HorizonCode, Snapshot,
                   COUNT_BIG(*) AS RowCnt, MAX(QtyForecast) AS QtyForecast,
                   MAX(QtyActual) AS QtyActual, MAX(QtyNaiveForecast) AS QtyNaiveForecast,
                   MAX(AbsPctError) AS AbsPctError
            FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW_Wrk.v_FactForecastKpi
            WHERE FSCMonthLast >= ''' + @WS + N''' AND FSCMonthLast < ''' + @WE + N'''
            GROUP BY TRIM(ItemSKU), TRIM(WarehouseCode), FSCMonthLast, TRIM(HorizonCode), Snapshot
        ), compared AS
        (
            SELECT p.RowCnt AS PRows, v.RowCnt AS VRows,
                   p.QtyForecast AS PForecast, v.QtyForecast AS VForecast,
                   p.QtyActual AS PActual, v.QtyActual AS VActual,
                   p.QtyNaiveForecast AS PNaive, v.QtyNaiveForecast AS VNaive,
                   p.AbsPctError AS PAbsPct, v.AbsPctError AS VAbsPct
            FROM persisted AS p
            FULL OUTER JOIN current_view AS v
              ON (p.ItemSKU = v.ItemSKU OR (p.ItemSKU IS NULL AND v.ItemSKU IS NULL))
             AND (p.WarehouseCode = v.WarehouseCode OR (p.WarehouseCode IS NULL AND v.WarehouseCode IS NULL))
             AND p.FSCMonthLast = v.FSCMonthLast
             AND (p.HorizonCode = v.HorizonCode OR (p.HorizonCode IS NULL AND v.HorizonCode IS NULL))
             AND (p.Snapshot = v.Snapshot OR (p.Snapshot IS NULL AND v.Snapshot IS NULL))
        )
        SELECT
            @bad = COALESCE(SUM(CASE WHEN PRows IS NULL OR VRows IS NULL OR PRows <> VRows
                  OR ABS(COALESCE(PForecast,0)-COALESCE(VForecast,0)) > 0.000001
                  OR ABS(COALESCE(PActual,0)-COALESCE(VActual,0)) > 0.000001
                  OR ABS(COALESCE(PNaive,0)-COALESCE(VNaive,0)) > 0.000001
                  OR ABS(COALESCE(PAbsPct,0)-COALESCE(VAbsPct,0)) > 0.000001 THEN 1 ELSE 0 END),0),
            @missing = COALESCE(SUM(CASE WHEN PRows IS NULL THEN 1 ELSE 0 END),0),
            @extra = COALESCE(SUM(CASE WHEN VRows IS NULL THEN 1 ELSE 0 END),0)
        FROM compared;';

        EXEC sp_executesql @parityStmt,
             N'@bad bigint OUTPUT,@missing bigint OUTPUT,@extra bigint OUTPUT',
             @bad=@parityBad OUTPUT,@missing=@parityMissing OUTPUT,@extra=@parityExtra OUTPUT;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,
            WindowStart,WindowEnd,ObservedValue,ExpectedValue,MissingInGold,ExtraInGold,Evidence)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','RECONCILIATION',1,'GOLD_TECH.FactForecastKpi.CurrentViewParity.RECONCILIATION',
            'FactForecastKpi.CurrentViewParity',1,
            CASE WHEN @parityBad=0 THEN 'PASS' ELSE 'FAIL' END,
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW_Wrk.v_FactForecastKpi',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',
            @WindowStart,@WindowEnd,CAST(@parityBad AS varchar(20)),
            '0 persisted/current-view key or metric mismatches',@parityMissing,@parityExtra,
            '{"scope":"FSCMonthLast within latest three completed months","metrics":"QtyForecast,QtyActual,QtyNaiveForecast,AbsPctError","null_snapshot_included":true}');
    END TRY
    BEGIN CATCH
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,
            WindowStart,WindowEnd,ErrorMessage)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','RECONCILIATION',1,'GOLD_TECH.FactForecastKpi.CurrentViewParity.RECONCILIATION',
            'FactForecastKpi.CurrentViewParity',1,'ERROR',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW_Wrk.v_FactForecastKpi',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',
            @WindowStart,@WindowEnd,ERROR_MESSAGE());
    END CATCH

    -- =======================================================================
    -- GATE 2: GOLD_TECH INVARIANT (9 KPI formula checks)
    -- =======================================================================
    BEGIN TRY
        DECLARE @tcnt bigint,@b1 bigint,@b2 bigint,@b3 bigint,@b4 bigint,@b5 bigint,@b6 bigint,@b7 bigint,@b8 bigint,@b9 bigint;
        DECLARE @invStmt nvarchar(max) = N'SET NOCOUNT ON;
        SELECT
            @tc = COUNT_BIG(*),
            @e1 = COALESCE(SUM(CASE WHEN ABS(COALESCE(QtyFcstError,0) - (COALESCE(QtyForecast,0)-COALESCE(QtyActual,0))) > 0.000001 THEN 1 ELSE 0 END),0),
            @e2 = COALESCE(SUM(CASE WHEN ABS(COALESCE(QtyAbsFcstError,0) - ABS(COALESCE(QtyForecast,0)-COALESCE(QtyActual,0))) > 0.000001 THEN 1 ELSE 0 END),0),
            @e3 = COALESCE(SUM(CASE WHEN ABS(COALESCE(QtyNaiveFcstError,0) - (COALESCE(QtyNaiveForecast,0)-COALESCE(QtyActual,0))) > 0.000001 THEN 1 ELSE 0 END),0),
            @e4 = COALESCE(SUM(CASE WHEN ABS(COALESCE(QtyAbsNaiveFcstError,0) - ABS(COALESCE(QtyNaiveForecast,0)-COALESCE(QtyActual,0))) > 0.000001 THEN 1 ELSE 0 END),0),
            @e5 = COALESCE(SUM(CASE WHEN ABS(COALESCE(QtySquaredFcstError,0) - POWER(COALESCE(QtyForecast,0)-COALESCE(QtyActual,0),2)) > 0.000001 THEN 1 ELSE 0 END),0),
            @e6 = COALESCE(SUM(CASE WHEN ABS(COALESCE(QtySquaredNaiveFcstError,0) - POWER(COALESCE(QtyNaiveForecast,0)-COALESCE(QtyActual,0),2)) > 0.000001 THEN 1 ELSE 0 END),0),
            @e7 = COALESCE(SUM(CASE WHEN COALESCE(ValidObsFlag,-1) <> CASE WHEN QtyActual IS NOT NULL AND QtyForecast IS NOT NULL THEN 1 ELSE 0 END THEN 1 ELSE 0 END),0),
            @e8 = COALESCE(SUM(CASE WHEN COALESCE(ValidActualNonzeroFlag,-1) <> CASE WHEN QtyActual IS NOT NULL AND QtyActual <> 0 THEN 1 ELSE 0 END THEN 1 ELSE 0 END),0),
            @e9 = COALESCE(SUM(CASE
                WHEN QtyActual IS NULL OR QtyActual = 0 THEN CASE WHEN AbsPctError IS NULL THEN 0 ELSE 1 END
                WHEN AbsPctError IS NULL OR ABS(AbsPctError - ABS((COALESCE(QtyForecast,0)-QtyActual)/QtyActual)) > 0.000001 THEN 1
                ELSE 0 END),0)
        FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi
        WHERE ' + @snapPred + N';';

        EXEC sp_executesql @invStmt,
             N'@tc bigint OUTPUT,@e1 bigint OUTPUT,@e2 bigint OUTPUT,@e3 bigint OUTPUT,@e4 bigint OUTPUT,@e5 bigint OUTPUT,@e6 bigint OUTPUT,@e7 bigint OUTPUT,@e8 bigint OUTPUT,@e9 bigint OUTPUT',
             @tc=@tcnt OUTPUT,@e1=@b1 OUTPUT,@e2=@b2 OUTPUT,@e3=@b3 OUTPUT,@e4=@b4 OUTPUT,@e5=@b5 OUTPUT,@e6=@b6 OUTPUT,@e7=@b7 OUTPUT,@e8=@b8 OUTPUT,@e9=@b9 OUTPUT;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,
            WindowStart,WindowEnd,TargetCount,ObservedValue,ExpectedValue,Evidence)
        SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','INVARIANT',1,'GOLD_TECH.FactForecastKpi.'+nm+'.INVARIANT','FactForecastKpi.'+nm,1,
            CASE WHEN bad=0 THEN 'PASS' ELSE 'FAIL' END,
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',
            @WindowStart,@WindowEnd,@tcnt,CAST(bad AS varchar(20)),'0 invalid rows',
            '{"epsilon":"0.000001","scope":"three_completed_snapshot_months"}'
        FROM (VALUES
            ('ForecastErrorFormula',@b1),('AbsoluteErrorFormula',@b2),('NaiveErrorFormula',@b3),
            ('AbsoluteNaiveErrorFormula',@b4),('SquaredErrorFormula',@b5),('SquaredNaiveErrorFormula',@b6),
            ('ValidObservationFlag',@b7),('ValidActualNonzeroFlag',@b8),('AbsolutePercentageErrorFormula',@b9)
        ) v(nm,bad);
    END TRY
    BEGIN CATCH
        DECLARE @invErr varchar(4000) = ERROR_MESSAGE();
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,WindowStart,WindowEnd,ErrorMessage)
        SELECT @DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'GOLD_TECH','INVARIANT',1,'GOLD_TECH.FactForecastKpi.'+nm+'.INVARIANT','FactForecastKpi.'+nm,1,'ERROR',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastKpi',@WindowStart,@WindowEnd,@invErr
        FROM (VALUES
            ('ForecastErrorFormula'),('AbsoluteErrorFormula'),('NaiveErrorFormula'),
            ('AbsoluteNaiveErrorFormula'),('SquaredErrorFormula'),('SquaredNaiveErrorFormula'),
            ('ValidObservationFlag'),('ValidActualNonzeroFlag'),('AbsolutePercentageErrorFormula')
        ) v(nm);
    END CATCH

    -- =======================================================================
    -- GATE 3: BRONZE_GOLD  (identity capture -> reconcile -> finalize DataCutId)
    -- =======================================================================
    -- Identity BEFORE. Comparability proof = identity unchanged across the run.
    DECLARE @fqLoadBefore varchar(40), @fqLoadAfter varchar(40);
    DECLARE @cgcSrcBefore bigint, @cgcTmlBefore varchar(40), @cgcTrcBefore bigint;
    DECLARE @cgcSrcAfter bigint,  @cgcTmlAfter varchar(40),  @cgcTrcAfter bigint;

    SELECT @fqLoadBefore = CONVERT(varchar(33), MAX(LoadDT), 126)
    FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual
    WHERE StatusCode = 'Forecast'
      AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') >= @WindowStart
      AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') < @WindowEndExclusive;

    SELECT @cgcTmlBefore = CONVERT(varchar(33), MAX(LoadDT), 126), @cgcTrcBefore = COUNT_BIG(*)
    FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping;
    SELECT @cgcSrcBefore = COUNT_BIG(*)
    FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
    WHERE CustomerGroup IS NOT NULL;

    -- --- ForecastQty reconciliation (immutable completed-month partition) ---
    DECLARE @fqSrcCnt bigint, @fqTgtCnt bigint, @fqSrcMeas decimal(38,6), @fqTgtMeas decimal(38,6),
            @fqMissing bigint, @fqExtra bigint;
    DECLARE @fqStatus varchar(32);
    BEGIN TRY
        WITH source_raw AS (
                SELECT TRIM(f.dfcItem) AS ItemSKU, TRIM(f.dfcWarehouse) AS WarehouseCode,
                       UPPER(TRIM(f.DfcCustomerGroups)) AS CustomerGroupCode,
                       DATEFROMPARTS(CAST(f.dfcFiscalMonth/100 AS int), CAST(f.dfcFiscalMonth%100 AS int),1) AS FiscalMonth,
                       CAST(f.dfcSnapshot AS date) AS Snapshot,
                       SUM(f.dfcResultantForecast) AS QtyResultantForecast,
                       SUM(f.dfcPromotionalLift) AS QtyPromotionalLift
                FROM Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily AS f
                INNER JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.ForecastCycle AS c
                    ON CAST(f.dfcSnapshot AS date) = c.ForecastSnapshot
                WHERE CAST(f.dfcSnapshot AS date) >= @WindowStart AND CAST(f.dfcSnapshot AS date) < @WindowEndExclusive
                  AND DATEFROMPARTS(CAST(f.dfcFiscalMonth/100 AS int), CAST(f.dfcFiscalMonth%100 AS int),1) >= @ForecastFiscalStart
                  AND DATEFROMPARTS(CAST(f.dfcFiscalMonth/100 AS int), CAST(f.dfcFiscalMonth%100 AS int),1) <= @ForecastFiscalEnd
                GROUP BY TRIM(f.dfcItem), TRIM(f.dfcWarehouse), UPPER(TRIM(f.DfcCustomerGroups)),
                    DATEFROMPARTS(CAST(f.dfcFiscalMonth/100 AS int), CAST(f.dfcFiscalMonth%100 AS int),1),
                    CAST(f.dfcSnapshot AS date)
            ), source_classified AS (
                SELECT r.ItemSKU, r.WarehouseCode, r.CustomerGroupCode, cal.FSCMonthLast,
                    DATEFROMPARTS(YEAR(r.Snapshot), MONTH(r.Snapshot),1) AS SnapshotVersionMonth,
                    CASE
                        WHEN DATEDIFF(month, r.Snapshot, r.FiscalMonth)=0 THEN 'Lag-0'
                        WHEN DATEDIFF(month, r.Snapshot, r.FiscalMonth)=1 THEN 'Lag-1'
                        WHEN DATEDIFF(month, r.Snapshot, r.FiscalMonth)=2 THEN 'Lag-2'
                        WHEN DATEDIFF(month, r.Snapshot, r.FiscalMonth)=3 THEN 'Lag-3'
                        WHEN DATEDIFF(month, r.Snapshot, r.FiscalMonth)=4 THEN 'Lag-4'
                        ELSE '>Lag-4' END AS HorizonCode,
                    CAST(r.QtyResultantForecast + r.QtyPromotionalLift AS decimal(38,6)) AS Qty
                FROM source_raw AS r
                INNER JOIN SupplyChain_Processing_Warehouse.ReferenceMaster_Enh.Calendar AS cal
                    ON cal.Date = r.FiscalMonth
            ), source_normalized AS (
                SELECT ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, SnapshotVersionMonth, HorizonCode,
                    CAST(SUM(Qty) AS decimal(38,6)) AS Qty, CAST(1 AS int) AS SourcePresent
                FROM source_classified
                GROUP BY ItemSKU, WarehouseCode, CustomerGroupCode, FSCMonthLast, SnapshotVersionMonth, HorizonCode
            ), target_normalized AS (
                SELECT TRIM(ItemSKU) AS ItemSKU, TRIM(WarehouseCode) AS WarehouseCode,
                    UPPER(TRIM(CustomerGroupCode)) AS CustomerGroupCode, FSCMonthLast,
                    TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') AS Snapshot,
                    TRIM(HorizonCode) AS HorizonCode,
                    CAST(SUM(Qty) AS decimal(38,6)) AS Qty, CAST(1 AS int) AS TargetPresent
                FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual
                WHERE StatusCode = 'Forecast'
                  AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') >= @WindowStart
                  AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') < @WindowEndExclusive
                GROUP BY TRIM(ItemSKU), TRIM(WarehouseCode), UPPER(TRIM(CustomerGroupCode)), FSCMonthLast,
                    TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01'), TRIM(HorizonCode)
            ), compared AS (
                SELECT s.Qty AS SourceQty, t.Qty AS TargetQty,
                       COALESCE(s.SourcePresent,0) AS HasSource, COALESCE(t.TargetPresent,0) AS HasTarget
                FROM source_normalized AS s
                FULL OUTER JOIN target_normalized AS t
                    ON (s.ItemSKU = t.ItemSKU OR (s.ItemSKU IS NULL AND t.ItemSKU IS NULL))
                   AND (s.WarehouseCode = t.WarehouseCode OR (s.WarehouseCode IS NULL AND t.WarehouseCode IS NULL))
                   AND (s.CustomerGroupCode = t.CustomerGroupCode OR (s.CustomerGroupCode IS NULL AND t.CustomerGroupCode IS NULL))
                   AND s.FSCMonthLast = t.FSCMonthLast
                   AND s.SnapshotVersionMonth = t.Snapshot
                   AND s.HorizonCode = t.HorizonCode
            )
            SELECT
                @fqSrcCnt = COALESCE(SUM(HasSource),0),
                @fqTgtCnt = COALESCE(SUM(HasTarget),0),
                @fqSrcMeas = CAST(COALESCE(SUM(SourceQty),0) AS decimal(38,6)),
                @fqTgtMeas = CAST(COALESCE(SUM(TargetQty),0) AS decimal(38,6)),
                @fqMissing = COALESCE(SUM(CASE WHEN HasSource=1 AND HasTarget=0 THEN 1 ELSE 0 END),0),
                @fqExtra   = COALESCE(SUM(CASE WHEN HasSource=0 AND HasTarget=1 THEN 1 ELSE 0 END),0)
            FROM compared;

        SET @fqStatus = CASE WHEN @fqSrcCnt = @fqTgtCnt AND ABS(@fqSrcMeas - @fqTgtMeas) <= @DevTolerance
                              AND @fqMissing = 0 AND @fqExtra = 0 THEN 'PASS' ELSE 'FAIL' END;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,
            WindowStart,WindowEnd,SourceCount,TargetCount,SourceDistinctKeyCount,TargetDistinctKeyCount,
            SourceMeasure,TargetMeasure,Difference,Tolerance,MissingInGold,ExtraInGold,ObservedValue,ExpectedValue,Evidence)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.ForecastQty.RECONCILIATION','ForecastQty',1,@fqStatus,
            'Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',
            @WindowStart,@WindowEnd,@fqSrcCnt,@fqTgtCnt,@fqSrcCnt,@fqTgtCnt,
            @fqSrcMeas,@fqTgtMeas,@fqSrcMeas-@fqTgtMeas,@DevTolerance,@fqMissing,@fqExtra,
            CASE WHEN @fqStatus='PASS' THEN 'metrics_match' ELSE 'metrics_differ' END,
            'matching metrics over an immutable common cut',
            '{"comparability":"immutable_completed_month_partition"}');
    END TRY
    BEGIN CATCH
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,WindowStart,WindowEnd,ErrorMessage)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.ForecastQty.RECONCILIATION','ForecastQty',1,'ERROR',
            'Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',@WindowStart,@WindowEnd,ERROR_MESSAGE());
    END CATCH

    -- --- CustomerGroupCoverage reconciliation (bracketed current-state ref) ---
    DECLARE @cgcSrc bigint, @cgcTgt bigint, @cgcMissing bigint, @cgcExtra bigint, @cgcStatus varchar(32);
    BEGIN TRY
        WITH source_keys AS (
                SELECT DISTINCT TRIM(CustomerNumber) AS Customer
                FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
                WHERE CustomerGroup IS NOT NULL AND TRIM(CustomerGroup) <> '' AND TRIM(CustomerNumber) <> ''
            ), target_keys AS (
                SELECT DISTINCT TRIM(Customer) AS Customer
                FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping
                WHERE Customer IS NOT NULL AND TRIM(Customer) <> ''
            ), compared AS (
                SELECT
                    CASE WHEN s.Customer IS NOT NULL THEN 1 ELSE 0 END AS HasSource,
                    CASE WHEN t.Customer IS NOT NULL THEN 1 ELSE 0 END AS HasTarget
                FROM source_keys AS s
                FULL OUTER JOIN target_keys AS t ON s.Customer = t.Customer
            )
            SELECT
                @cgcSrc = COALESCE(SUM(HasSource),0),
                @cgcTgt = COALESCE(SUM(HasTarget),0),
                @cgcMissing = COALESCE(SUM(CASE WHEN HasSource=1 AND HasTarget=0 THEN 1 ELSE 0 END),0),
                @cgcExtra   = COALESCE(SUM(CASE WHEN HasSource=0 AND HasTarget=1 THEN 1 ELSE 0 END),0)
            FROM compared;

        SET @cgcStatus = CASE WHEN @cgcMissing = 0 AND @cgcExtra = 0 THEN 'PASS' ELSE 'FAIL' END;

        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,
            WindowStart,WindowEnd,SourceCount,TargetCount,SourceDistinctKeyCount,TargetDistinctKeyCount,
            MissingInGold,ExtraInGold,ObservedValue,ExpectedValue,Evidence)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.CustomerGroupCoverage.RECONCILIATION','CustomerGroupCoverage',1,@cgcStatus,
            'Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping',
            @WindowStart,@WindowEnd,@cgcSrc,@cgcTgt,@cgcSrc,@cgcTgt,@cgcMissing,@cgcExtra,
            CASE WHEN @cgcStatus='PASS' THEN 'full_coverage' ELSE 'coverage_gap' END,
            'every Bronze customer present in Gold dim, none invented',
            '{"key":["Customer"],"comparability":"bracketed_current_state_reference","scope":"current_state_reference"}');
    END TRY
    BEGIN CATCH
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,WindowStart,WindowEnd,ErrorMessage)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.CustomerGroupCoverage.RECONCILIATION','CustomerGroupCoverage',1,'ERROR',
            'Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping',
            'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping',@WindowStart,@WindowEnd,ERROR_MESSAGE());
    END CATCH

    -- --- ActualDemandQty reconciliation adapter (Invoice component only) ---
    DECLARE @adSrcCnt bigint, @adTgtCnt bigint, @adSrcMeas decimal(38,6), @adTgtMeas decimal(38,6),
            @adDiff decimal(38,6), @adRelDiff decimal(38,6), @adStatus varchar(32);
    BEGIN TRY
        SELECT @adSrcCnt=COUNT_BIG(*),
               @adSrcMeas=CAST(COALESCE(SUM(CAST(QuantityShipped AS decimal(38,6))),0) AS decimal(38,6))
        FROM Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail
        WHERE InvoiceDate >= @WindowStart AND InvoiceDate < @WindowEndExclusive;
        SELECT @adTgtCnt=COUNT_BIG(*),
               @adTgtMeas=CAST(COALESCE(SUM(CAST(Qty AS decimal(38,6))),0) AS decimal(38,6))
        FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual
        WHERE StatusCode='Invoice' AND FSCMonthLast >= @WindowStart AND FSCMonthLast < @WindowEndExclusive;
        SET @adDiff=@adSrcMeas-@adTgtMeas;
        SET @adRelDiff=CASE WHEN @adSrcMeas=0 THEN CASE WHEN @adTgtMeas=0 THEN 0 ELSE 1 END ELSE ABS(@adDiff)/ABS(@adSrcMeas) END;
        SET @adStatus=CASE WHEN @adRelDiff <= @ReconciliationTolerancePct THEN 'PASS' ELSE 'FAIL' END;
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,
            WindowStart,WindowEnd,SourceCount,TargetCount,SourceMeasure,TargetMeasure,Difference,Tolerance,ObservedValue,ExpectedValue,Evidence)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.ActualDemandQty.RECONCILIATION','ActualDemandQty',1,@adStatus,
            'Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail','SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',
            @WindowStart,@WindowEnd,@adSrcCnt,@adTgtCnt,@adSrcMeas,@adTgtMeas,@adDiff,@ReconciliationTolerancePct,
            'relative_difference='+CONVERT(varchar(40),@adRelDiff),'relative difference <= '+CONVERT(varchar(40),@ReconciliationTolerancePct),
            '{"adapter":"scalar_aggregate","bronze_metric":"SUM(QuantityShipped)","gold_metric":"SUM(Qty)","gold_filter":"StatusCode=Invoice","no_transform_replay":true}');
    END TRY
    BEGIN CATCH
        INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
            GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,WindowStart,WindowEnd,ErrorMessage)
        VALUES (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
            'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.ActualDemandQty.RECONCILIATION','ActualDemandQty',1,'ERROR',
            'Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail','SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',@WindowStart,@WindowEnd,ERROR_MESSAGE());
    END CATCH

    -- --- Naive forecast remains nonblocking SKIPPED: no Bronze counterpart. ---
    INSERT INTO #results (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,RuleVersion,
        GateCode,CheckType,Tier,RuleCode,ObjectOrFlow,IsBlocking,Status,TargetObject,WindowStart,WindowEnd,ExpectedValue,Evidence)
    VALUES
    (@DQRunId,@DQRunAtUTC,SYSUTCDATETIME(),@MartCode,@PipelineRunId,@RuleVersion,
        'BRONZE_GOLD','RECONCILIATION',1,'BRONZE_GOLD.NaiveForecastQty.RECONCILIATION','NaiveForecastQty',0,'SKIPPED',
        'SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual',@WindowStart,@WindowEnd,
        'derived measure has no direct Bronze counterpart; reconciliation not applicable',
        '{"template_applicable":false,"no_transform_replay":true}');

    -- -----------------------------------------------------------------------
    -- Identity AFTER + finalize DataCutId / NOT_COMPARABLE demotion.
    -- -----------------------------------------------------------------------
    SELECT @fqLoadAfter = CONVERT(varchar(33), MAX(LoadDT), 126)
    FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.FactForecastActual
    WHERE StatusCode = 'Forecast'
      AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') >= @WindowStart
      AND TRY_CONVERT(date, REPLACE(SUBSTRING(VersionName,3,7),'.','-') + '-01') < @WindowEndExclusive;

    SELECT @cgcTmlAfter = CONVERT(varchar(33), MAX(LoadDT), 126), @cgcTrcAfter = COUNT_BIG(*)
    FROM SupplyChain_Gold_Warehouse.ForecastAccuracy_DW.DimCustomerGrouping;
    SELECT @cgcSrcAfter = COUNT_BIG(*)
    FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping
    WHERE CustomerGroup IS NOT NULL AND TRIM(CustomerGroup) <> '';

    -- ForecastQty: stable iff before == after (both NULL counts as unstable, matching oracle before IS NOT NULL rule)
    DECLARE @fqStable bit = CASE WHEN @fqLoadBefore IS NOT NULL AND @fqLoadBefore = @fqLoadAfter THEN 1 ELSE 0 END;
    DECLARE @fqIdent varchar(4000) = '{"target_load": "' + ISNULL(@fqLoadBefore,'') + '"}';
    DECLARE @fqCut varchar(64) = LOWER(SUBSTRING(CONVERT(varchar(64),
        HASHBYTES('SHA2_256', CAST('ForecastQty|'+@WS+'|'+@WE+'|'+@fqIdent AS varchar(8000))), 2),1,32));

    UPDATE #results
    SET DataCutId = CASE WHEN @fqStable = 1 THEN @fqCut ELSE NULL END,
        Status = CASE WHEN Status IN ('PASS','FAIL') AND @fqStable = 0 THEN 'NOT_COMPARABLE' ELSE Status END
    WHERE GateCode='BRONZE_GOLD' AND ObjectOrFlow='ForecastQty' AND CheckType='RECONCILIATION';

    -- CustomerGroupCoverage: stable iff all three identity fields unchanged
    DECLARE @cgcStable bit = CASE WHEN @cgcSrcBefore = @cgcSrcAfter
                                    AND @cgcTrcBefore = @cgcTrcAfter
                                    AND ISNULL(@cgcTmlBefore,'') = ISNULL(@cgcTmlAfter,'') THEN 1 ELSE 0 END;
    DECLARE @cgcIdent varchar(4000) =
        '{"source_row_count": ' + CAST(@cgcSrcBefore AS varchar(20)) +
        ', "target_max_load_dt": "' + ISNULL(@cgcTmlBefore,'') + '"' +
        ', "target_row_count": ' + CAST(@cgcTrcBefore AS varchar(20)) + '}';
    DECLARE @cgcCut varchar(64) = LOWER(SUBSTRING(CONVERT(varchar(64),
        HASHBYTES('SHA2_256', CAST('CustomerGroupCoverage|'+@WS+'|'+@WE+'|'+@cgcIdent AS varchar(8000))), 2),1,32));

    UPDATE #results
    SET DataCutId = CASE WHEN @cgcStable = 1 THEN @cgcCut ELSE NULL END,
        Status = CASE WHEN Status IN ('PASS','FAIL') AND @cgcStable = 0 THEN 'NOT_COMPARABLE' ELSE Status END
    WHERE GateCode='BRONZE_GOLD' AND ObjectOrFlow='CustomerGroupCoverage' AND CheckType='RECONCILIATION';

    -- =======================================================================
    -- Decision over blocking rows.
    -- =======================================================================
    DECLARE @Decision varchar(32);
    IF EXISTS (SELECT 1 FROM #results WHERE IsBlocking=1 AND Status='ERROR')
        SET @Decision = 'ERROR';
    ELSE IF EXISTS (SELECT 1 FROM #results WHERE IsBlocking=1 AND Status='FAIL')
        SET @Decision = 'FAIL';
    ELSE IF EXISTS (SELECT 1 FROM #results WHERE IsBlocking=1 AND Status='NOT_COMPARABLE')
        SET @Decision = 'NOT_COMPARABLE';
    ELSE IF EXISTS (SELECT 1 FROM #results WHERE IsBlocking=1 AND Status NOT IN ('PASS'))
        SET @Decision = 'ERROR';
    ELSE
        SET @Decision = 'PASS';

    SET @DQRunIdOutput = @DQRunId;
    SET @DecisionOutput = @Decision;

    -- =======================================================================
    -- Persist (optional) + return.
    -- =======================================================================
    -- Fabric Warehouse compiles a stored proc body in distributed mode, which
    -- rejects INSERT <real table> SELECT FROM #temp (error 15816). Verified live:
    -- INSERT..VALUES(@scalars) inside a proc works. So persistence walks #results
    -- row-by-row and inserts scalar values. (S2 pattern, proven 2026-07-22.)
    IF @Persist = 1
    BEGIN
        DECLARE @pcnt int = (SELECT COUNT(*) FROM #results);
        DECLARE @pi int = 1;
        WHILE @pi <= @pcnt
        BEGIN
            DECLARE @p_DataCutId varchar(256), @p_GateCode varchar(32), @p_CheckType varchar(32),
                    @p_Tier int, @p_RuleCode varchar(256), @p_ParentRuleCode varchar(256),
                    @p_ObjectOrFlow varchar(256), @p_IsBlocking bit, @p_Status varchar(32),
                    @p_SourceObject varchar(512), @p_TargetObject varchar(512),
                    @p_SourceCount bigint, @p_TargetCount bigint,
                    @p_SourceDistinctKeyCount bigint, @p_TargetDistinctKeyCount bigint,
                    @p_SourceMeasure decimal(38,6), @p_TargetMeasure decimal(38,6),
                    @p_Difference decimal(38,6), @p_Tolerance decimal(38,6),
                    @p_MissingInGold bigint, @p_ExtraInGold bigint,
                    @p_ObservedValue varchar(4000), @p_ExpectedValue varchar(4000),
                    @p_Evidence varchar(8000), @p_ErrorMessage varchar(4000),
                    @p_RowLoadDT datetime2(6);

            SELECT
                @p_DataCutId = DataCutId, @p_GateCode = GateCode, @p_CheckType = CheckType,
                @p_Tier = Tier, @p_RuleCode = RuleCode, @p_ParentRuleCode = ParentRuleCode,
                @p_ObjectOrFlow = ObjectOrFlow, @p_IsBlocking = IsBlocking, @p_Status = Status,
                @p_SourceObject = SourceObject, @p_TargetObject = TargetObject,
                @p_SourceCount = SourceCount, @p_TargetCount = TargetCount,
                @p_SourceDistinctKeyCount = SourceDistinctKeyCount, @p_TargetDistinctKeyCount = TargetDistinctKeyCount,
                @p_SourceMeasure = SourceMeasure, @p_TargetMeasure = TargetMeasure,
                @p_Difference = Difference, @p_Tolerance = Tolerance,
                @p_MissingInGold = MissingInGold, @p_ExtraInGold = ExtraInGold,
                @p_ObservedValue = ObservedValue, @p_ExpectedValue = ExpectedValue,
                @p_Evidence = Evidence, @p_ErrorMessage = ErrorMessage, @p_RowLoadDT = LoadDT
            FROM #results WHERE OrderSeq = @pi;

            INSERT INTO DataQuality.DQForecastAccuracyGate
                (DQRunId,DQRunAtUTC,LoadDT,MartCode,PipelineRunId,DataCutId,RuleVersion,GateCode,CheckType,Tier,
                 RuleCode,ParentRuleCode,ObjectOrFlow,IsBlocking,Status,SourceObject,TargetObject,WindowStart,WindowEnd,
                 SourceCount,TargetCount,SourceDistinctKeyCount,TargetDistinctKeyCount,SourceMeasure,TargetMeasure,
                 Difference,Tolerance,MissingInGold,ExtraInGold,ObservedValue,ExpectedValue,Evidence,ErrorMessage)
            VALUES
                (@DQRunId,@DQRunAtUTC,@p_RowLoadDT,@MartCode,@PipelineRunId,@p_DataCutId,@RuleVersion,@p_GateCode,@p_CheckType,@p_Tier,
                 @p_RuleCode,@p_ParentRuleCode,@p_ObjectOrFlow,@p_IsBlocking,@p_Status,@p_SourceObject,@p_TargetObject,@WindowStart,@WindowEnd,
                 @p_SourceCount,@p_TargetCount,@p_SourceDistinctKeyCount,@p_TargetDistinctKeyCount,@p_SourceMeasure,@p_TargetMeasure,
                 @p_Difference,@p_Tolerance,@p_MissingInGold,@p_ExtraInGold,@p_ObservedValue,@p_ExpectedValue,@p_Evidence,@p_ErrorMessage);

            SET @pi += 1;
        END
    END

    IF @EmitResults = 1
    BEGIN
        -- Result set 1: run summary
        SELECT @DQRunId AS DQRunId, @Decision AS Decision, @RuleVersion AS RuleVersion,
               @WindowStart AS WindowStart, @WindowEnd AS WindowEnd, @WindowEndExclusive AS WindowEndExclusive,
               (SELECT COUNT(*) FROM #results) AS ResultCount,
               (SELECT COUNT(*) FROM #results WHERE Status='PASS') AS PassCount,
               (SELECT COUNT(*) FROM #results WHERE Status='FAIL') AS FailCount,
               (SELECT COUNT(*) FROM #results WHERE Status='SKIPPED') AS SkippedCount,
               (SELECT COUNT(*) FROM #results WHERE Status='NOT_COMPARABLE') AS NotComparableCount,
               (SELECT COUNT(*) FROM #results WHERE Status='ERROR') AS ErrorCount,
               @Persist AS Persisted;

        -- Result set 2: full detail
        SELECT * FROM #results ORDER BY OrderSeq;
    END
END;
