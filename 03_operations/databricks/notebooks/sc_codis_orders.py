"""sc_codis_orders — [Reconstructed]

Wholesale_Codis_AFI nightly extract: EXTORD, EXTORIT, COMAST, AAORDTYP,
codatan. Treated as current-state overwrite from ADLS `current/`.

When DB2 journal is on, Fabric `usp_IncrementalTableLoad`
SourcePlatform=DB2 is the CDC path — this notebook does not MERGE journals.
"""

import argparse

from _slice_io import read_current, spark, write_delta

TABLES = [
    "extord",
    "extorit",
    "comast",
    "aaordtyp",
    "codatan",
]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="edw_dev")
    args = p.parse_args()
    ss = spark()
    schema = "wholesale_codis_afi"
    for table in TABLES:
        df = read_current(ss, schema, table)
        write_delta(df, args.catalog, schema, table)


if __name__ == "__main__":
    main()
