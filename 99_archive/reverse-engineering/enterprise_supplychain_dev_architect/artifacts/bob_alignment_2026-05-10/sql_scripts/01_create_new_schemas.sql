-- 01_create_new_schemas.sql
-- Create renamed schemas. Idempotent.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Staging_Wrk') EXEC('CREATE SCHEMA Staging_Wrk');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ReferenceMaster_Enh') EXEC('CREATE SCHEMA ReferenceMaster_Enh');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'SalesHistory_Enh') EXEC('CREATE SCHEMA SalesHistory_Enh');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ForecastHistory_Enh') EXEC('CREATE SCHEMA ForecastHistory_Enh');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'OpenOrderHistory_Enh') EXEC('CREATE SCHEMA OpenOrderHistory_Enh');
