# ─── Cell 0 ───
# ==============================================================================
# [ENGINE] brz_engine — KHÔNG CHỈNH
# Nhận từ nb_etl: TARGET_TABLE, SOURCE_TABLE, COLUMN_SQL
# ==============================================================================
import time, calendar, random as _random
from datetime import datetime, timedelta
from pyspark.sql import functions as F
from delta.tables import DeltaTable

start_time   = time.time()
METADATA_TBL = "SupplyChain_Lakehouse.dbo.utl_pipeline_metadata"
LAKEHOUSE    = "SupplyChain_Lakehouse"
ROW_LIMIT    = None
SOURCE_BASE  = (
    "abfss://c8d9fc83-18b6-4e1d-8264-0b49eed36fe0"
    "@onelake.dfs.fabric.microsoft.com"
    "/584e7d2c-46ca-49dc-bb6c-68df6ef4f424/Tables"
)

SOURCE_PATH = f"{SOURCE_BASE}/{SOURCE_TABLE}"

# ── 1. FETCH CONFIG ────────────────────────────────────────────────────────────
print(f"🔍 Fetching config for: {TARGET_TABLE}")
config_df = spark.sql(f"SELECT * FROM {METADATA_TBL} WHERE table_name = '{TARGET_TABLE}'")
if config_df.count() == 0:
    raise Exception(f"❌ '{TARGET_TABLE}' chưa được đăng ký trong utl_pipeline_metadata!")

config         = config_df.collect()[0]
LOAD_TYPE      = config['load_type']
WATERMARK_COL  = config['watermark_column']
PRIMARY_KEY    = config['primary_key']
FREQ           = config['frequency']
LAST_WM        = config['last_watermark_value']
NEXT_RUN       = config['next_run_time']
IS_ACTIVE      = config['is_active']
SCHEDULED_HOUR = config['scheduled_hour']
print(f"📋 Config | load_type={LOAD_TYPE} | watermark_col={WATERMARK_COL} | last_wm={LAST_WM} | freq={FREQ}")

# ── 2. SCHEDULING GATE ─────────────────────────────────────────────────────────
if IS_ACTIVE == 0:
    print("⏸️  Skipped: is_active = 0")
    notebookutils.notebook.exit("skipped:inactive")

now = datetime.utcnow()
if NEXT_RUN and now < NEXT_RUN.replace(tzinfo=None):
    remaining = round((NEXT_RUN.replace(tzinfo=None) - now).total_seconds() / 60, 1)
    print(f"⏳ Skipped: next run at {NEXT_RUN} UTC ({remaining} min remaining)")
    notebookutils.notebook.exit("skipped:not_due")

# ── 3. SPARK CONFIG ────────────────────────────────────────────────────────────
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.microsoft.delta.optimizeWrite.enabled", "true")
spark.conf.set("spark.microsoft.delta.vorder.enabled", "true")
spark.conf.set("spark.sql.parquet.datetimeRebaseModeInRead", "LEGACY")
spark.conf.set("spark.sql.parquet.int96RebaseModeInRead", "LEGACY")

# ── 4. INGEST SOURCE ───────────────────────────────────────────────────────────
print(f"📥 Reading: {SOURCE_PATH}")
try:
    df_raw = spark.read.format("delta") \
        .option("mergeSchema", "true") \
        .load(SOURCE_PATH)
except Exception as e:
    raise Exception(f"❌ Không đọc được source: {SOURCE_PATH}\n{str(e)}")

if ROW_LIMIT:
    df_raw = df_raw.limit(ROW_LIMIT)
    print(f"⚠️  Dev mode: limited to {ROW_LIMIT:,} rows")

if LOAD_TYPE in ('incremental', 'upsert') and WATERMARK_COL and LAST_WM:
    df_raw = df_raw.filter(F.col(WATERMARK_COL) > F.lit(LAST_WM))
    print(f"🔄 Incremental filter: {WATERMARK_COL} > {LAST_WM}")
elif LOAD_TYPE == 'incremental' and WATERMARK_COL and not LAST_WM:
    print(f"🔄 Incremental first run: loading all data")

df_raw.createOrReplaceTempView("raw_source")

# ── 5. TRANSFORM ───────────────────────────────────────────────────────────────
df_final     = spark.sql(COLUMN_SQL)
record_count = df_final.count()
print(f"📋 Records to process: {record_count:,}")

# ── 6. WRITE ───────────────────────────────────────────────────────────────────
FULL_TARGET = f"{LAKEHOUSE}.dbo.{TARGET_TABLE}"

if record_count == 0:
    print("☕ No new records. Skipping write.")
