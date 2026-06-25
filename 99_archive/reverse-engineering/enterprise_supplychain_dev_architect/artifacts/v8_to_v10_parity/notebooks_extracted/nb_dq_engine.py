# ─── Cell 0 ───
# Fabric notebook source
# Notebook: nb_dq_engine
# Purpose: DQ Engine — 4 check functions + main orchestration loop
# Used by: nb_dq_after_brz, nb_dq_after_ref, nb_dq_after_slv, nb_dq_after_gld

# ─── Cell 1 ───
# Cell 1 — Parameters (tag as parameter cell in Fabric)

# ─── Cell 2 ───
DQ_LAYER = "BRZ"
TEAMS_WEBHOOK_URL = ""

# ─── Cell 3 ───
# Cell 2 — Environment (from notebookutils.runtime.context)

# ─── Cell 4 ───
context = notebookutils.runtime.context
workspace_name = context.get("currentWorkspaceName", "")

if workspace_name == "Enterprise SupplyChain-Dev":
    ENV = "dev"
elif workspace_name == "Enterprise SupplyChain":
    ENV = "prod"
else:
    ENV = "dev"  # fallback

LAKEHOUSE = "SupplyChain_Lakehouse"

# ─── Cell 5 ───
# Cell 3 — Imports + Config

# ─── Cell 6 ───
import json
import uuid
import time
from datetime import datetime, timezone, date

from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField, StringType, BooleanType,
    LongType, TimestampType, IntegerType,
)

RUN_ID = str(uuid.uuid4())
RUN_TIMESTAMP = datetime.now(timezone.utc)

# ─── Cell 7 ───
# Cell 4 — Check Functions (all PySpark, never pandas)

# ─── Cell 8 ───
def check_uniqueness(table_name, column_name, params):
    """Check PK uniqueness. Supports single column or composite key.

    column_name: single col (e.g. "id_order") or "*" for composite
    params: None → use column_name
            {"columns": ["col_a", "col_b"]} → composite key
    """
    df = spark.table(table_name)

    if params and "columns" in params:
        cols = params["columns"]
    else:
        cols = [column_name]

    total = df.count()
    distinct = df.select(*cols).distinct().count()
    dup_count = total - distinct

    return {
        "passed": dup_count == 0,
        "actual_value": f"{dup_count:,} duplicates / {total:,} rows",
        "expected_value": "0 duplicates",
    }


def check_row_count(table_name, column_name, params):
    """Check table has minimum row count.

    params: {"min": 1}
    """
    df = spark.table(table_name)
    actual = df.count()
    min_rows = int(params.get("min", 1)) if params else 1

    return {
        "passed": actual >= min_rows,
        "actual_value": f"{actual:,} rows",
        "expected_value": f">= {min_rows:,}",
    }


def check_freshness(table_name, column_name, params):
    """Check data freshness by finding the most recent timestamp/date column.

    params: {"max_age_hours": 48, "ts_column": "dt_invoice"}
    If ts_column not specified, auto-detect columns with dt_ or ts_ prefix.
    """
    max_age = int(params.get("max_age_hours", 48)) if params else 48
    ts_col = params.get("ts_column") if params else None

    df = spark.table(table_name)

    # Auto-detect timestamp/date column if not specified
    if not ts_col:
        candidates = [
            c.name for c in df.schema.fields
            if c.name.startswith("dt_") or c.name.startswith("ts_")
        ]
        if not candidates:
            return {
                "passed": False,
                "actual_value": "no dt_/ts_ column found",
                "expected_value": f"< {max_age}h",
                "error_message": "Cannot auto-detect timestamp column. "
                                 "Specify ts_column in check_params.",
            }
        # Pick the first candidate
        ts_col = candidates[0]

    if ts_col not in df.columns:
        return {
            "passed": False,
            "actual_value": f"column '{ts_col}' not found",
            "expected_value": f"< {max_age}h",
            "error_message": f"Column '{ts_col}' does not exist in {table_name}",
        }

    latest_val = df.agg(F.max(F.col(ts_col))).collect()[0][0]

    if latest_val is None:
        return {
            "passed": False,
            "actual_value": "NULL (no data)",
            "expected_value": f"< {max_age}h",
        }

    # Handle date vs timestamp
    if isinstance(latest_val, date) and not isinstance(latest_val, datetime):
        latest_dt = datetime.combine(latest_val, datetime.min.time(),
                                     tzinfo=timezone.utc)
    elif isinstance(latest_val, datetime):
        latest_dt = (latest_val.replace(tzinfo=timezone.utc)
                     if latest_val.tzinfo is None else latest_val)
    else:
        return {
            "passed": False,
            "actual_value": str(latest_val),
            "expected_value": f"< {max_age}h",
            "error_message": f"Cannot parse '{ts_col}' as date/timestamp",
        }

    now = datetime.now(timezone.utc)
    age_hours = (now - latest_dt).total_seconds() / 3600

    return {
        "passed": age_hours <= max_age,
        "actual_value": f"{age_hours:.1f}h (latest: {latest_dt.strftime('%Y-%m-%d %H:%M')})",
        "expected_value": f"< {max_age}h",
    }


