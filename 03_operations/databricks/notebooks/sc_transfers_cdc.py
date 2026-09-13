"""sc_transfers_cdc — [Reconstructed]

Maps to Manufacturing_Inventory_AFI.TFRHDR / TFRDTL.
Inventory run_order: HoldingTransferSnapshotDaily load_type=incremental.
CDC: same JO* drop list as usp_IncrementalTableLoad.
After-images used here: JOENTT in (UP, PX, PT). Deletes (DL/UB) stay in the
T-SQL proc; this notebook does not pretend to own that branch.

Journal landing: ADLS dt=<yesterday UTC> (job runs 02:50; today's file may
still be landing).
"""

import argparse

from pyspark.sql import functions as F

from _slice_io import JO_DROP, drop_journal_cols, lookback_start, read_partition, spark


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", default="edw_dev")
    args = p.parse_args()
    ss = spark()

    yesterday = lookback_start(1)
    jn = read_partition(ss, "manufacturing_inventory_afi", "tfr_journal", yesterday)
    after = jn.where(F.upper(F.col("JOENTT")).isin("UP", "PX", "PT"))
    after = drop_journal_cols(after)
    leftover = [c for c in after.columns if c.upper() in JO_DROP]
    if leftover:
        raise RuntimeError(f"journal columns leaked: {leftover}")

    hdr = after.where(F.col("source_file") == F.lit("TFRHDR"))
    dtl = after.where(F.col("source_file") == F.lit("TFRDTL"))

    # MERGE on transfer number / line — reconstructed; live keys are DTFRNO/HTFRNO.
    hdr.createOrReplaceTempView("tfrhdr_cdc")
    dtl.createOrReplaceTempView("tfrdtl_cdc")
    ss.sql(
        f"""
        MERGE INTO {args.catalog}.manufacturing_inventory_afi.tfrhdr t
        USING tfrhdr_cdc s
        ON t.HTFRNO = s.HTFRNO
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
    )
    ss.sql(
        f"""
        MERGE INTO {args.catalog}.manufacturing_inventory_afi.tfrdtl t
        USING tfrdtl_cdc s
        ON t.DTFRNO = s.DTFRNO AND t.DITNBR = s.DITNBR
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
    )


if __name__ == "__main__":
    main()
