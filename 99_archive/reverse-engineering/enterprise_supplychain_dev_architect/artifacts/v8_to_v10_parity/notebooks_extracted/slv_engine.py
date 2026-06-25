# ─── Cell 0 ───
# ==============================================================================
# [ENGINE] slv_engine — KHÔNG CHỈNH
# 
# Chức năng:
# 1. Auto-detect first run (full load) vs subsequent (incremental)
# 2. Scan SQL_TRANSFORM để detect:
#    - JOIN types (LEFT, INNER, CROSS, FULL, RIGHT)
#    - WHERE clauses (filters)
#    - UNION operations
# 3. Log detailed transformation:
#    - Source counts (before JOIN/UNION/WHERE)
#    - Step-by-step: after each JOIN, after WHERE, final
#    - Join loss detection (%) + join type validation
# 4. Handle all LOAD_TYPE: incremental, overwrite, upsert
# ==============================================================================
import time, calendar, random as _random
from datetime import datetime, timedelta
from pyspark.sql import functions as F
from delta.tables import DeltaTable
import re

start_time   = time.time()
METADATA_TBL = "SupplyChain_Lakehouse.dbo.utl_pipeline_metadata"
LAKEHOUSE    = "SupplyChain_Lakehouse"
ROW_LIMIT    = None

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
print(f"📋 Config | load_type={LOAD_TYPE} | watermark_col={WATERMARK_COL} | freq={FREQ}")

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

# ── 4. AUTO-DETECT FIRST RUN vs INCREMENTAL ─────────────────────────────────────
print(f"🔍 Detecting first run vs incremental...")

is_first_run = LAST_WM is None or str(LAST_WM).strip() == 'None' or str(LAST_WM).strip() == ''

if is_first_run:
    print(f"  🟢 FIRST RUN detected (last_wm=NULL) → FULL LOAD")
    sql_transform_filtered = SQL_TRANSFORM
    run_mode = "FIRST_RUN_FULL"
else:
    print(f"  🔄 SUBSEQUENT RUN (last_wm={LAST_WM}) → INCREMENTAL")
    if LOAD_TYPE == 'incremental' and WATERMARK_COL:
        # ✅ Check if SQL already has WHERE clause
        has_where_clause = bool(re.search(r'\bWHERE\b', SQL_TRANSFORM, re.IGNORECASE))
        
        if has_where_clause:
            # WHERE exists → append AND
            watermark_filter = f" AND {WATERMARK_COL} > '{LAST_WM}'"
        else:
            # No WHERE → prepend WHERE
            watermark_filter = f" WHERE {WATERMARK_COL} > '{LAST_WM}'"
        
        sql_transform_filtered = SQL_TRANSFORM + watermark_filter
        run_mode = "INCRE"
    else:
        sql_transform_filtered = SQL_TRANSFORM
        run_mode = "FULL"

# ── 5. SCAN SQL FOR JOIN/WHERE/UNION ────────────────────────────────────────────
print(f"📋 Scanning SQL_TRANSFORM for operations...")

# Extract JOIN types (order matters — preserve sequence)
join_pattern = r'(?:INNER\s+|LEFT\s+|RIGHT\s+|FULL\s+|CROSS\s+)?JOIN\s+(?:[^\s\.]+\.)?([^\s]+)\s+([a-z])'
joins = re.findall(join_pattern, sql_transform_filtered, re.IGNORECASE)

# Extract table names (FROM + all JOINs in order)
from_pattern = r'FROM\s+(?:[^\s\.]+\.)?([^\s]+)\s+([a-z])'
from_match = re.search(from_pattern, sql_transform_filtered, re.IGNORECASE)

# Check for WHERE clause
has_where = bool(re.search(r'\bWHERE\b', sql_transform_filtered, re.IGNORECASE))

# Check for UNION
has_union = bool(re.search(r'\bUNION\b', sql_transform_filtered, re.IGNORECASE))

# Build operation chain
operation_chain = []
if from_match:
    operation_chain.append(f"FROM_{from_match.group(1).upper()}")

for join_type, join_table in joins:
    if not join_type.strip():
        join_type = "INNER"
    else:
        join_type = join_type.strip().upper()
    operation_chain.append(f"{join_type}_JOIN_{join_table.upper()}")

