# ─── Cell 0 ───
TARGET_TABLE = "ref_forecast_horizon"

# ─── Cell 1 ───
import time
from datetime import datetime, timedelta

start_time = time.time()

# Write hardcode data
spark.sql("""
    CREATE OR REPLACE TABLE SupplyChain_Lakehouse.dbo.ref_forecast_horizon
    USING DELTA AS
    SELECT 'Lag-0'      AS code_horizon, 1 AS num_rank UNION ALL
    SELECT 'Lag-1',  2 UNION ALL
    SELECT 'Lag-2',  3 UNION ALL
    SELECT 'Lag-3',  4 UNION ALL
    SELECT 'Lag-4', 5 UNION ALL
    SELECT '>Lag-4',  6 UNION ALL
    SELECT 'Actual demand',  7 UNION ALL
    SELECT 'Naive forecast',  8
""")

duration_secs = round(time.time() - start_time)
record_count  = 8

# Update metadata
next_run = datetime.utcnow().date() + timedelta(days=1)
new_next_run = datetime(next_run.year, next_run.month, next_run.day, 2, 0, 0)

spark.sql(f"""
    UPDATE SupplyChain_Lakehouse.dbo.utl_pipeline_metadata SET
        last_load_date  = current_timestamp(),
        rows_loaded     = {record_count},
        status          = 'success',
        next_run_time   = '{new_next_run}',
        error_message   = NULL,
        pipeline_notes  = 'Hardcode load {record_count} rows in {duration_secs}s'
    WHERE table_name = '{TARGET_TABLE}'
""")

print(f"Done | {record_count} rows | {duration_secs}s | Next: {new_next_run} UTC")

