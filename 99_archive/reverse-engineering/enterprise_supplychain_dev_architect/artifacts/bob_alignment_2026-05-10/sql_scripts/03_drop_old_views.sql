-- 03_drop_old_views.sql
-- Drop all old vw_* views in old _ENH/_WRK schemas. Logic preserved in step 04.

-- Staging_WRK
DROP VIEW IF EXISTS Staging_WRK.vw_Codatan;
DROP VIEW IF EXISTS Staging_WRK.vw_Comast;
DROP VIEW IF EXISTS Staging_WRK.vw_Extord;
DROP VIEW IF EXISTS Staging_WRK.vw_Extorit;

-- ReferenceMaster_ENH
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_Calendar;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_CustomerAccount;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_CustomerAccountGroup;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_CustomerGrouping;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_CustomerShippingLocation;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_ForecastCycle;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_ForecastHorizon;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_ItemMaster;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_OrderType;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_Product;
DROP VIEW IF EXISTS ReferenceMaster_ENH.vw_Warehouse;

-- SalesHistory_ENH
DROP VIEW IF EXISTS SalesHistory_ENH.vw_ActualDemandMonthly;
DROP VIEW IF EXISTS SalesHistory_ENH.vw_ActualDemandWeekly;
DROP VIEW IF EXISTS SalesHistory_ENH.vw_InvoiceDetailLineLevel;
DROP VIEW IF EXISTS SalesHistory_ENH.vw_InvoiceWeekly;

-- ForecastHistory_ENH
DROP VIEW IF EXISTS ForecastHistory_ENH.vw_ForecastDemandMonthly;
DROP VIEW IF EXISTS ForecastHistory_ENH.vw_NaiveForecastMonthly;

-- OpenOrderHistory_ENH
DROP VIEW IF EXISTS OpenOrderHistory_ENH.vw_OpenOrderLineLevel;
DROP VIEW IF EXISTS OpenOrderHistory_ENH.vw_OpenOrderMonthly;