def check_null_percent(table_name, column_name, params):
    """Check % null does not exceed threshold. Supports multi-column.

    column_name: single col or "*" for multi
    params: {"max_null_pct": 0}
            {"columns": ["col_a", "col_b"], "max_null_pct": 0}
    """
    max_pct = float(params.get("max_null_pct", 0)) if params else 0

    if params and "columns" in params:
        cols = params["columns"]
    else:
        cols = [column_name]

    df = spark.table(table_name)
    total = df.count()

    if total == 0:
        return {
            "passed": False,
            "actual_value": "0 rows",
            "expected_value": f"<= {max_pct}%",
        }

    # Check each column, report worst
    worst_pct = 0.0
    worst_col = ""
    details = []

    for col in cols:
        if col not in df.columns:
            details.append(f"{col}: NOT FOUND")
            continue
        null_count = df.filter(F.col(col).isNull()).count()
        null_pct = null_count / total * 100
        details.append(f"{col}: {null_pct:.2f}% ({null_count:,}/{total:,})")
        if null_pct > worst_pct:
            worst_pct = null_pct
            worst_col = col

    passed = worst_pct <= max_pct

    return {
        "passed": passed,
        "actual_value": " | ".join(details),
        "expected_value": f"<= {max_pct}% null",
    }

# ─── Cell 9 ───
# Cell 5 — Teams Alert

# ─── Cell 10 ───
def send_teams_alert(webhook_url, layer, run_id, failures):
    """Send failure summary to Microsoft Teams via webhook."""
    if not webhook_url:
        return

    import requests

    facts = []
    for f in failures[:10]:
        facts.append({
            "name": f.get("table_name", ""),
            "value": (f"{f.get('check_type')}: "
                      f"{f.get('error_message', 'FAILED')} "
                      f"(Severity: {f.get('severity')})"),
        })

    card = {
        "@type": "MessageCard",
        "themeColor": "FF0000",
        "summary": f"DQ Failures - {layer} layer",
        "sections": [{
            "activityTitle": f"Data Quality Alert - {layer} Layer",
            "activitySubtitle": f"Run: {run_id} | {RUN_TIMESTAMP.isoformat()}",
            "facts": facts,
            "markdown": True,
        }],
    }

    try:
        requests.post(webhook_url, json=card, timeout=10)
    except Exception as e:
        print(f"WARNING: Failed to send Teams alert: {e}")

# ─── Cell 11 ───
# Cell 6 — Main Orchestration Loop

