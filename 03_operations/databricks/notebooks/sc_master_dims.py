"""sc_master_dims — [Reconstructed]

Overwrite current-state masters from ADLS `current/` (landing.yaml).
ITBEXT ~3.4M [ADR-011] is keyed by item-branch, not time — full current
snapshot is allowed. Not a date-range fact; no replaceWhere.
"""

import argparse

from _slice_io import read_current, spark, write_delta

TABLES = [
    ("masterdata_dw", "dimdate"),
    ("masterdata_dw", "dimitemmaster"),
    ("itemmaster_afi", "itbext"),
    ("itemmaster_afi", "itmext"),
    ("itemmaster_afi", "aitmcls"),
    ("masterdata_productknowledge", "item_env"),
    ("purchasing_afi", "vendormaster"),
    ("customerorders_afi", "warehousemaster"),
    ("wholesale_codis_afi", "ashleywarehousemaster"),
    ("customers", "accountmaster"),
    ("customers", "shippinglocations"),
    ("wholesale_productsourcing_afi", "customergrouping"),
    ("wholesale_productsourcing", "nonpkitems"),
]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="edw_dev")
    args = p.parse_args()
    ss = spark()
    for schema, table in TABLES:
        df = read_current(ss, schema, table)
        write_delta(df, args.catalog, schema, table)


if __name__ == "__main__":
    main()
