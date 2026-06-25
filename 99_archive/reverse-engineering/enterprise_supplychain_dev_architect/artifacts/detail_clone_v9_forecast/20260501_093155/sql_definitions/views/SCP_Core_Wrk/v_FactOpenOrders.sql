-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_FactOpenOrders
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE           VIEW [SCP_CORE_WRK].[v_FactOpenOrders] AS (
SELECT  cast(str(CASE WHEN T3.ORDTE=0 Then 19990101 Else T3.ORDTE End) AS date)  as [OrderTakenDate],
        T1.[Ordno] AS [OrderNumber], 
        T1.[itmsq] AS [ItemSequenceNumber],
        T1.CCusno as [AccountNumber], 
        T1.CSHPNO as  [ShipToNumber],
        RTRIM(CASE 
            WHEN T1.CSHPNO IS NULL OR CAST(T1.CSHPNO AS VARCHAR(50)) = ''
                THEN CAST(T1.CCusno AS VARCHAR(50))
            ELSE
                RTRIM(CAST(T1.CCusno AS VARCHAR(50))) + '-' + LTRIM(CAST(T1.CSHPNO AS VARCHAR(50)))
            END) AS [Account And ShipTo Number], 
        --C.[Store Address ID] as idsStoreAddressID,
        --C.[Shipto AddressID] as idsRouteAddressID, 
		--[M].[City],
		--[M].[State Code],
		--[M].[Country Code],
	    RTRIM(T1.Itnbr) as [ItemSKU], 
		--AFISalesDivisionCode as  idsDivision, 
		--M.[Msa Fips Code] as idsMsaFips,
		RTRIM(T1.HOUSE) as [Warehouse]	,	
		[IM].AFIItemStatus as [ItemStatus],
		 CAST(T1.COQTY - T1.Qtysh AS INT) as [OpenOrderQty],
		 CAST(T1.QTYBO AS INT) as [BackOrderQty],
		--((T1.INSAM/case when T1.QTYBO > 0 then T1.QTYBO else T1.COQTY end) - T2.IFRGHT) * case when T1.QTYBO > 0 then T1.QTYBO else T1.COQTY end as idsOpenOrderAmt, 
		CAST(((T1.INSAM/
            CASE 
                WHEN T1.QTYBO > 0 
                    THEN T1.QTYBO 
                ELSE (CASE 
                            WHEN T1.COQTY > 0 
                                THEN T1.COQTY 
                            ELSE 1 
                        END)
                END) - T2.IFRGHT) 
                * CASE 
                        WHEN T1.QTYBO > 0 
                            THEN T1.QTYBO
                    ELSE (CASE 
                            WHEN T1.COQTY > 0 
                                THEN  T1.COQTY 
                            ELSE 1 
                          END) 
                    END AS DEC(13,2)
            ) AS [OpenOrderAmt],
		CAST(Case when T1.QTYBO > 0 Then ((T1.INSAM/T1.QTYBO) - T2.IFRGHT) * T1.QTYBO else 0 END AS DEC(13,2)) as [BackOrderAmt], 
		 T4.ORDARR as [OrderArrival],
		 cast(str(CASE WHEN T2.Iprmdt=0 Then NULL Else T2.Iprmdt End) AS date) as [OriginalPromiseDate],
		 cast(str(CASE WHEN T1.Rqidt=0  Then NULL Else T1.Rqidt  End) AS date) as [CurrentPromiseDate],
		 cast(str(CASE WHEN T4.Frzdat=0 Then NULL Else T4.Frzdat End) AS date) as [OriginalRequestDate],
		 cast(str(CASE WHEN T4.Rqsdat=0 Then NULL Else T4.Rqsdat End) AS date) as [CurrentRequestDate],
		[PrimaryOrderType]=  OT1.OTDES1,
		[SecondaryOrderType]= OT2.OTDES1,
		[3rdOrderType]=OT3.OTDES1,
		[4thOrderType]=OT4.OTDES1,
		T1.[IAFLG] AS [InventoryAllocatedFlag],
		cast(str(CASE WHEN T1.MFIDT=0  Then NULL Else T1.MFIDT  End) AS date) AS [CurrentLoadDate],
		T1.[NUMLDDTCHG] AS [CountofLoadDateChanges],
		T3.[SHLTC] AS [LoadLeadTime],
		T3.[SHINS] AS [ShippingInstructions],
		case T1.itdsi  when T1.itdsc then '' else T1.itdsi end as [CustomerSKUNo],
		--C.[Account Exception Flag],
		 T2.IFRGHT as [OrderFreight]
		,CASE 
            WHEN DATEADD(DAY, 7, cast(str(CASE WHEN T4.Rqsdat=0 Then NULL Else T4.Rqsdat End) AS date)) < CONVERT(DATE, GETDATE())
                THEN 'Past Due'
            ELSE 'Future Ord'
        END AS [FlagPastDue]
		-- ST.[RegionCode_RepID_Category] as [RegionCode_RepID_Cat]
  FROM  [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[codatan] AS T1 
        LEFT JOIN  [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[EXTORIT] AS T2  
          ON (T1.ORDNO = T2.IORD AND T1.ITMSQ = T2.ISEQ)
		JOIN [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[COMAST]AS T3   
          ON (T1.ORDNO = T3.ORDNO)
		JOIN [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[EXTORD] AS T4  
          ON (T1.ORDNO = T4.XORDNO)
        --LEFT Join AFISales_DW.DimCustomers C  on C.[Customer Account Number] = T1.CCusno AND  C.[Customer Shipto Number]=T1.CSHPNO		
        --LEFT JOIN AFISales_DW.DimGeographicLocations M ON [Shipto AddressID] = [Address ID]
        JOIN [Enterprise_Lakehouse].[MasterData_DW].[DimItemMaster] AS IM 
          ON ItemSku=T1.Itnbr
	    Left Join [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AAORDTYP] AS ot1  
          ON ot1.OTCODE=T4.[OTTYP1]
	    Left Join [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AAORDTYP] AS ot2  
          ON ot2.OTCODE=T4.[OTTYP2]
		Left Join [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AAORDTYP] AS ot3  
          ON ot3.OTCODE=T4.[OTTYP3]
		Left JOIN [Enterprise_Lakehouse].[Wholesale_Codis_AFI].[AAORDTYP] AS ot4  
          ON ot4.OTCODE=T4.[OTTYP4]

  WHERE (T1.QTYBO <> 0 or T1.COQTY <> 0) and Price <> 0 and T3.ACREC <> 'X' AND T1.COQTY >= 0
  )