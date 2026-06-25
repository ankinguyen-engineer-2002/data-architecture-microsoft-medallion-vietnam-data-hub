-- ---- InventoryHealth_DW.v_DimDate ----  [DROPPED 2026-05-22]
-- Reason: duplicate of Shared_DW.DimCalendar (same source ReferenceMaster_Enh.Calendar).
-- Inv_health TMDL now binds directly to Shared_DW.DimCalendar via column-name
-- aliases (DateKey→DateSK, FiscalMonth→FSCMonthNum, etc.). Single shared date dim.
-- IsCurrentDate/IsCurrentWeek/IsMonthEnd flag cols deferred — compute report-level DAX if needed.
-- See git history pre-2026-05-22 for restoration if Phase 2 needs them as physical cols.

-- (Full v_DimDate CREATE VIEW body removed — recoverable from git pre-2026-05-22)


-- ---- InventoryHealth_DW.v_DimItem ----  [DEACTIVATED 2026-05-29]
-- Consolidated to Shared_DW.DimProduct. The shared superset preserves inventory
-- attributes (LifecycleStatus, PrimaryVendorNumber, vendor display name, Cubes,
-- FOBArcPrice, finished-goods and unavailable flags) while keeping Forecast-compatible
-- columns in one physical table.
-- Kept below as historical reference only; live registry marks InventoryHealth_DW.DimItem inactive.
