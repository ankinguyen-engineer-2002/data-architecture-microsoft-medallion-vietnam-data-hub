-- 02_transfer_tables.sql
-- ALTER SCHEMA TRANSFER for all v10 tables. Non-destructive — preserves data.

-- Staging_WRK -> Staging_Wrk
ALTER SCHEMA Staging_Wrk TRANSFER Staging_WRK.InvoiceDetailEdw;
ALTER SCHEMA Staging_Wrk TRANSFER Staging_WRK.InvoiceHeaderEdw;
ALTER SCHEMA Staging_Wrk TRANSFER Staging_WRK.ProductEdw;
ALTER SCHEMA Staging_Wrk TRANSFER Staging_WRK.DemandForecastSnapshotDailyEdw;

-- ReferenceMaster_ENH -> ReferenceMaster_Enh
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.Calendar;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.CustomerAccount;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.CustomerAccountGroup;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.CustomerGrouping;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.CustomerShippingLocation;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.ForecastCycle;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.ForecastHorizon;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.ItemMaster;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.OrderType;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.Product;
ALTER SCHEMA ReferenceMaster_Enh TRANSFER ReferenceMaster_ENH.Warehouse;

-- SalesHistory_ENH -> SalesHistory_Enh
ALTER SCHEMA SalesHistory_Enh TRANSFER SalesHistory_ENH.ActualDemandMonthly;
ALTER SCHEMA SalesHistory_Enh TRANSFER SalesHistory_ENH.ActualDemandWeekly;
ALTER SCHEMA SalesHistory_Enh TRANSFER SalesHistory_ENH.InvoiceDetailLineLevel;
ALTER SCHEMA SalesHistory_Enh TRANSFER SalesHistory_ENH.InvoiceWeekly;

-- ForecastHistory_ENH -> ForecastHistory_Enh
ALTER SCHEMA ForecastHistory_Enh TRANSFER ForecastHistory_ENH.ForecastDemandMonthly;
ALTER SCHEMA ForecastHistory_Enh TRANSFER ForecastHistory_ENH.NaiveForecastMonthly;

-- OpenOrderHistory_ENH -> OpenOrderHistory_Enh
ALTER SCHEMA OpenOrderHistory_Enh TRANSFER OpenOrderHistory_ENH.OpenOrderLineLevel;
ALTER SCHEMA OpenOrderHistory_Enh TRANSFER OpenOrderHistory_ENH.OpenOrderMonthly;

