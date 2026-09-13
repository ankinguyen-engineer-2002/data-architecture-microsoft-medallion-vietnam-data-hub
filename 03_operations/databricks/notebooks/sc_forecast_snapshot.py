"""sc_forecast_snapshot — [Reconstructed]

Fabric staging contract:
  Target  SupplyChain_Processing_Warehouse.Staging.DemandForecastSnapshotDaily
  Method  usp_IncrementalTableLoad / DateRange / DateKey=dfcSnapshot / 30 days

Live Bronze scale [Verified ADR-011]: DemandForecastSnapshotDaily ~11.0B rows.
This job must never rewrite the full table. Reads ADLS dt= partitions for
the lookback (landing.yaml), then replaceWhere on dfcSnapshot.
"""

import argparse

from _slice_io import (
    daterange,
    lookback_start,
    raw_path,
    read_date_range,
    spark,
    utc_today,
    write_replace_where,
)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--date_range_days", type=int, default=30)
    p.add_argument("--catalog", default="edw_dev")
    args = p.parse_args()
    if args.date_range_days < 1 or args.date_range_days > 90:
        raise RuntimeError("date_range_days must be 1..90 (30 is the staging contract)")

    ss = spark()
    start = lookback_start(args.date_range_days)
    end = utc_today()
    predicate = f"dfcSnapshot >= '{start}' AND dfcSnapshot < '{end}'"
    domain = "supplychain_enh"

    src = read_date_range(ss, domain, "demandforecastsnapshotdaily", start, end)
    write_replace_where(
        src, args.catalog, domain, "demandforecastsnapshotdaily", predicate
    )

    # Weekly extract is smaller and may miss a night; do not fail the 11B job.
    weekly_paths = [
        raw_path(domain, "curfcstsnapshotweekly", dt) for dt in daterange(start, end)
    ]
    try:
        weekly = ss.read.option("ignoreMissingFiles", "true").parquet(*weekly_paths)
    except Exception:
        weekly = None
    if weekly is not None and weekly.take(1) != []:
        write_replace_where(
            weekly,
            args.catalog,
            domain,
            "curfcstsnapshotweekly",
            f"WeekEndingDate >= '{start}' AND WeekEndingDate < '{end}'",
        )


if __name__ == "__main__":
    main()
