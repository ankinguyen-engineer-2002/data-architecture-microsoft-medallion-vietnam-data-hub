CREATE VIEW ReferenceMaster_ENH.vw_CustomerAccountGroup AS
SELECT TRIM(CustomerNumber) AS Customer, UPPER(TRIM(CustomerGroup)) AS CustomerGroupCode,
    TRIM(CustomerGroupLevel3) AS CustomerGroupLevel3Code, TRIM(BusinessTypeCode) AS BusinessTypeCode
FROM Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping