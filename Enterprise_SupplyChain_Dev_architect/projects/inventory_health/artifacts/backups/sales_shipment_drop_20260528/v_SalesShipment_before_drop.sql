-- =====================================================================
-- Mart B Inventory Health - DA-first refactor candidate
-- Created: 2026-05-27
--
-- Purpose:
--   Build additive candidate views for the DA Silver_Check refactor without
--   replacing production tables/views.
--
-- Source of truth:
--   1. artifacts/source_inputs/inventory_health_project_resources_2026-06-02.xlsx, sheet Silver_Check
--   2. artifacts/source_inputs/inventoryhistory_enh_silver_view_sql_export_2026-06-02.md
--   3. Live 2026-05-26 post-fix architecture:
--      InventorySnapshotWeeklyFactBase remains the helper/fact base.
--
-- Safety:
--   - This script creates/updates * views only.
--   - It does not DROP, TRUNCATE, DELETE, or replace production objects.
--   - Do not swap production registry/view names from this script without
--     explicit approval.
-- =====================================================================


-- ---------------------------------------------------------------------
-- P0 candidate: replace Mart B SalesShipment source with Mart A invoice
-- silver view. Same Mart B output contract as InventoryHistory_Enh.SalesShipment.
-- ---------------------------------------------------------------------
CREATE   VIEW InventoryHistory_Enh.v_SalesShipment AS
SELECT
    CAST(InvoiceID AS DECIMAL(18,0))            AS InvoiceNumber,
    CAST(ItemSequenceNum AS DECIMAL(18,0))      AS ItemSequence,
    CAST(TRIM(ItemSKU) AS VARCHAR(50))          AS ItemSku,
    CAST(TRIM(WarehouseCode) AS VARCHAR(50))    AS WarehouseCode,
    CAST(InvoiceDate AS DATE)                   AS InvoiceDate,
    CAST(OrderDate AS DATE)                     AS OrderDate,
    CAST(QtyShipped AS DECIMAL(18,4))           AS QuantityShipped,
    CAST(QtyOrdered AS DECIMAL(18,4))           AS QuantityOrdered,
    CAST(AmtPrice AS DECIMAL(18,4))             AS Price,
    CAST('SalesHistory_Enh' AS VARCHAR(64))     AS SourceSystem,
    CAST('v_InvoiceDetailLineLevel' AS VARCHAR(128)) AS SourceTable
FROM SalesHistory_Enh.v_InvoiceDetailLineLevel
WHERE ItemSKU IS NOT NULL
  AND WarehouseCode IS NOT NULL
  AND TRIM(ItemSKU) <> ''
  AND TRIM(WarehouseCode) <> '';
