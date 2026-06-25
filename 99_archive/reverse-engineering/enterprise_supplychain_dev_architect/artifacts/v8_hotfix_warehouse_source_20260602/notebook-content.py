# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {
# META     "lakehouse": {
# META       "default_lakehouse": "62a3081e-4093-4f46-856c-f50aa58732fa",
# META       "default_lakehouse_name": "SupplyChain_Lakehouse",
# META       "default_lakehouse_workspace_id": "c8d9fc83-18b6-4e1d-8264-0b49eed36fe0",
# META       "known_lakehouses": [
# META         {
# META           "id": "62a3081e-4093-4f46-856c-f50aa58732fa"
# META         },
# META         {
# META           "id": "584e7d2c-46ca-49dc-bb6c-68df6ef4f424"
# META         }
# META       ]
# META     }
# META   }
# META }

# CELL ********************

TARGET_TABLE  = "ref_warehouse"
SOURCE_TABLE  = "CustomerOrders_AFI/WarehouseMaster"

COLUMN_SQL = """
    WITH source_clean AS (
        SELECT
            TRIM(Warehouse)              AS code_warehouse,
            TRIM(IntransitWarehouse)     AS code_intransit_warehouse,
            TRIM(ContainerDirectWhse)    AS code_container_direct,
            CAST(Controlled AS INT)      AS is_controlled_warehouse,
            TRIM(WarehouseOrderGroup)    AS name_warehouse_order_group,
            CAST(LocationID AS INT)      AS source_location_id
        FROM raw_source
        WHERE Warehouse IS NOT NULL
    ),
    legacy_shim AS (
        SELECT * FROM source_clean
        UNION ALL
        SELECT
            'N/A' AS code_warehouse,
            ''    AS code_intransit_warehouse,
            ''    AS code_container_direct,
            0     AS is_controlled_warehouse,
            ''    AS name_warehouse_order_group,
            1     AS source_location_id
        WHERE NOT EXISTS (SELECT 1 FROM source_clean WHERE code_warehouse = 'N/A')
        UNION ALL
        SELECT
            '' AS code_warehouse,
            '' AS code_intransit_warehouse,
            '' AS code_container_direct,
            0  AS is_controlled_warehouse,
            '' AS name_warehouse_order_group,
            2  AS source_location_id
        WHERE NOT EXISTS (SELECT 1 FROM source_clean WHERE code_warehouse = '')
    )
    SELECT
        CAST(CASE code_warehouse
            WHEN 'N/A' THEN 1
            WHEN '' THEN 2
            WHEN '1' THEN 3
            WHEN '10' THEN 4
            WHEN '101' THEN 5
            WHEN '109' THEN 6
            WHEN '12' THEN 7
            WHEN '14' THEN 8
            WHEN '15' THEN 9
            WHEN '151' THEN 10
            WHEN '15A' THEN 11
            WHEN '16' THEN 12
            WHEN '17' THEN 13
            WHEN '17A' THEN 14
            WHEN '18' THEN 15
            WHEN '19' THEN 16
            WHEN '19A' THEN 17
            WHEN '1A' THEN 18
            WHEN '2' THEN 19
            WHEN '20' THEN 20
            WHEN '201' THEN 21
            WHEN '21' THEN 22
            WHEN '213' THEN 23
            WHEN '215' THEN 24
            WHEN '232' THEN 25
            WHEN '242' THEN 26
            WHEN '28' THEN 27
            WHEN '28A' THEN 28
            WHEN '3' THEN 29
            WHEN '335' THEN 30
            WHEN '42' THEN 31
            WHEN '42A' THEN 32
            WHEN '49' THEN 33
            WHEN '5' THEN 34
            WHEN '50' THEN 35
            WHEN '52' THEN 36
            WHEN '55' THEN 37
            WHEN '5A' THEN 38
            WHEN '6' THEN 39
            WHEN '60' THEN 40
            WHEN '7' THEN 41
            WHEN '70' THEN 42
            WHEN '8' THEN 43
            WHEN '9' THEN 44
            WHEN 'AF' THEN 45
            WHEN 'C' THEN 46
            WHEN 'C35' THEN 47
            WHEN 'C99' THEN 48
            WHEN 'CNW' THEN 49
            WHEN 'ECA' THEN 50
            WHEN 'ECR' THEN 51
            WHEN 'IOR' THEN 52
            WHEN 'P' THEN 53
            WHEN 'R' THEN 54
            WHEN 'W' THEN 55
            ELSE source_location_id
        END AS INT)                              AS sk_warehouse,
        code_warehouse                           AS code_warehouse,
        code_intransit_warehouse                 AS code_intransit_warehouse,
        code_container_direct                    AS code_container_direct,
        is_controlled_warehouse                  AS is_controlled_warehouse,
        CAST(CASE code_warehouse
            WHEN 'N/A' THEN ''
            WHEN '' THEN 'UNDEFINED'
            WHEN '1' THEN 'ARCADIA'
            WHEN '10' THEN 'DO NOT USE - SEATTLE'
            WHEN '101' THEN 'CHIPPEWA FALLS WI'
            WHEN '109' THEN 'ASHLEY MAKERS CENTER'
            WHEN '12' THEN 'RIPLEY'
            WHEN '14' THEN 'DO NOT USE - DIAMOND'
            WHEN '15' THEN 'LEESPORT PA'
            WHEN '151' THEN 'POTTSVILLE PA'
            WHEN '15A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '16' THEN 'STATESVILLE'
            WHEN '17' THEN 'ADVANCE NC'
            WHEN '17A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '18' THEN 'DO NOT USE - VERONA'
            WHEN '19' THEN 'SALTILLO'
            WHEN '19A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '1A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '2' THEN 'OFF-SITE STORAGE LOCATION'
            WHEN '20' THEN 'VERONA FOAM PLANT'
            WHEN '201' THEN 'VERONA PLANT 4'
            WHEN '21' THEN 'WANVOG WAREHOUSE 21'
            WHEN '213' THEN 'MEMPHIS 3PL'
            WHEN '215' THEN 'NEW JERSEY 3PL'
            WHEN '232' THEN 'ASHLEY FURNITURE 232'
            WHEN '242' THEN 'TACOMA 3PL'
            WHEN '28' THEN 'MESQUITE'
            WHEN '28A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '3' THEN 'WHITEHALL'
            WHEN '335' THEN 'ASHTON FURNITURE LLC'
            WHEN '42' THEN 'SPANAWAY WA'
            WHEN '42A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '49' THEN 'COLTON XD'
            WHEN '5' THEN 'REDLANDS'
            WHEN '50' THEN 'LYNWOOD 3PL'
            WHEN '52' THEN 'CARSON 3PL'
            WHEN '55' THEN '3RD PARTY WAREHOUSE'
            WHEN '5A' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN '6' THEN 'DO NOT USE - NEW JERSEY'
            WHEN '60' THEN 'TOLLESON AZ'
            WHEN '7' THEN 'DO NOT USE - PT. RICHMOND'
            WHEN '70' THEN 'ETNA OHIO'
            WHEN '8' THEN 'DO NOT USE - FLORIDA'
            WHEN '9' THEN 'DO NOT USE - BOSTON'
            WHEN 'AF' THEN 'AF - CONTAINER DIRECT'
            WHEN 'C' THEN 'CONTAINER DIRECT'
            WHEN 'C35' THEN 'ASHTON CONTAINER DIRECT'
            WHEN 'C99' THEN 'CONTAINER DIRECT'
            WHEN 'CNW' THEN 'CNW - CONTAINER DIRECT'
            WHEN 'ECA' THEN 'RH/AFI VIRTUAL WAREHOUSE'
            WHEN 'ECR' THEN 'ECRU'
            WHEN 'IOR' THEN 'IOR - CONTAINER DIRECT'
            WHEN 'P' THEN 'ARCADIA - REPLACEMENT PARTS'
            WHEN 'R' THEN 'DISCONTINUED PRODUCT'
            WHEN 'W' THEN 'WHITEHALL IN TRANSIT'
            ELSE name_warehouse_order_group
        END AS STRING)                            AS name_warehouse_location,
        name_warehouse_order_group                AS name_warehouse_order_group,
        CAST(CASE code_warehouse
            WHEN 'N/A' THEN 0
            WHEN '' THEN 0
            WHEN '1' THEN 1
            WHEN '10' THEN 0
            WHEN '101' THEN 1
            WHEN '109' THEN 1
            WHEN '12' THEN 1
            WHEN '14' THEN 0
            WHEN '15' THEN 1
            WHEN '151' THEN 1
            WHEN '15A' THEN 1
            WHEN '16' THEN 1
            WHEN '17' THEN 1
            WHEN '17A' THEN 1
            WHEN '18' THEN 0
            WHEN '19' THEN 1
            WHEN '19A' THEN 1
            WHEN '1A' THEN 1
            WHEN '2' THEN 0
            WHEN '20' THEN 1
            WHEN '201' THEN 1
            WHEN '21' THEN 0
            WHEN '213' THEN 1
            WHEN '215' THEN 1
            WHEN '232' THEN 1
            WHEN '242' THEN 1
            WHEN '28' THEN 1
            WHEN '28A' THEN 1
            WHEN '3' THEN 1
            WHEN '335' THEN 1
            WHEN '42' THEN 1
            WHEN '42A' THEN 1
            WHEN '49' THEN 1
            WHEN '5' THEN 1
            WHEN '50' THEN 1
            WHEN '52' THEN 1
            WHEN '55' THEN 0
            WHEN '5A' THEN 1
            WHEN '6' THEN 0
            WHEN '60' THEN 1
            WHEN '7' THEN 0
            WHEN '70' THEN 1
            WHEN '8' THEN 0
            WHEN '9' THEN 0
            WHEN 'AF' THEN 1
            WHEN 'C' THEN 0
            WHEN 'C35' THEN 1
            WHEN 'C99' THEN 0
            WHEN 'CNW' THEN 0
            WHEN 'ECA' THEN 1
            WHEN 'ECR' THEN 1
            WHEN 'IOR' THEN 1
            WHEN 'P' THEN 0
            WHEN 'R' THEN 0
            WHEN 'W' THEN 0
            ELSE CASE WHEN is_controlled_warehouse = 1 THEN 1 ELSE 0 END
        END AS INT)                               AS is_finance_inventory_report
    FROM legacy_shim
"""

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }

# CELL ********************

notebookutils.notebook.run(
    "brz_engine",
    7200,
    {
        "TARGET_TABLE": TARGET_TABLE,
        "SOURCE_TABLE": SOURCE_TABLE,  
        "COLUMN_SQL":   COLUMN_SQL
    }
)

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
