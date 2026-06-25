#!/usr/bin/env python3
"""Split mart aggregate SQL into layer/object files.

This is a one-time repo housekeeping helper. It preserves the original aggregate
SQL by moving each mart's old aggregate `sql/` folder into
`99_history/aggregate_sql_pre_layer_split/`.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

SECTION_RE = re.compile(r"(?m)^-- ----\s+(.+?)\s+----.*$")
CREATE_RE = re.compile(
    r"(?is)\bCREATE\s+(?:OR\s+ALTER\s+)?(?:VIEW|TABLE)\s+([\[\]\w.]+)"
)
ENTERPRISE_RE = re.compile(
    r"(?:\[Enterprise_Lakehouse\]\.\[([^\]]+)\]\.\[([^\]]+)\]|Enterprise_Lakehouse\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+))"
)
SUPPLYCHAIN_RE = re.compile(
    r"(?:\[SupplyChain_Lakehouse\]\.\[([^\]]+)\]\.\[([^\]]+)\]|SupplyChain_Lakehouse\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+))"
)


def ensure(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def clean_object_name(raw: str) -> str:
    raw = raw.strip()
    raw = raw.split("(")[0].strip()
    raw = raw.replace("[", "").replace("]", "")
    raw = raw.replace(" (BOB source wrapper)", "")
    raw = raw.replace(" (canonical BOB target table)", "")
    return raw


def file_for_object(folder: Path, object_name: str) -> Path:
    return folder / f"{clean_object_name(object_name)}.sql"


def split_sections(source: Path, dest: Path, include_filter: str | None = None) -> list[Path]:
    text = source.read_text(encoding="utf-8")
    matches = list(SECTION_RE.finditer(text))
    written: list[Path] = []
    if not matches:
        return written

    for idx, match in enumerate(matches):
        start = match.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        block = text[start:end].strip() + "\n"
        title = clean_object_name(match.group(1))
        if include_filter and include_filter not in title:
            continue
        create_match = CREATE_RE.search(block)
        object_name = clean_object_name(create_match.group(1) if create_match else title)
        path = file_for_object(dest, object_name)
        path.write_text(block, encoding="utf-8")
        written.append(path)
    return written


def write_shortcut_file(folder: Path, source: str, mart: str) -> Path:
    ensure(folder)
    path = file_for_object(folder, source)
    path.write_text(
        f"-- {source}\n"
        f"-- Layer: Bronze/source shortcut reference for mart `{mart}`.\n"
        "-- This is not a local view/table definition in this repo.\n"
        "-- It documents the upstream Fabric Lakehouse object used by downstream views/registry lineage.\n",
        encoding="utf-8",
    )
    return path


def collect_sources(paths: list[Path], regex: re.Pattern[str], prefix: str) -> set[str]:
    found: set[str] = set()
    for path in paths:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for match in regex.finditer(text):
            schema = match.group(1) or match.group(3)
            table = match.group(2) or match.group(4)
            found.add(f"{prefix}.{schema}.{table}")
    return found


def write_readme(path: Path, title: str, body: str) -> None:
    path.write_text(f"# {title}\n\n{body.strip()}\n", encoding="utf-8")


def restructure_forecast() -> None:
    mart = ROOT / "02_marts" / "forecast_accuracy"
    sql = mart / "sql"
    for folder in [
        mart / "01_bronze" / "01_enterprise_lakehouse",
        mart / "01_bronze" / "02_supplychain_lakehouse",
        mart / "00_source_wrk" / "processing_seed",
        mart / "00_source_wrk" / "staging_wrk",
        mart / "02_silver",
        mart / "03_gold",
    ]:
        ensure(folder)

    split_sections(sql / "staging_ddl.sql", mart / "00_source_wrk" / "staging_wrk")
    split_sections(sql / "silver_views.sql", mart / "02_silver")
    split_sections(sql / "gold_views.sql", mart / "03_gold")

    # Manual target table note that appears as comments in staging_ddl.
    (mart / "00_source_wrk" / "staging_wrk" / "Staging.DemandForecastSnapshotDaily.sql").write_text(
        "-- Staging.DemandForecastSnapshotDaily\n"
        "-- Canonical BOB target table materialized from Staging_Wrk.v_DemandForecastSnapshotDaily.\n"
        "-- Loader: ETL_Framework.DW_Developer.usp_IncrementalTableLoad.\n"
        "-- UpdateMethod: DateRange. DateKey: dfcSnapshot. Window: 30 days.\n",
        encoding="utf-8",
    )

    source_files = [sql / "staging_ddl.sql", sql / "silver_views.sql", sql / "gold_views.sql"]
    enterprise_sources = collect_sources(source_files, ENTERPRISE_RE, "Enterprise_Lakehouse")
    # Registry-only live sources that do not appear in current object SQL text.
    enterprise_sources.update(
        {
            "Enterprise_Lakehouse.Customers.AccountMaster",
            "Enterprise_Lakehouse.Customers.ShippingLocations",
            "Enterprise_Lakehouse.MasterData_DW.DimDate",
            "Enterprise_Lakehouse.MasterData_DW.DimItemMaster",
            "Enterprise_Lakehouse.SalesHistory_AFI.InvoiceDetail",
            "Enterprise_Lakehouse.SalesHistory_AFI.InvoiceHeader",
            "Enterprise_Lakehouse.SupplyChain_Enh.DemandForecastSnapshotDaily",
            "Enterprise_Lakehouse.Wholesale_Codis_AFI.AAORDTYP",
            "Enterprise_Lakehouse.Wholesale_Codis_AFI.COMAST",
            "Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORD",
            "Enterprise_Lakehouse.Wholesale_Codis_AFI.EXTORIT",
            "Enterprise_Lakehouse.Wholesale_Codis_AFI.codatan",
            "Enterprise_Lakehouse.Wholesale_ProductSourcing_AFI.CustomerGrouping",
        }
    )
    for source in sorted(enterprise_sources):
        write_shortcut_file(mart / "01_bronze" / "01_enterprise_lakehouse", source, "forecast_accuracy")

    write_readme(
        mart / "01_bronze" / "02_supplychain_lakehouse" / "README.md",
        "SupplyChain Lakehouse",
        "No active Forecast Accuracy runtime source uses `SupplyChain_Lakehouse` after the 2026-06-23 live check.\n\n"
        "Historical `_edw`/Dataflow Gen2 source notes are preserved under `99_history/aggregate_sql_pre_layer_split/` and `99_archive/`.",
    )
    write_shortcut_file(mart / "00_source_wrk" / "processing_seed", "ProcessingSeed.ForecastCycle", "forecast_accuracy")
    write_shortcut_file(mart / "00_source_wrk" / "processing_seed", "ProcessingSeed.ForecastHorizon", "forecast_accuracy")


def restructure_inventory() -> None:
    mart = ROOT / "02_marts" / "inventory_health"
    sql = mart / "sql"
    for folder in [
        mart / "01_bronze" / "01_enterprise_lakehouse",
        mart / "01_bronze" / "02_supplychain_lakehouse",
        mart / "00_source_wrk" / "staging_wrk",
        mart / "02_silver",
        mart / "03_gold",
    ]:
        ensure(folder)

    # These aggregate files include active, inactive, and historical/candidate objects.
    split_sections(sql / "staging_ddl.sql", mart / "00_source_wrk" / "staging_wrk")
    split_sections(sql / "silver_views.sql", mart / "02_silver")
    split_sections(sql / "gold_views.sql", mart / "03_gold")

    source_files = [
        sql / "staging_ddl.sql",
        sql / "silver_views.sql",
        sql / "gold_views.sql",
        sql / "registry_inserts.sql",
        sql / "mart_b_da_refactor_candidate_20260527.sql",
    ]
    for source in sorted(collect_sources(source_files, ENTERPRISE_RE, "Enterprise_Lakehouse")):
        write_shortcut_file(mart / "01_bronze" / "01_enterprise_lakehouse", source, "inventory_health")

    supplychain_sources = collect_sources(source_files, SUPPLYCHAIN_RE, "SupplyChain_Lakehouse")
    for source in sorted(supplychain_sources):
        path = write_shortcut_file(mart / "01_bronze" / "02_supplychain_lakehouse", source, "inventory_health")
        existing = path.read_text(encoding="utf-8")
        path.write_text(
            existing
            + "-- Current note: this source is a SupplyChain_Lakehouse/Dataflow Gen2 path or historical fallback.\n",
            encoding="utf-8",
        )
    write_readme(
        mart / "01_bronze" / "02_supplychain_lakehouse" / "README.md",
        "SupplyChain Lakehouse",
        "Files here document SupplyChain_Lakehouse/Dataflow Gen2 or historical fallback sources.\n\n"
        "If there is no local view definition, the file intentionally contains source notes only.",
    )


def archive_aggregate_sql(mart: Path) -> None:
    sql = mart / "sql"
    if not sql.exists():
        return
    dest = mart / "99_history" / "aggregate_sql_pre_layer_split"
    ensure(dest.parent)
    if dest.exists():
        # Preserve previous run if any.
        suffix = 1
        while (mart / "99_history" / f"aggregate_sql_pre_layer_split_{suffix}").exists():
            suffix += 1
        dest = mart / "99_history" / f"aggregate_sql_pre_layer_split_{suffix}"
    shutil.move(str(sql), str(dest))


def write_layer_readmes() -> None:
    for mart_name in ["forecast_accuracy", "inventory_health"]:
        mart = ROOT / "02_marts" / mart_name
        write_readme(
            mart / "00_source_wrk" / "README.md",
            "Source / Working Views",
            "This folder contains source-side SQL objects such as Processing-owned seeds and `Staging_Wrk` wrappers.\n\n"
            "Object files are named with the fully qualified object name so the dependency path is visible from the file tree.",
        )
        write_readme(
            mart / "01_bronze" / "README.md",
            "Bronze Sources",
            "Bronze files document upstream source objects. `01_enterprise_lakehouse/` contains Enterprise Lakehouse shortcut references. "
            "`02_supplychain_lakehouse/` contains SupplyChain Lakehouse/Dataflow Gen2 or historical fallback references when applicable.",
        )
        write_readme(
            mart / "02_silver" / "README.md",
            "Silver Objects",
            "Each `.sql` file is one view/table definition or source object note for this layer.",
        )
        write_readme(
            mart / "03_gold" / "README.md",
            "Gold Objects",
            "Each `.sql` file is one view/table definition for this serving layer.",
        )


def main() -> None:
    restructure_forecast()
    restructure_inventory()
    write_layer_readmes()
    archive_aggregate_sql(ROOT / "02_marts" / "forecast_accuracy")
    archive_aggregate_sql(ROOT / "02_marts" / "inventory_health")


if __name__ == "__main__":
    main()
