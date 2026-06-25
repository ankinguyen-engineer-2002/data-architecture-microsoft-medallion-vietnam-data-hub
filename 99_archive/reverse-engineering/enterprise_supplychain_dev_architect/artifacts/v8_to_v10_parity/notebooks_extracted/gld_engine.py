# ─── Cell 0 ───
# ==============================================================================
# [ENGINE] gld_engine — KHÔNG CHỈNH
# 
# Chức năng:
# 1. Auto-detect first run (full load) vs subsequent (full reload)
# 2. Scan SQL_AGGREGATE để detect:
#    - JOIN types (LEFT, INNER, CROSS, FULL, RIGHT)
#    - WHERE clauses (filters)
#    - GROUP BY aggregation
# 3. Log detailed transformation:
#    - Source counts (before aggregation)
#    - Final row counts
#    - Aggregation ratio (input vs output)
# 4. Handle LOAD_TYPE: overwrite (full reload every run)
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
FREQ           = config['frequency']
NEXT_RUN       = config['next_run_time']
IS_ACTIVE      = config['is_active']
SCHEDULED_HOUR = config['scheduled_hour']
print(f"📋 Config | load_type={LOAD_TYPE} | freq={FREQ}")

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

# ── 4. SCAN SQL FOR JOIN/WHERE/GROUP BY ────────────────────────────────────────
print(f"📋 Scanning SQL_AGGREGATE for operations...")

# Extract JOIN types (order matters)
join_pattern = r'(?:INNER\s+|LEFT\s+|RIGHT\s+|FULL\s+|CROSS\s+)?JOIN\s+(?:[^\s\.]+\.)?([^\s]+)\s+([a-z])'
joins = re.findall(join_pattern, SQL_AGGREGATE, re.IGNORECASE)

# Extract table names (FROM + all JOINs in order)
from_pattern = r'FROM\s+(?:[^\s\.]+\.)?([^\s]+)\s+([a-z])'
from_match = re.search(from_pattern, SQL_AGGREGATE, re.IGNORECASE)

# Check for WHERE clause
has_where = bool(re.search(r'\bWHERE\b', SQL_AGGREGATE, re.IGNORECASE))

# Check for GROUP BY
has_group_by = bool(re.search(r'\bGROUP\s+BY\b', SQL_AGGREGATE, re.IGNORECASE))

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

if has_group_by:
    operation_chain.append("GROUP_BY")

print(f"  📊 Operations: {' → '.join(operation_chain)}")
print(f"  📊 JOINs found: {len(joins)} (types: {', '.join(set(j[0].strip().upper() or 'INNER' for j in joins))})")
print(f"  📊 Has WHERE: {has_where}")
print(f"  📊 Has GROUP BY: {has_group_by}")

# ── 5. GET SOURCE ROW COUNTS (BEFORE aggregation) ───────────────────────────────
print(f"📊 Counting source rows (before aggregation)...")

source_counts = {}
try:
    # All tables in SQL (FROM + JOINs)
    all_tables = []
    if from_match:
        all_tables.append(from_match.group(1))
    all_tables.extend([j[1] for j in joins])
    
    for table_name in set(all_tables):
        try:
            source_count_sql = f"SELECT COUNT(*) as cnt FROM {LAKEHOUSE}.dbo.{table_name}"
            source_count = spark.sql(source_count_sql).collect()[0]['cnt']
            source_counts[table_name] = source_count
            print(f"  📊 {table_name}: {source_count:,} rows")
        except:
            pass
    
except Exception as e:
    print(f"  ⚠️  Could not extract source counts: {str(e)}")

# ── 6. AGGREGATE (GLD: execute SQL_AGGREGATE) ──────────────────────────────────
print(f"📋 Executing SQL_AGGREGATE (full reload)...")
print(f"  Operations: {' → '.join(operation_chain)}")

try:
    df_final = spark.sql(SQL_AGGREGATE)
except Exception as e:
    raise Exception(f"❌ Không chạy được SQL_AGGREGATE:\n{str(e)}")

if ROW_LIMIT:
    df_final = df_final.limit(ROW_LIMIT)
    print(f"⚠️  Dev mode: limited to {ROW_LIMIT:,} rows")

record_count = df_final.count()
print(f"📊 Final result (after aggregation): {record_count:,} rows")

# ── 7. VALIDATION: Aggregation Ratio ───────────────────────────────────────────
print(f"🔍 Validating aggregation...")

warnings = []
if record_count == 0:
    warnings.append("NO_OUTPUT")

# Calculate aggregation ratio (input vs output)
primary_table = list(source_counts.keys())[0] if source_counts else None
if primary_table and source_counts[primary_table] > 0:
    input_count = source_counts[primary_table]
    ratio = (record_count / input_count) * 100
    
    if has_group_by:
        print(f"  ✓ GROUP BY: {input_count:,} → {record_count:,} rows (ratio: {ratio:.1f}%)")
    else:
        if ratio < 100:
            print(f"  ℹ️ Aggregation reduced rows: {ratio:.1f}%")
        else:
            print(f"  ℹ️ No reduction: {ratio:.1f}%")

# ── 8. WRITE ───────────────────────────────────────────────────────────────────
FULL_TARGET = f"{LAKEHOUSE}.dbo.{TARGET_TABLE}"

if record_count == 0:
    print("☕ No records. Skipping write.")
    pipeline_notes = "No records"
else:
    # GLD: Always OVERWRITE (full reload)
    print(f"🔄 OVERWRITE → {FULL_TARGET} (full reload)")
    df_final.write.format("delta") \
        .mode("overwrite") \
        .option("overwriteSchema", "true") \
        .option("mergeSchema", "true") \
        .saveAsTable(FULL_TARGET)

    # OPTIMIZE always for aggregate tables
    print(f"⚡ OPTIMIZE {FULL_TARGET}")
    spark.sql(f"OPTIMIZE {FULL_TARGET}")
    
    # ── BUILD DETAILED PIPELINE NOTES ──────────────────────────────────────────
    # Format: MODE | OPERATIONS | BEFORE_COUNTS → AFTER | RATIO | WARNINGS
    source_counts_str = " | ".join([f"{t}={c:,}" for t, c in source_counts.items()])
    ops_str = " → ".join(operation_chain) if operation_chain else "SIMPLE_SELECT"
    warning_str = f" [⚠️  {','.join(warnings)}]" if warnings else " [✓]"
    
    if has_group_by and source_counts and primary_table:
        primary_count = source_counts[primary_table]
        ratio = (record_count / primary_count) * 100
        pipeline_notes = f"FULL | {ops_str} | BEFORE:{source_counts_str} → AFTER:{record_count:,} (ratio {ratio:.1f}%){warning_str}"
    else:
        pipeline_notes = f"FULL | {ops_str} | BEFORE:{source_counts_str} → AFTER:{record_count:,}{warning_str}"
    
    print(f"📝 Pipeline notes: {pipeline_notes}")

# ── 9. CALC NEXT RUN ───────────────────────────────────────────────────────────
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

# ── 10. UPDATE METADATA — Exponential Backoff + Full Jitter ───────────────────
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
_src_tables = _re.findall(_src_pattern, SQL_AGGREGATE, _re.IGNORECASE)
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

