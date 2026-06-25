-- Source: SupplyChain_Warehouse.bronze.vw_ref_order_type
-- Object type: VIEW
-- Exported read-only from sys.sql_modules.


CREATE   VIEW bronze.vw_ref_order_type AS
SELECT
    TRIM(OTCODE)                                    AS code_order_type,
    TRIM(OTDES1)                                    AS name_order_type,
    TRIM(OTDES2)                                    AS name_order_type_short,
    TRIM(OORDCL)                                    AS code_order_class,
    CAST(OOTCAT AS INT)                             AS num_order_category,
    CASE WHEN TRIM(OROUTE) = 'Y' THEN 1 ELSE 0 END    AS is_route_eligible,
    CASE WHEN TRIM(OADCHG) = 'Y' THEN 1 ELSE 0 END    AS is_additional_charge,
    CASE WHEN TRIM(OARFLG) = 'Y' THEN 1 ELSE 0 END    AS is_auto_replenish,
    CASE WHEN TRIM(OWNEXP) = 'Y' THEN 1 ELSE 0 END    AS is_will_notify_expedite,
    CASE WHEN TRIM(OMINEXC) = 'Y' THEN 1 ELSE 0 END   AS is_minimum_exception,
    TRIM(OREQMNT)                                  AS code_requirement_type,
    CASE WHEN TRIM(OFDESCH) = 'Y' THEN 1 ELSE 0 END   AS is_force_delivery_schedule,
    CASE WHEN TRIM(OFDRIMS) = 'Y' THEN 1 ELSE 0 END   AS is_force_delivery_rims,
    TRIM(OTRPTYP)                                   AS code_transport_type,
    CAST(OZNLTIM AS INT)                            AS num_zone_lead_time_days,
    CASE WHEN TRIM(OSPECHND) = 'Y' THEN 1 ELSE 0 END  AS is_special_handling,
    CASE WHEN TRIM(OAUTORSCH) = 'Y' THEN 1 ELSE 0 END AS is_auto_reschedule,
    CASE WHEN TRIM(OUSRDFN) = 'Y' THEN 1 ELSE 0 END   AS is_user_defined,
    TRIM(OTUSER)                                    AS name_modified_by,
    TRY_CONVERT(DATE, CAST(OTDATE AS VARCHAR(20)))  AS dt_modified
FROM Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP
WHERE OTCODE IS NOT NULL
