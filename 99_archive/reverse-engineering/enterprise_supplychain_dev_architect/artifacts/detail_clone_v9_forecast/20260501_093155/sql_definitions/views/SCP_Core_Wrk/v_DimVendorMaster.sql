-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimVendorMaster
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE   VIEW [SCP_CORE_WRK].[v_DimVendorMaster] AS (

/****** SCP_Core.DimVendorMaster ******/

SELECT V.VendorNumber
	  ,V.VendorName
	  ,V.[Office]
      ,[VendorOfficeLocation] = 
			CASE 
				WHEN V.[Office] = 'ACROS' THEN 'CHINA'
				WHEN V.[Office] = 'AMLO' THEN 'MALAYSIA'
				WHEN V.[Office] = 'CINRO' THEN 'INDIA'
				WHEN V.[Office] = 'CVRO' THEN 'VIETNAM'
				WHEN V.[Office] = 'RKD' THEN 'USA'
				WHEN V.[Office] = 'WBOC' THEN 'CHINA'
				WHEN V.[Office] = 'ACLO' THEN 'CAMBODIA'
				WHEN V.[Office] = 'ABLO' THEN 'BANGLADESH'
				WHEN V.[Office] = 'THAI' THEN 'THAILAND'
				WHEN V.[Office] = 'MYAN' THEN 'MAYANMAR'
				WHEN V.[Office] = 'ATLO' THEN 'TAIWAN R.O.C'
				WHEN V.[Office] = 'CIRO' THEN 'INDONESIA'
				WHEN V.[Office] = 'CANA' THEN 'CANADA'
				WHEN V.[Office] = 'MXCO' THEN 'MEXICO'
				WHEN V.[Office] = 'MILLE' THEN 'VIETNAM'
				WHEN V.[Office] = 'WANEK' THEN 'VIETNAM'
				WHEN V.[Office] = 'LAOS' THEN 'LAOS'
				WHEN V.[Office] = 'SGPR' THEN 'SINGAPORE'
				WHEN V.[Office] = 'SLKA' THEN 'SRI LANKA'
				WHEN V.[Office] = 'TRKY' THEN 'TURKEY'

				ELSE 'N/A'
			END				
	  ,V.[VendorDesc]
	  ,V.Country
	  ,A.[LEAD_TIME] AS [LeadTime] 
	  ,[VendorActive] = 
			CASE
				WHEN [A].[Active] = '1'
					THEN 'Yes'
				ELSE 'No'
			END
	  ,[Vendor Import Domestic Flag] = 
			CASE 
				WHEN [A].[ProductOrigin] = 'I' OR [A].[ProductOrigin] IS NULL THEN 'Import'
				WHEN [A].[ProductOrigin] = 'D' THEN 'Domestic'
				ELSE 'N/A'
			END
FROM (

SELECT RTRIM(V.[VNDNR]) AS [VendorNumber]
		,RTRIM(V.[VNAME]) AS [VendorName]
		,V.[VNAMA] AS [Office]
		,CONCAT(RTRIM(V.[VNAME]),' - ',RTRIM(V.[VNDNR])) AS [VendorDesc]
		,V.[VCNTR] AS [Country]
	FROM [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[VENNAM] AS V
	WHERE [VNAMA] IN ('ACROS','AMLO','CINRO','CVRO','RKD','WBOC','ACLO'
                      ,'ABLO','THAI','MYAN', 'ATLO', 'CANA', 'CIRO','MXCO'
					  ,'MILLE', 'WANEK','LAOS','SLKA','SGPR','TRKY'
					  )


	) AS V
	LEFT JOIN [Enterprise_Lakehouse].[Wholesale_Purchasing_AFI].[EXTVNDR] AS A
	 ON V.VendorNumber = A.[VEND_NUM]

	 )