else:
    if LOAD_TYPE == 'overwrite':
        print(f"🔄 OVERWRITE → {FULL_TARGET}")
        df_final.write.format("delta") \
            .mode("overwrite") \
            .option("overwriteSchema", "true") \
            .saveAsTable(FULL_TARGET)

    elif LOAD_TYPE == 'incremental':
        print(f"➕ INCREMENTAL APPEND → {FULL_TARGET}")
        df_final.write.format("delta") \
            .mode("append") \
            .saveAsTable(FULL_TARGET)

    elif LOAD_TYPE == 'upsert':
        pk_list   = [k.strip() for k in PRIMARY_KEY.split(",")]
        join_cond = " AND ".join([f"t.{k} = s.{k}" for k in pk_list])
        print(f"🔀 UPSERT → {FULL_TARGET} ON ({', '.join(pk_list)})")
        if DeltaTable.isDeltaTable(spark, f"Tables/{TARGET_TABLE}"):
            DeltaTable.forName(spark, FULL_TARGET).alias("t") \
                .merge(df_final.alias("s"), join_cond) \
                .whenMatchedUpdateAll() \
                .whenNotMatchedInsertAll() \
                .execute()
        else:
            print(f"⚠️  Target chua ton tai, tao moi bang overwrite")
            df_final.write.format("delta").mode("overwrite").saveAsTable(FULL_TARGET)

    else:
        raise Exception(f"❌ load_type khong hop le: '{LOAD_TYPE}'")

    spark.sql(f"OPTIMIZE {FULL_TARGET}")

# ── 7. CALC NEXT RUN ───────────────────────────────────────────────────────────
def calc_next_run(freq, scheduled_hour):
    freq = (freq or '').lower()
    now  = datetime.utcnow()
    h    = scheduled_hour if scheduled_hour is not None else 2

    if freq == 'daily':
        next_day = now.date() + timedelta(days=1)
        return datetime(next_day.year, next_day.month, next_day.day, h, 0, 0)
    if freq == 'hourly':
        return now + timedelta(hours=1)
    if freq == 'weekly':
        next_week = now.date() + timedelta(weeks=1)
        return datetime(next_week.year, next_week.month, next_week.day, h, 0, 0)
    if freq == 'monthly':
        y = now.year + (now.month // 12)
        m = (now.month % 12) + 1
        d = min(now.day, calendar.monthrange(y, m)[1])
        return datetime(y, m, d, h, 0, 0)
    return now + timedelta(days=1)

new_wm = LAST_WM
if WATERMARK_COL and WATERMARK_COL in df_raw.columns and record_count > 0:
    new_wm = spark.read.format("delta") \
        .option("mergeSchema", "true") \
        .load(SOURCE_PATH) \
        .agg(F.max(WATERMARK_COL)) \
        .collect()[0][0]

new_next_run  = calc_next_run(FREQ, SCHEDULED_HOUR)
duration_secs = round(time.time() - start_time)

# ── 8. UPDATE METADATA — Exponential Backoff + Full Jitter ────────────────────
def update_metadata_with_retry(spark, metadata_tbl, target_table,
                                new_wm, record_count, new_next_run, duration_secs,
                                source_tables_str="",
                                max_retries=15, base=2.0, cap=60.0):
    for attempt in range(max_retries):
        try:
            # ✅ Format pipeline_notes dựa trên record_count
            if record_count == 0:
                pipeline_notes = 'No new records to process'
            else:
                pipeline_notes = f'Processed {record_count:,} rows in {duration_secs}s'
            
            safe_notes = pipeline_notes.replace("'", "''")
            
            spark.sql(f"""
                UPDATE {metadata_tbl} SET
                    last_watermark_value = '{new_wm}',
                    last_load_date       = current_timestamp(),
                    rows_loaded          = {record_count},
                    status               = 'success',
                    next_run_time        = '{new_next_run}',
                    error_message        = NULL,
                    pipeline_notes       = '{safe_notes}',
                    source_tables        = '{source_tables_str}'
                WHERE table_name = '{target_table}'
            """)
            if attempt > 0:
                print(f"✅ Metadata updated after {attempt} retries")
            return

        except Exception as e:
            is_conflict = any(x in str(e) for x in [
                'ConcurrentAppendException',
                'ConcurrentDeleteReadException',
                'ConcurrentTransactionException'
            ])
            if is_conflict and attempt < max_retries - 1:
                ceiling = min(cap, base * (2 ** attempt))
                wait    = _random.uniform(0, ceiling)
                print(f"⚠️ Conflict attempt {attempt+1}/{max_retries} → wait {wait:.1f}s")
                time.sleep(wait)
            else:
                raise

# ── Extract source tables for lineage ──
source_tables_str = f"[external] {SOURCE_TABLE}"

update_metadata_with_retry(
    spark         = spark,
    metadata_tbl  = METADATA_TBL,
    target_table  = TARGET_TABLE,
    new_wm        = new_wm,
    record_count  = record_count,
    new_next_run  = new_next_run,
    duration_secs = duration_secs,
    source_tables_str = source_tables_str
)

print(f"✅ Done | {record_count:,} rows | {duration_secs}s | Next: {new_next_run} UTC")

