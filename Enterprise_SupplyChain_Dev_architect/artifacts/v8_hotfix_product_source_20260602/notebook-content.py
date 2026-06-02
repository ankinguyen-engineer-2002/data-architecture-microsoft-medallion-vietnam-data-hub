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
# META         {"id": "62a3081e-4093-4f46-856c-f50aa58732fa"},
# META         {"id": "584e7d2c-46ca-49dc-bb6c-68df6ef4f424"}
# META       ]
# META     }
# META   }
# META }

# CELL ********************

# v8 hotfix 2026-06-02: the legacy product source path no longer exists.
# Keep the v8 ref_product output contract by projecting from the existing EDW supplement table.
import time, calendar, random as _random
from datetime import datetime, timedelta
from pyspark.sql import functions as F

start_time = time.time()
TARGET_TABLE = "ref_product"
SOURCE_TABLE = "SupplyChain_Lakehouse.dbo.ref_product_ver2"
TARGET_FULL = "SupplyChain_Lakehouse.dbo.ref_product"
METADATA_TBL = "SupplyChain_Lakehouse.dbo.utl_pipeline_metadata"

print(f"Fetching config for: {TARGET_TABLE}")
config_df = spark.sql(f"SELECT * FROM {METADATA_TBL} WHERE table_name = '{TARGET_TABLE}'")
if config_df.count() == 0:
    raise Exception(f"'{TARGET_TABLE}' is not registered in utl_pipeline_metadata")

config = config_df.collect()[0]
FREQ = config['frequency']
NEXT_RUN = config['next_run_time']
IS_ACTIVE = config['is_active']
SCHEDULED_HOUR = config['scheduled_hour']
LAST_WM = config['last_watermark_value']

if IS_ACTIVE == 0:
    print("Skipped: is_active = 0")
    notebookutils.notebook.exit("skipped:inactive")

now = datetime.utcnow()
if NEXT_RUN and now < NEXT_RUN.replace(tzinfo=None):
    remaining = round((NEXT_RUN.replace(tzinfo=None) - now).total_seconds() / 60, 1)
    print(f"Skipped: next run at {NEXT_RUN} UTC ({remaining} min remaining)")
    notebookutils.notebook.exit("skipped:not_due")

spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.microsoft.delta.optimizeWrite.enabled", "true")
spark.conf.set("spark.microsoft.delta.vorder.enabled", "true")