# ─── Cell 12 ───
def run_dq_checks(dq_layer, env):
    """Fetch rules, execute checks, persist results, alert on failures."""

    CHECK_DISPATCH = {
        "uniqueness": check_uniqueness,
        "row_count": check_row_count,
        "freshness": check_freshness,
        "null_percent": check_null_percent,
    }

    # 1. Fetch active rules for this layer
    rules_df = spark.table(f"{LAKEHOUSE}.dbo.utl_dq_rules").filter(
        (F.col("layer") == dq_layer) & (F.col("is_active") == 1)
    )
    rules = rules_df.collect()

    print(f"{'=' * 60}")
    print(f"DQ Engine: {len(rules)} rules for layer {dq_layer}")
    print(f"Run ID: {RUN_ID}")
    print(f"{'=' * 60}")

    if len(rules) == 0:
        print(f"No active DQ rules found for layer {dq_layer}. Skipping.")
        notebookutils.notebook.exit(f"skipped:no_rules_for_{dq_layer}")
        return

    # 2. Execute each rule
    results = []
    critical_failures = []

    for rule in rules:
        check_type = rule["check_type"]
        check_fn = CHECK_DISPATCH.get(check_type)

        if check_fn is None:
            print(f"  WARNING: Unknown check_type '{check_type}' "
                  f"for rule {rule['rule_id']}")
            continue

        start_ms = time.time() * 1000

        try:
            params = (json.loads(rule["check_params"])
                      if rule["check_params"] else {})
            outcome = check_fn(
                rule["table_name"], rule["column_name"], params
            )
            error_msg = outcome.get(
                "error_message",
                None if outcome["passed"]
                else f"{check_type} failed: actual={outcome['actual_value']}",
            )
        except Exception as e:
            outcome = {
                "passed": False,
                "actual_value": "ERROR",
                "expected_value": "N/A",
            }
            error_msg = str(e)

        elapsed_ms = int(time.time() * 1000 - start_ms)

        result = {
            "result_id": str(uuid.uuid4()),
            "run_id": RUN_ID,
            "run_timestamp": RUN_TIMESTAMP,
            "layer": dq_layer,
            "table_name": rule["table_name"],
            "rule_id": rule["rule_id"],
            "check_type": check_type,
            "column_name": rule["column_name"] or "*",
            "severity": rule["severity"],
            "passed": outcome["passed"],
            "actual_value": str(outcome.get("actual_value", "")),
            "expected_value": str(outcome.get("expected_value", "")),
            "error_message": error_msg,
            "execution_time_ms": elapsed_ms,
            "environment": env,
        }
        results.append(result)

        status = "PASS" if outcome["passed"] else "FAIL"
        print(f"  [{status}] {rule['table_name']}.{rule['column_name'] or '*'} "
              f"({check_type}, {rule['severity']}) "
              f"- {outcome.get('actual_value', '')} [{elapsed_ms}ms]")

        if not outcome["passed"] and rule["severity"] == "CRITICAL":
            critical_failures.append(result)

    # 3. Persist results to Delta table
    results_schema = StructType([
        StructField("result_id", StringType()),
        StructField("run_id", StringType()),
        StructField("run_timestamp", TimestampType()),
        StructField("layer", StringType()),
        StructField("table_name", StringType()),
        StructField("rule_id", StringType()),
        StructField("check_type", StringType()),
        StructField("column_name", StringType()),
        StructField("severity", StringType()),
        StructField("passed", BooleanType()),
        StructField("actual_value", StringType()),
        StructField("expected_value", StringType()),
        StructField("error_message", StringType()),
        StructField("execution_time_ms", LongType()),
        StructField("environment", StringType()),
    ])

    results_df = spark.createDataFrame(results, schema=results_schema)
    results_df.write.mode("append").format("delta").saveAsTable(
        f"{LAKEHOUSE}.dbo.utl_dq_results"
    )

    # 4. Summary
    total = len(results)
    passed = sum(1 for r in results if r["passed"])
    failed = total - passed
    critical_count = len(critical_failures)

    print(f"\n{'=' * 60}")
    print(f"DQ Summary: {passed}/{total} passed, {failed} failed "
          f"({critical_count} CRITICAL)")
    print(f"{'=' * 60}")

    # 5. Send Teams alert if any failures
    all_failures = [r for r in results if not r["passed"]]
    if all_failures and TEAMS_WEBHOOK_URL:
        send_teams_alert(TEAMS_WEBHOOK_URL, dq_layer, RUN_ID, all_failures)

    # 6. Raise exception on CRITICAL failures (stops pipeline)
    if critical_failures:
        failure_tables = ", ".join(
            sorted(set(f["table_name"] for f in critical_failures))
        )
        raise Exception(
            f"DQ CRITICAL FAILURE in {dq_layer} layer: "
            f"{critical_count} critical checks failed on tables: "
            f"{failure_tables}. Run ID: {RUN_ID}"
        )

    print(f"DQ checks completed for {dq_layer}. No critical failures.")
    notebookutils.notebook.exit(f"success:{passed}/{total}")

# ─── Cell 13 ───
# Cell 7 — Execute

# ─── Cell 14 ───
run_dq_checks(DQ_LAYER, ENV)

