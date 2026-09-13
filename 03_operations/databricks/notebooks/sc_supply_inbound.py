"""sc_supply_inbound — [Reconstructed]

PO snapshot, Logility container, supply plan: current-state extracts
(Fabric Silver then builds historical helpers — run_order overwrite).

MOMAST: Inventory run_order ManufacturingOrderSnapshotDaily = incremental.
This notebook uses a 14-day replaceWhere on OrderDate as the Spark stand-in
for that incremental contract. Not a DB2 journal MERGE (see sc_transfers_cdc).
"""

import argparse

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
    p.add_argument("--mo_lookback_days", type=int, default=14)
    args = p.parse_args()
    ss = spark()

    write_delta(
        read_current(ss, "supplychain_enh", "purchaseordersnapshot"),
        args.catalog,
        "supplychain_enh",
        "purchaseordersnapshot",
    )
    write_delta(
        read_current(ss, "supplychain_enh", "demandfulfillmentcommoncontainer_logility"),
        args.catalog,
        "supplychain_enh",
        "demandfulfillmentcommoncontainer_logility",
    )
    write_delta(
        read_current(ss, "supplychain_enh", "supplyplandetailsnapshotdaily"),
        args.catalog,
        "supplychain_enh",
        "supplyplandetailsnapshotdaily",
    )

    start = lookback_start(args.mo_lookback_days)
    end = utc_today()
    mo = read_date_range(
        ss, "manufacturing_productionplanning_afi", "momast", start, end
    )
    write_replace_where(
        mo,
        args.catalog,
        "manufacturing_productionplanning_afi",
        "momast",
        f"OrderDate >= '{start}' AND OrderDate < '{end}'",
    )


if __name__ == "__main__":
    main()
