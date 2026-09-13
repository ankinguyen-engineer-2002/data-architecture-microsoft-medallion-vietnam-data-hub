"""Shared IO for the SCM upstream slice.

[Reconstructed] helper used by nightly jobs. Paths follow
03_operations/azure/landing.yaml. Table names must match
02_marts/*/01_bronze/01_enterprise_lakehouse/.

Two stages, same night:
  1. Read parquet from ADLS raw/ (landing). Empty -> fail closed.
  2. Write Delta under Unity Catalog (curated). Date-bounded facts use
     replaceWhere so history outside the window is left alone.

This file is a sibling of the job notebooks (Repos / bundle include).
It is not a live workspace export.
"""

from __future__ import annotations

from pyspark.sql import SparkSession

from _windows import completed_month_window, daterange, lookback_start, utc_today

RAW = "abfss://<storage-account>.dfs.core.windows.net/supplychain"
JO_DROP = {
    "JOENTL", "JOSEQN", "JOCODE", "JOENTT", "JODATE", "JOTIME", "JOJOB",
    "JOUSER", "JONBR", "JOPGM", "JOOBJ", "JOLIB", "JOMBR", "JOCTRR",
    "JOFLAG", "JOCCID", "JOUSPF", "JOSYNM", "JOINCDAT", "JOMINESD", "JORES",
}


def spark() -> SparkSession:
    return SparkSession.builder.getOrCreate()


def raw_path(domain: str, table: str, dt: str) -> str:
    return f"{RAW}/{domain}/{table}/dt={dt}"


def current_path(domain: str, table: str) -> str:
    return f"{RAW}/{domain}/{table}/current"


def require_nonempty(df, label: str):
    if df.take(1) == []:
        raise RuntimeError(f"empty partition, refuse overwrite: {label}")
    return df


def read_current(ss: SparkSession, domain: str, table: str):
    path = current_path(domain, table)
    return require_nonempty(ss.read.parquet(path), path)


def read_partition(ss: SparkSession, domain: str, table: str, dt: str):
    path = raw_path(domain, table, dt)
    return require_nonempty(ss.read.parquet(path), path)


def read_date_range(ss: SparkSession, domain: str, table: str, start: str, end_exclusive: str):
    paths = [raw_path(domain, table, dt) for dt in daterange(start, end_exclusive)]
    if not paths:
        raise RuntimeError(f"empty date window {domain}.{table} [{start}, {end_exclusive})")
    df = ss.read.option("ignoreMissingFiles", "true").parquet(*paths)
    return require_nonempty(df, f"{domain}.{table} [{start}, {end_exclusive})")


def write_delta(df, catalog: str, schema: str, table: str, mode: str = "overwrite") -> None:
    """Current-state overwrite. Do not use for date-bounded facts."""
    (
        df.write.format("delta")
        .mode(mode)
        .option("overwriteSchema", "false")
        .saveAsTable(f"{catalog}.{schema}.{table}")
    )


def write_replace_where(df, catalog: str, schema: str, table: str, predicate: str) -> None:
    if not predicate or ">=" not in predicate:
        raise RuntimeError(f"replaceWhere predicate required for {schema}.{table}")
    require_nonempty(df, f"{catalog}.{schema}.{table} {predicate}")
    (
        df.write.format("delta")
        .mode("overwrite")
        .option("replaceWhere", predicate)
        .option("overwriteSchema", "false")
        .saveAsTable(f"{catalog}.{schema}.{table}")
    )


def drop_journal_cols(df):
    keep = [c for c in df.columns if c.upper() not in JO_DROP]
    return df.select(*keep)