select_expr = [
    'CAST(`sk_product` AS INT) AS `sk_product`',
    'TRIM(CAST(`id_item_sku` AS STRING)) AS `id_item_sku`',
    'TRIM(CAST(`id_item` AS STRING)) AS `id_item`',
    'TRIM(CAST(`id_scp_item` AS STRING)) AS `id_scp_item`',
    'TRIM(CAST(`name_item_description` AS STRING)) AS `name_item_description`',
    'TRIM(CAST(`name_color` AS STRING)) AS `name_color`',
    'CAST(`num_qty_in_box` AS INT) AS `num_qty_in_box`',
    'TRIM(CAST(`code_uom` AS STRING)) AS `code_uom`',
    'TRIM(CAST(`code_series` AS STRING)) AS `code_series`',
    'TRIM(CAST(`code_ext_series` AS STRING)) AS `code_ext_series`',
    'TRIM(CAST(`code_item_ext_series` AS STRING)) AS `code_item_ext_series`',
    'TRIM(CAST(`name_series` AS STRING)) AS `name_series`',
    'TRIM(CAST(`name_series_color` AS STRING)) AS `name_series_color`',
    'TRIM(CAST(`name_series_description` AS STRING)) AS `name_series_description`',
    'TRIM(CAST(`name_item_desc_series` AS STRING)) AS `name_item_desc_series`',
    'TRIM(CAST(`name_sh_item_desc_series` AS STRING)) AS `name_sh_item_desc_series`',
    'TRIM(CAST(`name_sh_series_description` AS STRING)) AS `name_sh_series_description`',
    'TRIM(CAST(`name_item_desc_series_color` AS STRING)) AS `name_item_desc_series_color`',
    'TRIM(CAST(`code_item_class` AS STRING)) AS `code_item_class`',
    'TRIM(CAST(`name_item_class` AS STRING)) AS `name_item_class`',
    'TRIM(CAST(`name_item_class_full` AS STRING)) AS `name_item_class_full`',
    'TRIM(CAST(`code_item` AS STRING)) AS `code_item`',
    'TRIM(CAST(`name_item_grouping` AS STRING)) AS `name_item_grouping`',
    'TRIM(CAST(`code_item_style` AS STRING)) AS `code_item_style`',
    'TRIM(CAST(`name_item_style_group` AS STRING)) AS `name_item_style_group`',
    'TRIM(CAST(`name_item_style` AS STRING)) AS `name_item_style`',
    'TRIM(CAST(`name_product_line` AS STRING)) AS `name_product_line`',
    'TRIM(CAST(`code_retail_category` AS STRING)) AS `code_retail_category`',
    'TRIM(CAST(`name_retail_category` AS STRING)) AS `name_retail_category`',
    'TRIM(CAST(`name_merchandising_category` AS STRING)) AS `name_merchandising_category`',
    'TRIM(CAST(`name_child_style` AS STRING)) AS `name_child_style`',
    'TRIM(CAST(`name_parent_style` AS STRING)) AS `name_parent_style`',
    'TRIM(CAST(`name_price_point` AS STRING)) AS `name_price_point`',
    'TRIM(CAST(`code_association` AS STRING)) AS `code_association`',
    'TRIM(CAST(`code_sales_class` AS STRING)) AS `code_sales_class`',
    'TRIM(CAST(`name_sales_class_description` AS STRING)) AS `name_sales_class_description`',
    'TRIM(CAST(`name_sales_class` AS STRING)) AS `name_sales_class`',
    'TRIM(CAST(`code_afi_sales_category` AS STRING)) AS `code_afi_sales_category`',
    'TRIM(CAST(`name_afi_sales_category` AS STRING)) AS `name_afi_sales_category`',
    'TRIM(CAST(`code_afi_sales_division` AS STRING)) AS `code_afi_sales_division`',
    'TRIM(CAST(`name_afi_sales_division` AS STRING)) AS `name_afi_sales_division`',
    'TRIM(CAST(`name_afi_finance_division` AS STRING)) AS `name_afi_finance_division`',
    'TRIM(CAST(`code_discount_class` AS STRING)) AS `code_discount_class`',
    'TRIM(CAST(`name_discount_class_description` AS STRING)) AS `name_discount_class_description`',
    'TRIM(CAST(`name_discount_class` AS STRING)) AS `name_discount_class`',
    'TRIM(CAST(`code_commission_class` AS STRING)) AS `code_commission_class`',
    'TRIM(CAST(`name_commission_class_description` AS STRING)) AS `name_commission_class_description`',
    'TRIM(CAST(`name_commission_class` AS STRING)) AS `name_commission_class`',
    'TRIM(CAST(`code_freight_class` AS STRING)) AS `code_freight_class`',
    'TRIM(CAST(`name_freight_class_description` AS STRING)) AS `name_freight_class_description`',
    'TRIM(CAST(`name_freight_class` AS STRING)) AS `name_freight_class`',
    'TRIM(CAST(`code_collective_class` AS STRING)) AS `code_collective_class`',
    'TRIM(CAST(`name_collective_class` AS STRING)) AS `name_collective_class`',
    'TRIM(CAST(`code_responsible_office` AS STRING)) AS `code_responsible_office`',
    'TRIM(CAST(`code_import_domestic` AS STRING)) AS `code_import_domestic`',
    'TRIM(CAST(`name_country_of_origin` AS STRING)) AS `name_country_of_origin`',
    'TRIM(CAST(`code_cex` AS STRING)) AS `code_cex`',
    'TRIM(CAST(`code_afi_item_status` AS STRING)) AS `code_afi_item_status`',
    'TRIM(CAST(`code_manufacturing_status` AS STRING)) AS `code_manufacturing_status`',
    'TRIM(CAST(`code_current_scp_manufacturing_status` AS STRING)) AS `code_current_scp_manufacturing_status`',
    'TRIM(CAST(`code_marketing_item_status` AS STRING)) AS `code_marketing_item_status`',
    'TRIM(CAST(`name_marketing_status` AS STRING)) AS `name_marketing_status`',
    'TRIM(CAST(`code_current_status` AS STRING)) AS `code_current_status`',
    'CAST(`dt_manufacturing_status_change` AS DATE) AS `dt_manufacturing_status_change`',
    'CAST(`is_main_piece` AS BOOLEAN) AS `is_main_piece`',
    'CAST(`num_commodity_item` AS INT) AS `num_commodity_item`',
    'TRIM(CAST(`code_sellable_item` AS STRING)) AS `code_sellable_item`',
    'CAST(`is_f123_product` AS INT) AS `is_f123_product`',
    'CAST(`is_hs_core_product` AS INT) AS `is_hs_core_product`',
    'CAST(`is_hs_proprietary_product` AS INT) AS `is_hs_proprietary_product`',
    'CAST(`is_hs_exclusive` AS INT) AS `is_hs_exclusive`',
    'CAST(`is_berkline_product` AS INT) AS `is_berkline_product`',
    'CAST(`is_benchcraft_product` AS INT) AS `is_benchcraft_product`',
    'CAST(`is_new_millennium_product` AS INT) AS `is_new_millennium_product`',
    'CAST(`is_bardini_product` AS INT) AS `is_bardini_product`',
    'CAST(`is_shanghai_store` AS INT) AS `is_shanghai_store`',
    'CAST(`num_default_group` AS INT) AS `num_default_group`',
    'TRIM(CAST(`name_market_introduced_at` AS STRING)) AS `name_market_introduced_at`',
    'CAST(`dt_market_begin` AS DATE) AS `dt_market_begin`',
    'CAST(`dt_market_end` AS DATE) AS `dt_market_end`',
    'CAST(`amt_fob_price` AS DECIMAL(14,3)) AS `amt_fob_price`',
    'TRIM(CAST(`code_good_better_best` AS STRING)) AS `code_good_better_best`',
    'CAST(`num_gbb_sort` AS INT) AS `num_gbb_sort`',
    'TRIM(CAST(`code_primary_vendor` AS STRING)) AS `code_primary_vendor`',
    'TRIM(CAST(`name_primary_vendor` AS STRING)) AS `name_primary_vendor`',
    'TRIM(CAST(`code_initial_invoice_period` AS STRING)) AS `code_initial_invoice_period`',
    'CAST(`qty_initial_invoice` AS INT) AS `qty_initial_invoice`',
    'TRIM(CAST(`id_item_forecast_planner` AS STRING)) AS `id_item_forecast_planner`',
    'TRIM(CAST(`code_main_piece` AS STRING)) AS `code_main_piece`'
]

