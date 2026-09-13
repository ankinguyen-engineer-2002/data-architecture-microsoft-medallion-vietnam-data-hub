"""sc_inventory_onhand — [Reconstructed]

ItemBalance / ITEMBL / ITMRVA = current book on-hand from ADLS `current/`.
Negative quantities are a source fact (do not 'fix' in Spark).

ATPWeekEnding: InsertedVersion=2 only; do not emit ATP-now
(removed from Inventory Gold 2026-06-01).

DemandInventorySnapshotDaily is a **daily history** (Silver keys off `dtea`).
Use 30-day replaceWhere — a full overwrite would restatement the series.
"""

import argparse

from pyspark.sql import functions as F

from _slice_io import (
    lookback_start,
    read_current,
    read_date_range,
    spark,
    utc_today,
    write_delta,
    write_replace_where,
)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="edw_dev")
    p.add_argument("--date_range_days", type=int, default=30)
    args = p.parse_args()
    ss = spark()

    bal = read_current(ss, "inventory_enh_history", "itembalance")
    write_delta(bal, args.catalog, "inventory_enh_history", "itembalance")

    atp = read_current(ss, "supplychain_enh", "atpweekending").where(
        F.col("InsertedVersion") == F.lit(2)
    )
    write_delta(atp, args.catalog, "supplychain_enh", "atpweekending")

    for schema, table in (
        ("itemmaster_afi", "itembl"),
        ("itemmaster_afi", "itmrva"),
    ):
        write_delta(read_current(ss, schema, table), args.catalog, schema, table)

    start = lookback_start(args.date_range_days)
    end = utc_today()
    din = read_date_range(ss, "supplychain_enh", "demandinventorysnapshotdaily", start, end)
    write_replace_where(
        din,
        args.catalog,
        "supplychain_enh",
        "demandinventorysnapshotdaily",
        f"dtea >= '{start}' AND dtea < '{end}'",
    )


if __name__ == "__main__":
    main()