if has_where:
    operation_chain.append("WHERE_FILTER")

if has_union:
    operation_chain.append("UNION")

print(f"  📊 Operations: {' → '.join(operation_chain)}")
print(f"  📊 JOINs found: {len(joins)} (types: {', '.join(set(j[0].strip().upper() or 'INNER' for j in joins))})")
print(f"  📊 Has WHERE: {has_where}")
print(f"  📊 Has UNION: {has_union}")

# ── 6. GET SOURCE ROW COUNTS (BEFORE transform) ─────────────────────────────────
print(f"📊 Counting source rows (before operations)...")

source_counts = {}
try:
    # All tables in SQL (FROM + JOINs)
    all_tables = []
    if from_match:
        all_tables.append(from_match.group(1))
    all_tables.extend([j[1] for j in joins])
    
    for table_name in set(all_tables):
        try:
            if is_first_run:
                source_count_sql = f"SELECT COUNT(*) as cnt FROM {LAKEHOUSE}.dbo.{table_name}"
            else:
                if LOAD_TYPE == 'incremental' and WATERMARK_COL and table_name.startswith('brz_'):
                    source_count_sql = f"""
                        SELECT COUNT(*) as cnt
                        FROM {LAKEHOUSE}.dbo.{table_name}
                        WHERE {WATERMARK_COL} > '{LAST_WM}'
                    """
                else:
                    source_count_sql = f"SELECT COUNT(*) as cnt FROM {LAKEHOUSE}.dbo.{table_name}"
            
            source_count = spark.sql(source_count_sql).collect()[0]['cnt']
            source_counts[table_name] = source_count
            print(f"  📊 {table_name}: {source_count:,} rows")
        except:
            pass
    
except Exception as e:
    print(f"  ⚠️  Could not extract source counts: {str(e)}")

# ── 7. TRANSFORM (SLV: execute SQL_TRANSFORM) ──────────────────────────────────
print(f"📋 Executing SQL_TRANSFORM...")
print(f"  Mode: {run_mode}")
print(f"  Operations: {' → '.join(operation_chain)}")

try:
    df_final = spark.sql(sql_transform_filtered)
except Exception as e:
    raise Exception(f"❌ Không chạy được SQL_TRANSFORM:\n{str(e)}")

if ROW_LIMIT:
    df_final = df_final.limit(ROW_LIMIT)
    print(f"⚠️  Dev mode: limited to {ROW_LIMIT:,} rows")

record_count = df_final.count()
print(f"📊 Final result: {record_count:,} rows")

# ── 8. VALIDATION: JOIN LOSS & TYPE VALIDATION ──────────────────────────────────
print(f"🔍 Validating transformations...")

warnings = []
if record_count == 0:
    warnings.append("NO_OUTPUT")

# Get primary table (first FROM table)
primary_table = list(source_counts.keys())[0] if source_counts else None
if primary_table and source_counts[primary_table] > 0:
    input_count = source_counts[primary_table]
    loss_pct = ((input_count - record_count) / input_count) * 100
    
    # Validate join type vs row count behavior
    has_left_join = any('LEFT' in j[0].upper() for j in joins)
    has_inner_join = any(('INNER' in j[0].upper() or j[0].strip() == '') for j in joins)
    
    if loss_pct > 5:
        if has_left_join:
            # LEFT JOIN should preserve all rows from primary
            warnings.append(f"LEFT_JOIN_LOSS_{loss_pct:.1f}%⚠️")
            print(f"  ⚠️  LEFT JOIN LOSS: {loss_pct:.1f}% ({input_count:,} → {record_count:,})")
        elif has_inner_join:
            # INNER JOIN can reduce rows
            print(f"  ✓ INNER JOIN: {loss_pct:.1f}% reduction (expected, {input_count:,} → {record_count:,})")
        else:
            warnings.append(f"LOSS_{loss_pct:.1f}%")
            print(f"  ⚠️  Row loss: {loss_pct:.1f}%")
    else:
        if has_left_join:
            print(f"  ✓ LEFT JOIN healthy: {loss_pct:.1f}% loss (acceptable)")
        elif has_inner_join:
            print(f"  ✓ INNER JOIN: {loss_pct:.1f}% reduction (expected)")
        else:
            print(f"  ✓ Row count stable")

