"""sc_sales_invoices — [Reconstructed]

ADR-011: InvoiceDetail ~296.7M, InvoiceHeader ~63.2M.
DQ scans the last three **completed** UTC calendar months
(half-open [WindowStart, WindowEndExclusive); current month excluded).

Spark uses the same window and **replaceWhere** on InvoiceDate.
A filtered overwrite without replaceWhere would delete older history.
"""

import argparse

from _slice_io import completed_month_window, read_date_range, spark, write_replace_where


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--months", type=int, default=3)
    p.add_argument("--catalog", default="edw_dev")
    args = p.parse_args()
    ss = spark()

    start, end = completed_month_window(args.months)
    predicate = f"InvoiceDate >= '{start}' AND InvoiceDate < '{end}'"
    domain = "saleshistory_afi_enh"

    header = read_date_range(ss, domain, "invoiceheader", start, end)
    detail = read_date_range(ss, domain, "invoicedetail", start, end)

    write_replace_where(header, args.catalog, domain, "invoiceheader", predicate)
    write_replace_where(detail, args.catalog, domain, "invoicedetail", predicate)


if __name__ == "__main__":
    main()
