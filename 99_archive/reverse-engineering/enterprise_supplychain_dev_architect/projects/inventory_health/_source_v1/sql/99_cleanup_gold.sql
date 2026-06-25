/*============================================================
  99_cleanup_gold.sql — DROP ALL gold objects (mandatory after test)
  Run on: SupplyChain Gold Warehouse
  Safety: each DROP uses IF EXISTS — safe to re-run.
============================================================*/

PRINT 'gold cleanup start: ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);

-- ════════════════════════════════════════════════════════
-- 1. DROP PROCEDURES
-- ════════════════════════════════════════════════════════
DROP PROCEDURE IF EXISTS gold.usp_RefreshAll;
DROP PROCEDURE IF EXISTS gold.usp_Build_DimDate;
DROP PROCEDURE IF EXISTS gold.usp_Build_DimItem;
DROP PROCEDURE IF EXISTS gold.usp_Build_DimWarehouse;
DROP PROCEDURE IF EXISTS gold.usp_Build_DimVendor;
DROP PROCEDURE IF EXISTS gold.usp_Build_DimRuleVersion;
DROP PROCEDURE IF EXISTS gold.usp_Build_CogsRollingHelper;
DROP PROCEDURE IF EXISTS gold.usp_Build_FactInventoryHealthSnapshot;
DROP PROCEDURE IF EXISTS gold.usp_Build_FactInventoryRiskForward;

PRINT '  procs dropped';

-- ════════════════════════════════════════════════════════
-- 2. DROP TABLES
-- ════════════════════════════════════════════════════════

-- Staging (in case proc failed mid-build)
DROP TABLE IF EXISTS gold.DimDate_stg;
DROP TABLE IF EXISTS gold.DimItem_stg;
DROP TABLE IF EXISTS gold.DimWarehouse_stg;
DROP TABLE IF EXISTS gold.DimVendor_stg;
DROP TABLE IF EXISTS gold.CogsRollingHelper_stg;
DROP TABLE IF EXISTS gold.FactInventoryHealthSnapshot_stg;
DROP TABLE IF EXISTS gold.FactInventoryRiskForward_stg;

-- Facts (drop first to release fk-like dependencies)
DROP TABLE IF EXISTS gold.FactInventoryHealthSnapshot;
DROP TABLE IF EXISTS gold.FactInventoryRiskForward;

-- Helper
DROP TABLE IF EXISTS gold.CogsRollingHelper;

-- Dims
DROP TABLE IF EXISTS gold.DimDate;
DROP TABLE IF EXISTS gold.DimItem;
DROP TABLE IF EXISTS gold.DimWarehouse;
DROP TABLE IF EXISTS gold.DimVendor;
DROP TABLE IF EXISTS gold.DimRuleVersion;

PRINT '  tables dropped';

-- ════════════════════════════════════════════════════════
-- 3. DROP SCHEMA
-- ════════════════════════════════════════════════════════
DROP SCHEMA IF EXISTS gold;
PRINT '  schema dropped';


-- ════════════════════════════════════════════════════════
-- 4. VERIFY cleanup complete
-- ════════════════════════════════════════════════════════
SELECT
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES   WHERE TABLE_SCHEMA = 'gold') AS RemainingTables,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = 'gold') AS RemainingProcs,
    (SELECT COUNT(*) FROM sys.schemas WHERE name = 'gold') AS SchemaExists;
-- expect: 0, 0, 0

PRINT 'gold cleanup done: ' + CONVERT(VARCHAR, SYSUTCDATETIME(), 121);
GO