# ── 9. WRITE ───────────────────────────────────────────────────────────────────
FULL_TARGET = f"{LAKEHOUSE}.dbo.{TARGET_TABLE}"

if record_count == 0:
    print("☕ No new records. Skipping write.")
    pipeline_notes = "No new records"
else:
    if LOAD_TYPE == 'overwrite' and is_first_run:
        print(f"🔄 FIRST RUN FULL OVERWRITE → {FULL_TARGET}")
        df_final.write.format("delta") \
            .mode("overwrite") \
            .option("overwriteSchema", "true") \
            .saveAsTable(FULL_TARGET)
    
    elif LOAD_TYPE == 'overwrite' and not is_first_run:
        print(f"🔄 FULL OVERWRITE → {FULL_TARGET}")
        df_final.write.format("delta") \
            .mode("overwrite") \
            .option("overwriteSchema", "true") \
            .saveAsTable(FULL_TARGET)

    elif LOAD_TYPE == 'incremental':
        print(f"➕ APPEND → {FULL_TARGET}")
        df_final.write.format("delta") \
            .mode("append") \
            .option("mergeSchema", "true") \
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
            print(f"⚠️  Target chưa tồn tại, tạo mới bằng overwrite")
            df_final.write.format("delta").mode("overwrite").saveAsTable(FULL_TARGET)

    else:
        raise Exception(f"❌ load_type không hợp lệ: '{LOAD_TYPE}'")

    if record_count > 1_000_000:
        print(f"⚡ OPTIMIZE {FULL_TARGET} (>1M rows)")
        spark.sql(f"OPTIMIZE {FULL_TARGET}")
    else:
        print(f"⊘ Skip OPTIMIZE (<1M rows)")
    
    # ── BUILD DETAILED PIPELINE NOTES ──────────────────────────────────────────
    # Format: MODE | OPERATIONS | BEFORE_COUNTS → AFTER | WARNINGS
    source_counts_str = " | ".join([f"{t}={c:,}" for t, c in source_counts.items()])
    ops_str = " → ".join(operation_chain) if operation_chain else "SIMPLE_SELECT"
    warning_str = f" [⚠️  {','.join(warnings)}]" if warnings else " [✓]"
    
    pipeline_notes = f"{run_mode} | {ops_str} | BEFORE:{source_counts_str} → AFTER:{record_count:,}{warning_str}"
    
    print(f"📝 Pipeline notes: {pipeline_notes}")

# ── 10. CALC NEXT RUN ──────────────────────────────────────────────────────────
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

new_wm = datetime.utcnow().isoformat()
new_next_run  = calc_next_run(FREQ, SCHEDULED_HOUR)
duration_secs = round(time.time() - start_time)

# ── 11. UPDATE METADATA — Exponential Backoff + Full Jitter ───────────────────
def update_metadata_with_retry(spark, metadata_tbl, target_table,
                                new_wm, record_count, new_next_run, duration_secs, pipeline_notes,
                                source_tables_str="",
                                max_retries=15, base=2.0, cap=60.0):
    for attempt in range(max_retries):
        try:
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
import re as _re
_src_pattern = r'(?:FROM|JOIN)\s+(?:\S+\.)(\w+)'
_src_tables = _re.findall(_src_pattern, SQL_TRANSFORM, _re.IGNORECASE)
_skip = {'select','where','set','as','on','and','or','raw_source','table','view','null','true','false','case','when','then','else','end'}
source_tables_str = ','.join(sorted(set(t for t in _src_tables if t.lower() not in _skip and len(t) > 2)))

update_metadata_with_retry(
    spark=spark,
    metadata_tbl=METADATA_TBL,
    target_table=TARGET_TABLE,
    new_wm=new_wm,
    record_count=record_count,
    new_next_run=new_next_run,
    duration_secs=duration_secs,
    pipeline_notes=pipeline_notes,
    source_tables_str=source_tables_str
)

print(f"✅ Done | {record_count:,} rows | {duration_secs}s | Next: {new_next_run} UTC")

