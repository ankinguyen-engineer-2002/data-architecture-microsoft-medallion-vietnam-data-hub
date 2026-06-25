# ─── Cell 0 ───
TARGET_TABLE = "ref_order_type"
SOURCE_TABLE = "Wholesale_Codis_AFI/AAORDTYP"

COLUMN_SQL = """
    SELECT
        TRIM(OTCODE)                                    AS code_order_type,
        TRIM(OTDES1)                                    AS name_order_type,
        TRIM(OTDES2)                                    AS name_order_type_short,
        TRIM(OORDCL)                                    AS code_order_class,
        CAST(OOTCAT AS INT)                             AS num_order_category,
        CASE WHEN TRIM(OROUTE) = 'Y' THEN true ELSE false END    AS is_route_eligible,
        CASE WHEN TRIM(OADCHG) = 'Y' THEN true ELSE false END    AS is_additional_charge,
        CASE WHEN TRIM(OARFLG) = 'Y' THEN true ELSE false END    AS is_auto_replenish,
        CASE WHEN TRIM(OWNEXP) = 'Y' THEN true ELSE false END    AS is_will_notify_expedite,
        CASE WHEN TRIM(OMINEXC) = 'Y' THEN true ELSE false END   AS is_minimum_exception,
        TRIM(OREQMNT)                                  AS code_requirement_type,
        CASE WHEN TRIM(OFDESCH) = 'Y' THEN true ELSE false END   AS is_force_delivery_schedule,
        CASE WHEN TRIM(OFDRIMS) = 'Y' THEN true ELSE false END   AS is_force_delivery_rims,
        TRIM(OTRPTYP)                                   AS code_transport_type,
        CAST(OZNLTIM AS INT)                            AS num_zone_lead_time_days,
        CASE WHEN TRIM(OSPECHND) = 'Y' THEN true ELSE false END  AS is_special_handling,
        CASE WHEN TRIM(OAUTORSCH) = 'Y' THEN true ELSE false END AS is_auto_reschedule,
        CASE WHEN TRIM(OUSRDFN) = 'Y' THEN true ELSE false END   AS is_user_defined,
        TRIM(OTUSER)                                    AS name_modified_by,
        to_date(CAST(OTDATE AS STRING), 'yyyyMMdd')     AS dt_modified
    FROM raw_source
    WHERE OTCODE IS NOT NULL
"""

# ─── Cell 1 ───
notebookutils.notebook.run(
    "brz_engine",
    7200,
    {
        "TARGET_TABLE": TARGET_TABLE,
        "SOURCE_TABLE": SOURCE_TABLE,
        "COLUMN_SQL":   COLUMN_SQL
    }
)

