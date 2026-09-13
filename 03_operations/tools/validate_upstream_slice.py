#!/usr/bin/env python3
"""Check the Azure/Databricks slice against the two marts' Bronze files.

This is a contract check, not a live Databricks export.
Run from repo root:

  python3 03_operations/tools/validate_upstream_slice.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRONZE_DIRS = [
    ROOT / "02_marts/forecast_accuracy/01_bronze/01_enterprise_lakehouse",
    ROOT / "02_marts/inventory_health/01_bronze/01_enterprise_lakehouse",
]
YAML = ROOT / "03_operations/databricks/registry/sources.yaml"
NIGHT = ROOT / "03_operations/databricks/night_order.yaml"
JOBS = ROOT / "03_operations/databricks/jobs"
NOTEBOOKS = ROOT / "03_operations/databricks/notebooks"
WINDOWS = NOTEBOOKS / "_windows.py"
PROC = ROOT / "05_tools/03_gold_parity/runs/20260714T040440Z_proc_usp_IncrementalTableLoad.sql"
LANDING = ROOT / "03_operations/azure/landing.yaml"

RUNTIME = "15.4.x-scala2.12"
JO_DROP_SQL = {
    "JOENTL", "JOSEQN", "JOCODE", "JOENTT", "JODATE", "JOTIME", "JOJOB",
    "JOUSER", "JONBR", "JOPGM", "JOOBJ", "JOLIB", "JOMBR", "JOCTRR",
    "JOFLAG", "JOCCID", "JOUSPF", "JOSYNM", "JOINCDAT", "JOMINESD", "JORES",
}

# Notebooks that rewrite a date-bounded fact must use replaceWhere, not write_delta.
REPLACEWHERE_JOBS = {
    "sc_forecast_snapshot": ("replaceWhere", "dfcSnapshot", "date_range_days"),
    "sc_sales_invoices": ("replaceWhere", "InvoiceDate", "completed_month_window"),
    "sc_inventory_onhand": ("replaceWhere", "dtea", "date_range_days"),
    "sc_supply_inbound": ("replaceWhere", "OrderDate", "mo_lookback_days"),
}


def bronze_names() -> set[str]:
    names: set[str] = set()
    for folder in BRONZE_DIRS:
        for path in folder.glob("Enterprise_Lakehouse.*.sql"):
            names.add(path.stem)
    return names


def yaml_fabric() -> set[str]:
    text = YAML.read_text(encoding="utf-8")
    return set(re.findall(r"fabric:\s+(Enterprise_Lakehouse\.\S+)", text))


def yaml_job_ids() -> list[str]:
    text = YAML.read_text(encoding="utf-8")
    return re.findall(r"^\s+- id:\s+(\S+)", text, flags=re.M)


def night_crons() -> dict[str, str]:
    text = NIGHT.read_text(encoding="utf-8")
    ids = re.findall(r"^\s+- id:\s+(\S+)", text, flags=re.M)
    crons = re.findall(r'quartz:\s+"([^"]+)"', text)
    if len(ids) != len(crons):
        return {}
    return dict(zip(ids, crons))


def yaml_spark_methods() -> dict[str, str]:
    text = YAML.read_text(encoding="utf-8")
    blocks = re.split(r"\n  - id:\s+", text)
    out: dict[str, str] = {}
    for block in blocks[1:]:
        job_id = block.split()[0]
        match = re.search(r"spark:\s+(\S+)", block)
        if match:
            out[job_id] = match.group(1)
    return out


def jo_drop_from_helper() -> set[str]:
    text = (NOTEBOOKS / "_slice_io.py").read_text(encoding="utf-8")
    block = re.search(r"JO_DROP = \{([^}]+)\}", text, flags=re.S)
    if not block:
        return set()
    return set(re.findall(r'"([A-Z]+)"', block.group(1)))


def job_parameters(payload: dict) -> list[str]:
    tasks = payload.get("tasks") or []
    if not tasks:
        return []
    return list((tasks[0].get("spark_python_task") or {}).get("parameters") or [])


def cluster(payload: dict) -> dict:
    clusters = payload.get("job_clusters") or []
    if not clusters:
        return {}
    return clusters[0].get("new_cluster") or {}


def main() -> int:
    errors: list[str] = []
    bronze = bronze_names()
    yaml_src = yaml_fabric()
    missing = sorted(bronze - yaml_src)
    extra = sorted(yaml_src - bronze)
    if missing:
        errors.append(f"yaml missing Bronze: {missing}")
    if extra:
        errors.append(f"yaml extra (not in mart Bronze): {extra}")

    helper = (NOTEBOOKS / "_slice_io.py").read_text(encoding="utf-8")
    for token in ("read_current", "read_date_range", "write_replace_where"):
        if f"def {token}" not in helper:
            errors.append(f"_slice_io.py missing {token}()")
    if "from _windows import" not in helper:
        errors.append("_slice_io.py must import date windows from _windows (no Spark)")
    if not WINDOWS.is_file():
        errors.append("missing notebooks/_windows.py")
    else:
        sys.path.insert(0, str(NOTEBOOKS))
        from _windows import completed_month_window as _cmw  # type: ignore

        from datetime import datetime, timezone

        start, end = _cmw(3, datetime(2026, 9, 13, tzinfo=timezone.utc))
        if (start, end) != ("2026-06-01", "2026-09-01"):
            errors.append(
                f"ADR-011 window 2026-09-13 expected [2026-06-01, 2026-09-01) got [{start}, {end})"
            )
    landing = LANDING.read_text(encoding="utf-8")
    if "current_state:" not in landing or "dated:" not in landing:
        errors.append("landing.yaml must declare current_state and dated layouts")

    methods = yaml_spark_methods()
    if methods.get("sc_codis_orders") != "overwrite_current":
        errors.append("yaml sc_codis_orders spark must be overwrite_current (not CDC)")
    if methods.get("sc_sales_invoices") != "date_range_replacewhere":
        errors.append("yaml sc_sales_invoices spark must be date_range_replacewhere")

    job_ids = yaml_job_ids()
    if len(job_ids) != len(set(job_ids)):
        errors.append(f"duplicate job ids: {job_ids}")
    crons = night_crons()
    if set(crons) != set(job_ids):
        errors.append(f"night_order.yaml jobs != sources.yaml: {sorted(set(crons) ^ set(job_ids))}")
    for job_id in job_ids:
        job = JOBS / f"{job_id}.json"
        nb = NOTEBOOKS / f"{job_id}.py"
        if not job.is_file():
            errors.append(f"missing job json: {job.relative_to(ROOT)}")
            continue
        payload = json.loads(job.read_text(encoding="utf-8"))
        desc = str(payload.get("description", ""))
        if "[Reconstructed]" not in desc:
            errors.append(f"{job.name}: description must say [Reconstructed]")
        if payload.get("max_concurrent_runs") != 1:
            errors.append(f"{job.name}: max_concurrent_runs must be 1")
        schedule = payload.get("schedule") or {}
        if schedule.get("timezone_id") != "UTC":
            errors.append(f"{job.name}: schedule timezone must be UTC")
        expected_cron = crons.get(job_id)
        if expected_cron and schedule.get("quartz_cron_expression") != expected_cron:
            errors.append(
                f"{job.name}: cron {schedule.get('quartz_cron_expression')} "
                f"!= night_order.yaml {expected_cron}"
            )
        timeout = int(payload.get("timeout_seconds") or 0)
        if timeout < 600:
            errors.append(f"{job.name}: timeout_seconds too small")
        params = job_parameters(payload)
        if "--catalog" not in params or "edw_dev" not in params:
            errors.append(f"{job.name}: parameters must pass --catalog edw_dev")
        py = (payload.get("tasks") or [{}])[0].get("spark_python_task", {}).get("python_file")
        if py != f"notebooks/{job_id}.py":
            errors.append(f"{job.name}: python_file must be notebooks/{job_id}.py")
        cl = cluster(payload)
        if cl.get("spark_version") != RUNTIME:
            errors.append(f"{job.name}: spark_version must be {RUNTIME}")
        if not cl.get("autotermination_minutes"):
            errors.append(f"{job.name}: autotermination_minutes required (jobs compute EXIT)")
        if cl.get("data_security_mode") != "USER_ISOLATION":
            errors.append(f"{job.name}: data_security_mode USER_ISOLATION")
        if job_id == "sc_forecast_snapshot":
            if "--date_range_days" not in params or "30" not in params:
                errors.append("sc_forecast_snapshot.json must pin --date_range_days 30")
            if cl.get("runtime_engine") != "PHOTON":
                errors.append("sc_forecast_snapshot.json should use PHOTON (11B snapshot)")

        if not nb.is_file():
            errors.append(f"missing notebook: {nb.relative_to(ROOT)}")
            continue
        body = nb.read_text(encoding="utf-8")
        if "[Reconstructed]" not in body[:500]:
            errors.append(f"{nb.name}: notebook must say [Reconstructed]")
        if "read.table" in body and "_raw" in body:
            errors.append(f"{nb.name}: must read ADLS via _slice_io, not UC *_raw tables")
        if job_id in REPLACEWHERE_JOBS:
            _, date_col, helper_name = REPLACEWHERE_JOBS[job_id]
            if "write_replace_where" not in body:
                errors.append(f"{nb.name}: date-bounded fact must call write_replace_where")
            if date_col not in body:
                errors.append(f"{nb.name}: missing date column {date_col}")
            if helper_name not in body:
                errors.append(f"{nb.name}: missing window helper {helper_name}")
        if job_id == "sc_sales_invoices" and "write_delta(" in body:
            errors.append("sc_sales_invoices.py must not write_delta (would drop older months)")
        if job_id == "sc_forecast_snapshot" and "write_delta(" in body:
            errors.append("sc_forecast_snapshot.py must not write_delta the 11B table")
        if job_id == "sc_transfers_cdc":
            if "JOENTT" not in body or "UP" not in body:
                errors.append("sc_transfers_cdc.py must filter JOENTT UP/PX/PT")
            if "DL" in body and "does not pretend" not in body:
                errors.append("sc_transfers_cdc.py must not implement DL/UB deletes")

    jo = jo_drop_from_helper()
    if jo != JO_DROP_SQL:
        errors.append(f"JO_DROP drift vs usp_IncrementalTableLoad: {sorted(jo ^ JO_DROP_SQL)}")
    if not PROC.is_file():
        errors.append(f"CDC proc snapshot missing: {PROC.relative_to(ROOT)}")

    print(f"bronze={len(bronze)} yaml={len(yaml_src)} jobs={len(job_ids)}")
    if errors:
        print("FAIL")
        for row in errors:
            print(f"  {row}")
        return 1
    print("PASS slice contract (reconstructed jobs; not a live Databricks export)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
