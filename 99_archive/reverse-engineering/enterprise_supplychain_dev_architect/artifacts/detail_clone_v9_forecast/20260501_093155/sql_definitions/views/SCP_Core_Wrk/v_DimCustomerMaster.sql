-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimCustomerMaster
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE         VIEW [SCP_Core_Wrk].[v_DimCustomerMaster] AS (

-- SCP_Core_Wrk.[DimCustomerMaster]
SELECT RTRIM([CSL].[cslCustomerNumber]) AS [Account Number]
      ,RTRIM([CSL].[cslShiptoNumber]	) AS [ShipTo Number]
	  ,[CMA].[cmaCustomerName] AS [Customer Name]
	  ,[CSL].[cslName] AS [ShipTo Name]
      ,TRIM(Case When [CSL].[cslShiptoNumber] is Null or [CSL].[cslShiptoNumber] = ''
		Then [CSL].[cslCustomerNumber]
	Else
		RTRIM(cslCustomerNumber) + '-' + LTRIM(cslShiptoNumber)End)  as [Account And ShipTo Number]
      ,[CSL].[cslCommissionCode] AS [Commission Code]
	  ,[CSL].[cslFreightCode] AS [Freight Code]
	  ,[CSL].[cslPriceCode] AS [Price Code]
	  ,[CSL].[cslDefaultWarehouse] AS [Default Warehouse]
	  ,RTRIM([CSL].[csmshpa3]) AS [ShipTo City]
	  ,RTRIM([CSL].[csmshpst]) AS [ShipTo State]
	  ,RTRIM([CSL].[csmshpco]) AS [ShipTo Country]
	  ,[CSL].[cslBusinessType] AS [Business Type Code]
	  -- waiting for [Wholesale_Marketing].[BusinessType]
	      --,RTRIM(isnull(btyBtdesc,'')) as [Business Type]
	      --,btyRptBusType as [Reporting Business Type]
	  ,CASE 
        WHEN [CSL].[cslBusinessType] = '  ' THEN 'Unassigned'
        WHEN [CSL].[cslBusinessType] = '0A' THEN 'Other'
        WHEN [CSL].[cslBusinessType] = '1A' THEN 'Primary'
        WHEN [CSL].[cslBusinessType] = '1C' THEN 'Corporate Online Selling'
        WHEN [CSL].[cslBusinessType] = '1D' THEN 'e-Retail'
        WHEN [CSL].[cslBusinessType] = '1E' THEN 'Ashley Home Stores'
        WHEN [CSL].[cslBusinessType] = '1F' THEN 'Marketing Specialist'
        WHEN [CSL].[cslBusinessType] = '1G' THEN 'Interior Design'
        WHEN [CSL].[cslBusinessType] = '1H' THEN 'Hybrid - Homestore and Primary'
        WHEN [CSL].[cslBusinessType] = '2A' THEN 'RTA / Unfinished'
        WHEN [CSL].[cslBusinessType] = '2S' THEN 'Sleep Shops'
        WHEN [CSL].[cslBusinessType] = '3A' THEN 'International Primary'
        WHEN [CSL].[cslBusinessType] = '3B' THEN 'Distributors'
        WHEN [CSL].[cslBusinessType] = '3C' THEN 'International Homestore'
        WHEN [CSL].[cslBusinessType] = '3D' THEN 'International Rental'
        WHEN [CSL].[cslBusinessType] = '3E' THEN 'International Distributor'
        WHEN [CSL].[cslBusinessType] = '3F' THEN 'International e-Retail'
        WHEN [CSL].[cslBusinessType] = '4A' THEN 'Government'
        WHEN [CSL].[cslBusinessType] = '4B' THEN 'Warehouse Clubs'
        WHEN [CSL].[cslBusinessType] = '4C' THEN 'Employee Incentive Programs'
        WHEN [CSL].[cslBusinessType] = '5A' THEN 'Mail Order Catalogs'
        WHEN [CSL].[cslBusinessType] = '6A' THEN 'Rental'
        WHEN [CSL].[cslBusinessType] = '7A' THEN 'Mass Merchants'
        WHEN [CSL].[cslBusinessType] = '8A' THEN 'Decorators'
        WHEN [CSL].[cslBusinessType] = '9A' THEN 'GOB Accounts'
        ELSE 'Other'
    END AS [Business Type],
    CASE 
        WHEN [CSL].[cslBusinessType] = '  ' THEN 'Other'
        WHEN [CSL].[cslBusinessType] IN ('0A') THEN 'Other'
        WHEN [CSL].[cslBusinessType] IN ('1A', '1F', '1G', '1H', '2A', '2S', '3B', '4A', '4B', '5A', '8A', '9A') THEN 'Primary'
        WHEN [CSL].[cslBusinessType] IN ('1C', '1E', '4C') THEN 'Ashley HomeStores'
        WHEN [CSL].[cslBusinessType] = '1D' THEN 'e-Retail'
        WHEN [CSL].[cslBusinessType] IN ('3A', '3C', '3D', '3E', '3F') THEN 'International'
        WHEN [CSL].[cslBusinessType] = '6A' THEN 'Rental'
        WHEN [CSL].[cslBusinessType] = '7A' THEN 'Mass Merchants'
        ELSE 'Other'
    END AS [Reporting Business Type]
	  ,CASE 
			-- Waiting on CustomerGrouping in Bronze
			WHEN [CG].[CustomerGroup] IS NOT NULL
			  THEN [CG].[CustomerGroup]
			WHEN [CSL].[cslCustomerNumber] = '6000100' THEN 'AFICONS' --SAMPLE ACCOUNT
			WHEN [CSL].[cslCustomerNumber] IN ('1913400','8888000','8888300','8888600','9946600','9955000','9955100','9956600','9966100','9974000','9977400','9983800','9985500','9989200')
				THEN 'HSENT'
			WHEN [CSL].[cslCustomerNumber] = '4444400' --ASHCOMM
				THEN 'HSENT' 
			WHEN [CSL].[cslBusinessType] IN ('1C','1E','4C') --'Ashley HomeStores'
					AND [CSL].[cslCommissionCode] <> '006'
				THEN 'HSLIC'
			WHEN [CSL].[cslBusinessType] = '1H'-- = 'Hybrid - Homestore and Primary'
				THEN 'HSLIC'
			WHEN [CSL].[cslCustomerNumber] = '109200'
				THEN 'NFM'
			WHEN [CSL].[cslCustomerNumber] = '3061700' --Payless in E-Retail should be AFICONS
				THEN 'AFICONS'
            WHEN [CSL].[cslBusinessType] = '1D' -- 'E-Retail'
				THEN 'ECOMM'
			WHEN [CSL].[cslBusinessType] = '6A' -- 'Rental'
				THEN 'MASSRENT'
			WHEN [CSL].[cslBusinessType] = '7A' -- 'Mass Merchants'
				THEN 'MASSRENT'
			WHEN [CSL].[cslBusinessType] IN ('3A','3C','3D','3E','3F') -- 'International'
				THEN 'INT'
--			WHEN [DC].[Customer Account Number] = '4031300'
--					AND [DC].[Customer Shipto Number] IN ('','1','15','17','28','42','5','ECR') 
--				THEN 'RHDTC'
--			WHEN [DC].[Customer Account Number] = '4031300'
--					AND [DC].[Customer Shipto Number] IN ('AM01','AM15','AM17','AM28','AM42','AM05','AMEC')
--				THEN 'RHAMZ'
--			WHEN [DC].[Customer Account Number] = '4031300'
--					AND [DC].[Customer Shipto Name] LIKE 'AMAZON.COM%'
--				THEN 'RHAMZ'
			WHEN [CSL].[cslCustomerNumber] = '4031300'
				THEN 'RHCUST'
			WHEN [CSL].[cslCustomerNumber] = '3824800'
				THEN 'AFI DIST'
			ELSE 'AFICONS'
		END AS [Customer Group]
	  ,CASE
			WHEN [CSL].[cslCustomerNumber] IN ('9946600','9955000','9966100','9981000'
			                                       ,'9977400','9985500','9955100','9956600'
									                           ,'9983800','9989200','9974000'
									                           )  -- DSG Accounts
				THEN 'AGR RED'
			WHEN [CSL].[cslCustomerNumber] IN ('8888300','8888400','8888000','8888600','1913400')
				THEN 'AGR YELL'
			WHEN [CSL].[cslCustomerNumber] = '4444400'
				THEN 'ASHCOMM'
			WHEN [CSL].[cslCustomerNumber] = '3824800'
				THEN 'AFI DIST'
			WHEN [CSL].[cslCustomerNumber] IN ('3804400','3671000','3586300','269400'
									  )  -- Aaron's Rental Accts
				THEN 'AARONS RENTAL'

			ELSE CONCAT(RTRIM([CMA].[cmaCustomerName]), ' - ', RTRIM([CSL].[cslCustomerNumber]))
		END AS [Account Group]
  FROM [Enterprise_Lakehouse].[Customers].[ShippingLocations] AS CSL
  LEFT JOIN [Enterprise_Lakehouse].[Customers].[AccountMaster]  AS CMA  
    ON [CMA].[cmaCustomerNumber] = [CSL].[cslCustomerNumber]
  LEFT JOIN [Enterprise_Lakehouse].[Wholesale_ProductSourcing_AFI].[CustomerGrouping] AS CG
    ON [CSL].[cslCustomerNumber] = [CG].[CustomerNumber]

UNION

SELECT 'AFICONS' AS [Account Number]
      ,'AFICONS' AS [ShipTo Number]
      ,'AFICONS' AS [Customer Name]
      ,'AFICONS' AS [ShipTo Name]
      ,'AFICONS' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'AFICONS' AS [Customer Group]
      ,'AFICONS' AS [Account Group]

UNION 

SELECT 'ECOMM' AS [Account Number]
      ,'ECOMM' AS [ShipTo Number]
      ,'ECOMM' AS [Customer Name]
      ,'ECOMM' AS [ShipTo Name]
      ,'ECOMM' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'ECOMM' AS [Customer Group]
      ,'ECOMM' AS [Account Group]

UNION 

SELECT 'HSENT' AS [Account Number]
      ,'HSENT' AS [ShipTo Number]
      ,'HSENT' AS [Customer Name]
      ,'HSENT' AS [ShipTo Name]
      ,'HSENT' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'HSENT' AS [Customer Group]
      ,'HSENT' AS [Account Group]

UNION 

SELECT 'HSLIC' AS [Account Number]
      ,'HSLIC' AS [ShipTo Number]
      ,'HSLIC' AS [Customer Name]
      ,'HSLIC' AS [ShipTo Name]
      ,'HSLIC' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'HSLIC' AS [Customer Group]
      ,'HSLIC' AS [Account Group]

UNION 

SELECT 'INT' AS [Account Number]
      ,'INT' AS [ShipTo Number]
      ,'INT' AS [Customer Name]
      ,'INT' AS [ShipTo Name]
      ,'INT' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'INT' AS [Customer Group]
      ,'INT' AS [Account Group]

UNION 

SELECT 'MASSRENT' AS [Account Number]
      ,'MASSRENT' AS [ShipTo Number]
      ,'MASSRENT' AS [Customer Name]
      ,'MASSRENT' AS [ShipTo Name]
      ,'MASSRENT' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'MASSRENT' AS [Customer Group]
      ,'MASSRENT' AS [Account Group]

UNION 

SELECT 'MFRM' AS [Account Number]
      ,'MFRM' AS [ShipTo Number]
      ,'MFRM' AS [Customer Name]
      ,'MFRM' AS [ShipTo Name]
      ,'MFRM' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'MFRM' AS [Customer Group]
      ,'MFRM' AS [Account Group]

UNION 

SELECT 'NFM' AS [Account Number]
      ,'NFM' AS [ShipTo Number]
      ,'NFM' AS [Customer Name]
      ,'NFM' AS [ShipTo Name]
      ,'NFM' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'NFM' AS [Customer Group]
      ,'NFM' AS [Account Group]

UNION 

SELECT 'RHCUST' AS [Account Number]
      ,'RHCUST' AS [ShipTo Number]
      ,'RHCUST' AS [Customer Name]
      ,'RHCUST' AS [ShipTo Name]
      ,'RHCUST' AS [Account And ShipTo Number]
      ,'' AS [Commission Code]
      ,'' AS [Freight Code]
      ,'' AS [Price Code]
      ,'' AS [Default Warehouse]
      ,'' AS [ShipTo City]
      ,'' AS [ShipTo State]
      ,'' AS [ShipTo Country]
      ,'' AS [Business Type Code]
      ,'' AS [Business Type]
      ,'' AS [Reporting Business Type]
      ,'RHCUST' AS [Customer Group]
      ,'RHCUST' AS [Account Group]


  )