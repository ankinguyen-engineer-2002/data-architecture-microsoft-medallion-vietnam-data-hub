-- 09_drop_empty_old_schemas.sql
-- Drop the 5 old schemas after verifying they are empty.
-- WARNING: Run only after Step 02 transfer + Step 03 view drop succeed.

-- Pre-check Staging_WRK is empty:
-- SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE s.name='Staging_WRK';  -- expected 0
DROP SCHEMA IF EXISTS Staging_WRK;

-- Pre-check ReferenceMaster_ENH is empty:
-- SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE s.name='ReferenceMaster_ENH';  -- expected 0
DROP SCHEMA IF EXISTS ReferenceMaster_ENH;

-- Pre-check SalesHistory_ENH is empty:
-- SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE s.name='SalesHistory_ENH';  -- expected 0
DROP SCHEMA IF EXISTS SalesHistory_ENH;

-- Pre-check ForecastHistory_ENH is empty:
-- SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE s.name='ForecastHistory_ENH';  -- expected 0
DROP SCHEMA IF EXISTS ForecastHistory_ENH;

-- Pre-check OpenOrderHistory_ENH is empty:
-- SELECT COUNT(*) FROM sys.objects o JOIN sys.schemas s ON s.schema_id=o.schema_id WHERE s.name='OpenOrderHistory_ENH';  -- expected 0
DROP SCHEMA IF EXISTS OpenOrderHistory_ENH;

