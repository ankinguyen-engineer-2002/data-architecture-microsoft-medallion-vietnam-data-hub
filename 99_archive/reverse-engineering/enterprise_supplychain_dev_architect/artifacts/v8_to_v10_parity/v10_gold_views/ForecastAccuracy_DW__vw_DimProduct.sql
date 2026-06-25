
CREATE VIEW ForecastAccuracy_DW.vw_DimProduct AS
SELECT *, CAST(GETUTCDATE() AS DATETIME2(6)) AS LoadDT
FROM SupplyChain_Processing_Warehouse.Staging_WRK.ProductEdw
