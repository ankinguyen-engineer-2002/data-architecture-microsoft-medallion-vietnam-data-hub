# ─── Cell 0 ───
TARGET_TABLE   = "brz_supplychain_enh_1__demandforecastsnapshotdaily"
SOURCE_TABLE   = "SupplyChain_Enh_1/DemandForecastSnapshotDaily"
WATERMARK_COL  = "dfcSnapshot"
CUTOFF_DATE    = "2023-01-01"
NUM_PARTITIONS = 600
SCHEDULED_HOUR = 2

# ─── Cell 1 ───
import time, calendar
from datetime import datetime, timedelta
from pyspark.sql import functions as F
from pyspark.sql.types import TimestampType, DateType

start_time   = time.time()
METADATA_TBL = "SupplyChain_Lakehouse.dbo.utl_pipeline_metadata"
FULL_TARGET  = f"SupplyChain_Lakehouse.dbo.{TARGET_TABLE}"
SOURCE_PATH  = (
    "abfss://c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
    "@onelake.dfs.fabric.microsoft.com"
    f"/584e7d2c-46ca-49dc-bb6c-68df6ef4f424/Tables/{SOURCE_TABLE}"
)

new_count    = 0
new_watermark = None

# ── Spark config ──────────────────────────────────────────────
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.microsoft.delta.optimizeWrite.enabled", "true")
spark.conf.set("spark.microsoft.delta.vorder.enabled", "true")

