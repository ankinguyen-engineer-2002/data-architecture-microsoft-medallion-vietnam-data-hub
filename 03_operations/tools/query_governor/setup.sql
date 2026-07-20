-- Query Governor Audit Log Table
-- Run this once in SupplyChain_Processing_Warehouse to enable audit logging

-- Create Meta schema if not exists
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Meta')
BEGIN
    EXEC('CREATE SCHEMA Meta');
END
GO

-- Create QueryGovernorLog table
IF OBJECT_ID('Meta.QueryGovernorLog', 'U') IS NULL
BEGIN
    CREATE TABLE Meta.QueryGovernorLog (
        LogId BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        LogTimestamp DATETIME2(3) NOT NULL DEFAULT GETDATE(),
        WarehouseName NVARCHAR(200) NOT NULL,
        SessionId NVARCHAR(50) NOT NULL,
        LoginName NVARCHAR(200) NULL,
        QueryStartTime DATETIME2(3) NULL,
        ElapsedSeconds INT NULL,
        Action NVARCHAR(50) NOT NULL,  -- 'WARN', 'KILL'
        QueryText NVARCHAR(MAX) NULL,
        KillSuccess BIT NULL,
        ErrorMessage NVARCHAR(MAX) NULL,
        INDEX IX_QueryGovernorLog_Timestamp (LogTimestamp DESC),
        INDEX IX_QueryGovernorLog_Warehouse (WarehouseName, LogTimestamp DESC)
    );
    
    PRINT 'Created Meta.QueryGovernorLog table';
END
ELSE
BEGIN
    PRINT 'Meta.QueryGovernorLog table already exists';
END
GO

-- Sample query to view recent kills
-- SELECT TOP 100 * FROM Meta.QueryGovernorLog ORDER BY LogTimestamp DESC;
