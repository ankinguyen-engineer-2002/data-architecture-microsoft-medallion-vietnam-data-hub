-- Source: SupplyChain_Warehouse.SCP_Core_Wrk.v_DimWarehouseMaster
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.

CREATE         VIEW [SCP_Core_Wrk].[v_DimWarehouseMaster] AS (
SELECT RTRIM(S.[WarehouseCode]) AS [Warehouse Code]
      ,RTRIM(S.[WarehouseLocation]) AS [Warehouse Location]
      ,CASE RTRIM(S.[WarehouseCode])
           WHEN '1' THEN '1-RKD'
           WHEN '15' THEN '15-LEE'
           WHEN '17' THEN '17-ADV'
           WHEN '28' THEN '28-MES'
           WHEN '42' THEN '42-SPW'
           WHEN '5' THEN '5-RED'
           WHEN 'ECR' THEN 'ECR-ECR'
           WHEN '335' THEN '335-ASH'
           WHEN 'C' THEN 'C-ENT'
           WHEN 'CNW' THEN 'CNW-CUS'
           WHEN 'C35' THEN 'C35-ASH'
           WHEN 'AF' THEN 'AF-CND'
           WHEN 'C99' THEN 'C99-CND'
           WHEN 'IOR' THEN 'IOR-CND'
           WHEN '12' THEN '12-RIP'
           WHEN '101' THEN '101-CHP'
           WHEN '151' THEN '151-POT'
           WHEN '19' THEN '19-SLT'
           WHEN '201' THEN '201-VRM'
           WHEN '20' THEN '20-VRF'
           WHEN '3' THEN '3-WHT'
           WHEN '49' THEN '49-COL'
           WHEN '55' THEN '55-SDS'
           WHEN '1A' THEN '1-RKD'
           WHEN '15A' THEN '15-LEE'
           WHEN '17A' THEN '17-ADV'
           WHEN '28A' THEN '28-MES'
           WHEN '42A' THEN '42-SPW'
           WHEN '5A' THEN '5-RED'
           WHEN 'ECA' THEN 'ECR-ECR'
           WHEN '19A' THEN '19-SLT'
           ELSE NULL
       END AS [WH Desc]
      ,CASE RTRIM(S.[WarehouseCode])
           WHEN '1' THEN 'AFI'
           WHEN '15' THEN 'AFI'
           WHEN '17' THEN 'AFI'
           WHEN '28' THEN 'AFI'
           WHEN '42' THEN 'AFI'
           WHEN '5' THEN 'AFI'
           WHEN 'ECR' THEN 'AFI'
           WHEN '335' THEN 'ASH'
           WHEN 'C' THEN 'C.DIR'
           WHEN 'CNW' THEN 'C.DIR'
           WHEN 'C35' THEN 'C.DIR'
           WHEN 'AF' THEN 'C.DIR'
           WHEN 'C99' THEN 'C.DIR'
           WHEN 'IOR' THEN 'C.DIR'
           WHEN '12' THEN 'PROD'
           WHEN '101' THEN 'PROD'
           WHEN '151' THEN 'PROD'
           WHEN '19' THEN 'PROD'
           WHEN '201' THEN 'PROD'
           WHEN '20' THEN 'PROD'
           WHEN '3' THEN 'PROD'
           WHEN '49' THEN 'CXD'
           WHEN '55' THEN 'SDS'
           WHEN '1A' THEN 'AFI'
           WHEN '15A' THEN 'AFI'
           WHEN '17A' THEN 'AFI'
           WHEN '28A' THEN 'AFI'
           WHEN '42A' THEN 'AFI'
           WHEN '5A' THEN 'AFI'
           WHEN 'ECA' THEN 'AFI'
           WHEN '19A' THEN 'AFI'
           ELSE NULL
       END AS [WH Group]
      ,CONCAT(RTRIM(S.[WarehouseCode]),' - ', S.[WarehouseLocation]) AS [Warehouse Name]
      --,S.[WarehouseOrderGroup]
      ,RTRIM(S.[IntransitWarehouse]) AS [IntransitWarehouse]
      --,S.[ContainerDirectWarehouse]
      --,S.[ControlledWarehouse]
      --,S.[AFIWarehousesKey]	 
  FROM [Enterprise_Lakehouse].[SupplyChain_DW].[DimAFIWarehouses] AS S
  WHERE [S].[WarehouseCode] NOT IN ('', '10','109','14','16','18','2','21','213','215','232','242','50','52','55','6','60','7','70','8','9','N/A','P','R','W') 

  )