print(f"Reading: {SOURCE_TABLE}")
df_source = spark.table(SOURCE_TABLE)
df_final = (
    df_source
    .selectExpr(*select_expr)
    .where("id_item_sku IS NOT NULL AND id_item_sku <> 'N/A'")
)
record_count = df_final.count()
print(f"Records to process: {record_count:,}")

if record_count == 0:
    print("No records. Skipping write.")
else:
    print(f"OVERWRITE -> {TARGET_FULL}")
    df_final.write.format("delta").mode("overwrite").option("overwriteSchema", "true").saveAsTable(TARGET_FULL)
    spark.sql(f"OPTIMIZE {TARGET_FULL}")

def calc_next_run(freq, scheduled_hour):
    freq = (freq or '').lower()
    now = datetime.utcnow()
    h = scheduled_hour if scheduled_hour is not None else 2
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

def update_metadata_with_retry(max_retries=15, base=2.0, cap=60.0):
    duration_secs = round(time.time() - start_time)
    new_next_run = calc_next_run(FREQ, SCHEDULED_HOUR)
    source_tables_str = "[supplement] SupplyChain_Lakehouse.dbo.ref_product_ver2"
    safe_notes = f"Processed {record_count:,} rows in {duration_secs}s via v8 product supplement hotfix".replace("'", "''")
    for attempt in range(max_retries):
        try:
            spark.sql(f"""
                UPDATE {METADATA_TBL} SET
                    last_watermark_value = '{LAST_WM}',
                    last_load_date       = current_timestamp(),
                    rows_loaded          = {record_count},
                    status               = 'success',
                    next_run_time        = '{new_next_run}',
                    error_message        = NULL,
                    pipeline_notes       = '{safe_notes}',
                    source_tables        = '{source_tables_str}'
                WHERE table_name = '{TARGET_TABLE}'
            """)
            if attempt > 0:
                print(f"Metadata updated after {attempt} retries")
            return new_next_run, duration_secs
        except Exception as e:
            is_conflict = any(x in str(e) for x in [
                'ConcurrentAppendException',
                'ConcurrentDeleteReadException',
                'ConcurrentTransactionException'
            ])
            if is_conflict and attempt < max_retries - 1:
                wait = _random.uniform(0, min(cap, base * (2 ** attempt)))
                print(f"Metadata conflict attempt {attempt+1}/{max_retries} -> wait {wait:.1f}s")
                time.sleep(wait)
            else:
                raise

new_next_run, duration_secs = update_metadata_with_retry()
print(f"Done | {record_count:,} rows | {duration_secs}s | Next: {new_next_run} UTC")

# METADATA ********************

# META {
# META   "language": "python",
# META   "language_group": "synapse_pyspark"
# META }
