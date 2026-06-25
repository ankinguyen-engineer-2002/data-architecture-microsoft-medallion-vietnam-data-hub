-- 11_create_audit_log.sql
-- Create Meta.AuditLog matching Bob's ETL_Framework.DW_Developer.AuditLog schema.
-- Observed cols (from EnterpriseData-Dev scan): Description, DateTime, [User], Command.
-- Plus VN-specific: error_message, asset_id (for cross-ref to AssetRegistry).
--
-- Phase 1: local-only writes from usp_LogRun.
-- Phase 2 (after Bob Q1 unblocks): cross-DB INSERT into ETL_Framework.DW_Developer.AuditLog.

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
               WHERE s.name = 'Meta' AND t.name = 'AuditLog')
BEGIN
    EXEC('
    CREATE TABLE Meta.AuditLog (
        AuditID         BIGINT          NOT NULL,
        AuditDateTime   DATETIME2(6)    NOT NULL,
        UserName        VARCHAR(200)    NULL,
        Command         VARCHAR(8000)   NULL,
        Description     VARCHAR(8000)   NULL,
        ErrorMessage    VARCHAR(8000)   NULL,
        AssetID         VARCHAR(128)    NULL,
        RunID           VARCHAR(128)    NULL,
        Severity        VARCHAR(20)     NULL,
        LoadDT          DATETIME2(6)    NULL
    );
    ');
END
GO
