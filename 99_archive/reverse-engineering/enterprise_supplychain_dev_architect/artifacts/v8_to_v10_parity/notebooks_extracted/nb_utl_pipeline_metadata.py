# ─── Cell 0 ───
# spark.sql("""
#     CREATE TABLE IF NOT EXISTS SupplyChain_Lakehouse.dbo.utl_pipeline_metadata (
#         table_name            STRING,
#         last_watermark_value  STRING,
#         last_load_date        TIMESTAMP,
#         rows_loaded           LONG,
#         rows_rejected         LONG,
#         status                STRING,
#         error_message         STRING,
#         pipeline_notes        STRING
#     )
#     USING DELTA
# """)

# print("Done! utl_pipeline_metadata created.")

# ─── Cell 1 ───
df = spark.sql("""
    SELECT MAX(dfcSnapshot) AS max_wm
    FROM SupplyChain_Lakehouse.dbo.brz_SupplyChain_Enh_1__DemandForecastSnapshotDaily
""")

display(df)

# ─── Cell 2 ───
# Lấy max watermark từ bảng đã load sẵn
result = spark.sql("""
    SELECT MAX(dfcSnapshot) AS max_wm
    FROM SupplyChain_Lakehouse.dbo.brz_SupplyChain_Enh_1__DemandForecastSnapshotDaily
""").collect()

max_wm = result[0]["max_wm"]
print(f"Max watermark hiện tại: {max_wm}")

# Insert record vào metadata
spark.sql(f"""
    INSERT INTO SupplyChain_Lakehouse.dbo.utl_pipeline_metadata
    VALUES (
        'brz_SupplyChain_Enh_1__DemandForecastSnapshotDaily',
        '{max_wm}',
        current_timestamp(),
        NULL,
        0,
        'success',
        NULL,
        'Seeded manually - full load done before pipeline setup'
    )
""")

print(f"Done! Watermark seeded: {max_wm}")