# ── Helpers ───────────────────────────────────────────────────
def apply_cutoff_filter(df, col_name, cutoff_date):
    col_dtype = df.schema[col_name].dataType
    if isinstance(col_dtype, (TimestampType, DateType)):
        return df.filter(F.col(col_name) >= F.lit(cutoff_date).cast("timestamp"))
    return df.filter(
        F.to_timestamp(F.col(col_name), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
        >= F.lit(cutoff_date).cast("timestamp")
    )

def apply_cleaning(df):
    return (
        df.filter(F.col("dfcItem").isNotNull())
        .select(
            F.trim(F.col("dfcItem")).alias("id_item_sku"),
            F.trim(F.col("dfcWarehouse")).alias("code_warehouse"),
            F.col("dfcFiscalMonth").cast("int").alias("num_fiscal_month"),
            F.trim(F.col("DfcCustomerGroups")).alias("code_customer_group"),
            F.col("dfcResultantForecast").cast("decimal(14,3)").alias("qty_resultant_forecast"),
            F.col("dfcPromotionalLift").cast("decimal(14,3)").alias("qty_promotional_lift"),
            F.col("dfcForcedForecast").cast("decimal(14,3)").alias("qty_forced_forecast"),
            F.col("dfcOrderFutureQty").cast("int").alias("qty_order_future"),
            F.col("dfcPermComptQty").cast("decimal(14,2)").alias("qty_perm_component"),
            F.col("dfcSnapshot").cast("timestamp").alias("ts_snapshot"),
            F.trim(F.col("dfcMainPiece")).alias("code_main_piece"),
            F.trim(F.col("dfcCollectiveClass")).alias("name_collective_class"),
            F.trim(F.col("dfcUsr32Text")).alias("name_product_category"),
            F.trim(F.col("dfcFCSTTypeCode")).alias("code_forecast_type"),
            F.trim(F.col("dfcMgmtCode")).alias("code_management"),
            F.trim(F.col("dfcDerivedFCSTID")).alias("id_derived_forecast"),
            F.col("dfcDerivedFCSTFctr").cast("decimal(10,3)").alias("val_derived_forecast_factor"),
            F.col("dfcValidDemandMonths").cast("int").alias("num_valid_demand_months"),
            F.trim(F.col("dfcUsr25Text")).alias("name_usr25"),
            F.trim(F.col("usra")).alias("name_created_by"),
            F.col("dtea").cast("timestamp").alias("ts_created"),
            F.trim(F.col("usrc")).alias("name_modified_by"),
            F.col("dtec").cast("timestamp").alias("ts_modified")
        )
    )

def calc_next_run(scheduled_hour):
    now      = datetime.utcnow()
    next_day = now.date() + timedelta(days=1)
    return datetime(next_day.year, next_day.month, next_day.day, scheduled_hour, 0, 0)

# ── Fetch metadata + scheduling gate ─────────────────────────
row = spark.sql(f"""
    SELECT last_watermark_value, is_active, next_run_time
    FROM {METADATA_TBL}
    WHERE table_name = '{TARGET_TABLE}'
""").collect()

if len(row) == 0:
    raise Exception(f"'{TARGET_TABLE}' chua duoc dang ky trong utl_pipeline_metadata!")

if row[0]["is_active"] == 0:
    print("⏸️  Skipped: is_active = 0")
    notebookutils.notebook.exit("skipped:inactive")

next_run = row[0]["next_run_time"]
if next_run and datetime.utcnow() < next_run.replace(tzinfo=None):
    mins = round((next_run.replace(tzinfo=None) - datetime.utcnow()).total_seconds() / 60, 1)
    print(f"⏳ Skipped: next run at {next_run} UTC ({mins} min remaining)")
    notebookutils.notebook.exit("skipped:not_due")

last_wm = row[0]["last_watermark_value"]

# ── Main ──────────────────────────────────────────────────────
try:
    if last_wm is None:
        # FIRST RUN: full load
        print("🟢 No watermark → FULL LOAD...")
        df_raw        = spark.read.format("delta").load(SOURCE_PATH)
        df_raw        = apply_cutoff_filter(df_raw, WATERMARK_COL, CUTOFF_DATE)
        new_watermark = df_raw.agg(F.max(WATERMARK_COL)).first()[0]
        new_count     = df_raw.count()
        df_out = apply_cleaning(df_raw).repartition(NUM_PARTITIONS)
        spark.sql(f"DROP TABLE IF EXISTS {FULL_TARGET}")
        df_out.write.format("delta").mode("overwrite") \
            .option("overwriteSchema", "true").saveAsTable(FULL_TARGET)
        print(f"✅ FULL LOAD done: {new_count:,} rows | watermark = {new_watermark}")
    else:
        # INCREMENTAL
        print(f"🔄 Last watermark: {last_wm}")
        df_source  = spark.read.format("delta").load(SOURCE_PATH)
        df_source  = apply_cutoff_filter(df_source, WATERMARK_COL, CUTOFF_DATE)
        df_new_raw = df_source.filter(F.col(WATERMARK_COL) > F.lit(last_wm))
        new_count  = df_new_raw.count()
        
        if new_count == 0:
            print("☕ No new records to process")
            pipeline_notes = 'No new records since last watermark'
            safe_notes = pipeline_notes.replace("'", "''")
            new_next_run = calc_next_run(SCHEDULED_HOUR)
            
            spark.sql(f"""
                UPDATE {METADATA_TBL} SET
                    last_load_date  = current_timestamp(),
                    rows_loaded     = 0,
                    status          = 'success',
                    next_run_time   = '{new_next_run}',
                    error_message   = NULL,
                    pipeline_notes  = '{safe_notes}'
                WHERE table_name = '{TARGET_TABLE}'
            """)
            print(f"✅ Done | 0 rows | Next: {new_next_run} UTC")
            # ✅ KHÔNG exit() — flow continues naturally
        else:
            new_watermark = df_new_raw.agg(F.max(WATERMARK_COL)).first()[0]
            df_out = apply_cleaning(df_new_raw) \
                .repartition(min(new_count // 500000 + 1, NUM_PARTITIONS))
            df_out.write.format("delta").mode("append").saveAsTable(FULL_TARGET)
            print(f"✅ INCREMENTAL done: +{new_count:,} rows | watermark = {new_watermark}")
            
            # OPTIMIZE (chỉ khi có write)
            print(f"⚡ OPTIMIZE {FULL_TARGET}")
            spark.sql(f"OPTIMIZE {FULL_TARGET}")
            
            # UPDATE METADATA (chỉ khi có write)
            duration_secs = round(time.time() - start_time)
            new_next_run  = calc_next_run(SCHEDULED_HOUR)
            pipeline_notes = f'Processed {new_count:,} rows in {duration_secs}s'
            safe_notes = pipeline_notes.replace("'", "''")
            
            spark.sql(f"""
                UPDATE {METADATA_TBL} SET
                    last_watermark_value = '{new_watermark}',
                    last_load_date       = current_timestamp(),
                    rows_loaded          = {new_count},
                    status               = 'success',
                    next_run_time        = '{new_next_run}',
                    error_message        = NULL,
                    pipeline_notes       = '{safe_notes}'
                WHERE table_name = '{TARGET_TABLE}'
            """)
            print(f"✅ Done | {new_count:,} rows | {duration_secs}s | Next: {new_next_run} UTC")

except Exception as e:
    error_msg = str(e).replace("'", "''")[:500]
    safe_error = error_msg
    
    spark.sql(f"""
        UPDATE {METADATA_TBL} SET
            status         = 'failed',
            error_message  = '{safe_error}',
            last_load_date = current_timestamp(),
            pipeline_notes = 'Pipeline failed - see error_message'
        WHERE table_name = '{TARGET_TABLE}'
    """)
    print(f"❌ Pipeline failed: {str(e)}")
    notebookutils.notebook.exit("failed")

