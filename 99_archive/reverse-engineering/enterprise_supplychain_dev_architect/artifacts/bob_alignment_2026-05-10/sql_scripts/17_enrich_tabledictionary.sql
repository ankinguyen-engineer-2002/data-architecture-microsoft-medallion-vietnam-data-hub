-- 17_enrich_tabledictionary.sql
-- Run AFTER seeding (step 14) to fill derivable fields.
-- Pushes fill rate from ~30% (raw seed) to ~60% (with enrichment).
--
-- ColumnCount, ExtractQuery: must run from Python wrapper that probes
-- INFORMATION_SCHEMA / sys.sql_modules client-side (Fabric distributed mode
-- prevents UPDATE…JOIN with sys/INFORMATION_SCHEMA on server).

-- ============== Defaults & user identity ==============
UPDATE Meta.TableDictionary SET CreatedBy   = SYSTEM_USER             WHERE CreatedBy   IS NULL;
UPDATE Meta.TableDictionary SET ModifiedBy  = SYSTEM_USER             WHERE ModifiedBy  IS NULL;
UPDATE Meta.TableDictionary SET SourceServer = 'EDW-Fabric'           WHERE SourceServer IS NULL;
UPDATE Meta.TableDictionary SET ColumnStatsCount = 0                  WHERE ColumnStatsCount IS NULL;

-- ============== Date defaults from Modified or load timestamp ==============
UPDATE Meta.TableDictionary
SET CreateDate  = COALESCE(CreateDate,  Modified, '2026-05-04 00:00:00'),
    Created     = COALESCE(Created,     Modified, '2026-05-04 00:00:00'),
    CreatedDate = COALESCE(CreatedDate, Modified, '2026-05-04 00:00:00');

-- ============== UpdateQuery — construct EXEC statement from OperationKey ==============
UPDATE Meta.TableDictionary
SET UpdateQuery = CONCAT('EXEC Meta.usp_GenericLoad ', OperationKey)
WHERE UpdateQuery IS NULL AND OperationKey IS NOT NULL;

-- ============== SourceDatabase — infer from SourceObject 3-part-name prefix ==============
UPDATE Meta.TableDictionary
SET SourceDatabase = CASE
    WHEN SourceObject LIKE 'Enterprise_Lakehouse.%'             THEN 'Enterprise_Lakehouse'
    WHEN SourceObject LIKE 'SupplyChain_Lakehouse.%'            THEN 'SupplyChain_Lakehouse'
    WHEN SourceObject LIKE 'SupplyChain_Processing_Warehouse.%' THEN 'SupplyChain_Processing_Warehouse'
    ELSE DataLake
END
WHERE SourceDatabase IS NULL AND SourceObject IS NOT NULL;

-- ============== SourceObjectType — infer from SourceObject pattern ==============
UPDATE Meta.TableDictionary
SET SourceObjectType = CASE
    WHEN SourceObject LIKE 'SemanticModel.%' THEN 'SemanticModel'
    WHEN SourceObject IS NULL               THEN NULL
    ELSE 'Table'
END
WHERE SourceObjectType IS NULL;

-- ============== ErrorMsg — last 500 chars from latest RunLog with error ==============
WITH latest_err AS (
    SELECT asset_id, MAX(start_time_utc) AS last_run
    FROM Meta.RunLog
    WHERE error_message IS NOT NULL
    GROUP BY asset_id
)
UPDATE td
SET td.ErrorMsg = CAST(LEFT(rl.error_message, 500) AS VARCHAR(500))
FROM Meta.TableDictionary td
INNER JOIN latest_err le ON td.OperationKey = le.asset_id
INNER JOIN Meta.RunLog rl ON rl.asset_id = le.asset_id AND rl.start_time_utc = le.last_run
WHERE td.ErrorMsg IS NULL;

-- ============== Fabric-native storage defaults ==============
UPDATE Meta.TableDictionary SET IndexType       = 'CLUSTERED COLUMNSTORE' WHERE IndexType IS NULL;
UPDATE Meta.TableDictionary SET DistributionKey = 'AUTO'                  WHERE DistributionKey IS NULL;
GO

-- Note: cols intentionally left NULL (legitimately not applicable to Fabric):
--   AlternateKey, RowSToreClusteredKey, AdditionalIndexes, PartitionKey   -- Fabric auto-managed
--   TFSPath, JobName, JobServer, LibraryList                              -- Synapse/Azure DevOps legacy
--   DataBricksClusterVersion, DataBricksNodeType, DataBricksClusterRange  -- N/A Fabric pipelines
--   PII, ValidKeyValues, SelectColumn                                     -- Manual flags, not yet tracked
--   InvalidCount, DeletedRows                                             -- DQ tracking, future enhancement
--   DataLakeFolderArchive, ReplicatedSourceExpiryHours,
--   ReplicatedSourceArchiveExpiryHours                                    -- Archive policy not configured
--   ColumnStatsLastUpdated, SourceObjectAlias                             -- Not tracked
--   v9_ExecutionOrder                                                     -- Replaced by DAG waves
