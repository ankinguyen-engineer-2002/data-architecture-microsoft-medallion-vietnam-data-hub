#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# Reuse proven connection + helpers from the original verifier.
import verify_de_us_status_table as base


@dataclass(frozen=True)
class Table2Item:
    raw: str
    kind: str  # "ref" | "pair"
    left: str
    right: str | None = None
    note: str | None = None


def _strip_ticks(s: str) -> str:
    s = (s or "").strip()
    if s.startswith("`") and s.endswith("`") and len(s) >= 2:
        return s[1:-1].strip()
    return s


def _schema_without_suffix_1(schema: str) -> tuple[str, str | None]:
    if schema.lower().endswith("_1"):
        return schema[:-2], f"normalized schema '{schema}' -> '{schema[:-2]}' (rule: ignore *_1 schemas)"
    return schema, None


def parse_table2_items(status_md: Path) -> list[Table2Item]:
    text = status_md.read_text(encoding="utf-8")
    anchor = "## Focus list — chỉ giữ 🟡 / 🟠 / 🔴"
    start = text.find(anchor)
    if start < 0:
        raise SystemExit(f"Unable to find Table 2 section anchor in {status_md}")

    chunk = text[start:]
    lines = chunk.splitlines()

    rows: list[str] = []
    in_table = False
    for ln in lines:
        if ln.startswith("| Dataset / Table |"):
            in_table = True
            continue
        if in_table:
            if not ln.startswith("|"):
                break
            if ln.startswith("|---"):
                continue
            parts = [c.strip() for c in ln.strip().strip("|").split("|")]
            if not parts:
                continue
            first = parts[0].strip()
            if first:
                rows.append(first)

    out: list[Table2Item] = []
    for cell in rows:
        raw = _strip_ticks(cell)
        if " vs " in raw:
            left_raw, right_raw = [p.strip() for p in raw.split(" vs ", 1)]
            # If RHS is unqualified, reuse LHS schema.
            if "." not in right_raw and "." in left_raw:
                schema = left_raw.split(".", 1)[0]
                right_raw = f"{schema}.{right_raw}"
            out.append(Table2Item(raw=raw, kind="pair", left=left_raw, right=right_raw))
            continue

        if "." in raw:
            schema, table = raw.split(".", 1)
            schema2, note = _schema_without_suffix_1(schema)
            out.append(Table2Item(raw=raw, kind="ref", left=f"{schema2}.{table}", note=note))
        else:
            out.append(Table2Item(raw=raw, kind="ref", left=raw))
    return out


def _exclude_schema_suffix_1(refs: list[base.TableRef]) -> list[base.TableRef]:
    return [r for r in refs if not r.schema.lower().endswith("_1")]


def find_tables_no1(conn_holder: dict[str, Any], name_or_like: str) -> list[base.TableRef]:
    return _exclude_schema_suffix_1(base.find_tables(conn_holder, name_or_like))


def parse_ref_no1(raw: str, conn_holder: dict[str, Any]) -> list[base.TableRef]:
    raw = (raw or "").strip()
    if not raw:
        return []
    parts = [p for p in raw.split(".") if p]
    if len(parts) == 2:
        schema, note = _schema_without_suffix_1(parts[0])
        # Return schema-normalized ref; existence validated later.
        return [base.TableRef(schema, parts[1])]
    if len(parts) == 3:
        schema, _ = _schema_without_suffix_1(parts[1])
        return [base.TableRef(schema, parts[2])]
    if len(parts) == 1:
        return find_tables_no1(conn_holder, parts[0])
    return []


def resolve_to_single(ref_raw: str, conn_holder: dict[str, Any]) -> tuple[base.TableRef | None, list[str], str | None]:
    resolved = parse_ref_no1(ref_raw, conn_holder)
    resolved = _exclude_schema_suffix_1(resolved)
    if len(resolved) == 1:
        return resolved[0], [r.display for r in resolved], None

    # If unqualified name returned multiple hits, try an exact TABLE_NAME match and prefer common schemas.
    parts = [p for p in (ref_raw or "").split(".") if p]
    if len(parts) == 1:
        candidates = find_tables_no1(conn_holder, parts[0])
        if len(candidates) == 1:
            return candidates[0], [c.display for c in candidates], None
        return None, [c.display for c in candidates], "Unable to resolve to a single table"

    return None, [r.display for r in resolved], "Unable to resolve to a single table"


def max_of(cur: Any, ref: base.TableRef, col: str) -> dict[str, Any]:
    sql = f"SELECT MAX([{col}]) AS maxv FROM {ref.fq_sql};"
    cur.execute(sql)
    v = cur.fetchone()[0]
    return {"col": col, "max": base.as_iso(v)}


def pick_date_candidates(columns: list[str], col_types: dict[str, str]) -> list[str]:
    # Return a small ordered list of candidate date columns.
    preferred = []
    patterns = [
        r"(?i)^loaddt$",
        r"(?i)^updatedt$",
        r"(?i)^updatets$",
        r"(?i)^snapshot(date)?$",
        r"(?i).*(snapshot).*",
        r"(?i)^weekending$",
        r"(?i).*(week.*end).*",
        r"(?i)^invoicedate$",
        r"(?i).*(invoice).*date$",
        r"(?i).*(date|dt)$",
        r"(?i)^trndt$",
    ]
    for pat in patterns:
        for c in columns:
            if c in preferred:
                continue
            if not re.search(pat, c):
                continue
            t = (col_types.get(c) or "").lower()
            if t in {"date", "datetime", "datetime2", "smalldatetime", "datetimeoffset", "int", "bigint", "decimal", "numeric"}:
                preferred.append(c)
    return preferred[:5]


def summarize_one_table(
    conn_holder: dict[str, Any],
    ref_raw: str,
    *,
    mode: str,
    note: str | None = None,
) -> dict[str, Any]:
    out: dict[str, Any] = {"ref": ref_raw, "note": note}
    ref, resolved_displays, err = resolve_to_single(ref_raw, conn_holder)
    out["resolved"] = resolved_displays
    if err or ref is None:
        out["error"] = err or "Unable to resolve to a single table"
        return out

    exists, exists_err = base.try_select_one(conn_holder, ref)
    out["exists"] = exists
    out["exists_error"] = exists_err
    if not exists:
        return out

    cols, cols_err = base.fetch_columns(conn_holder, ref)
    out["columns_error"] = cols_err
    out["columns"] = cols
    col_types: dict[str, str] = {}
    try:
        col_types = base.fetch_column_types(conn_holder, ref) if cols else {}
    except Exception as e:  # noqa: BLE001
        out["column_types_error"] = str(e)
    out["column_types"] = col_types

    # Freshness signals (best-effort)
    freshness_col = base.pick_freshness_col(cols, col_types)
    out["freshness_col"] = freshness_col
    today = dt.date.today()
    try:
        if freshness_col:
            cur = base.execute_with_reconnect(conn_holder, f"SELECT MAX([{freshness_col}]) FROM {ref.fq_sql};")
            maxv = cur.fetchone()[0]
            out["freshness_max"] = base.as_iso(maxv)
            out["freshness_days_since"] = base.days_since(maxv, today)
    except Exception as e:  # noqa: BLE001
        out["freshness_error"] = str(e)

    # Extra date candidates (helps when freshness_col is a business date, not a load date)
    try:
        candidates = pick_date_candidates(cols, col_types)
        out["date_candidates"] = candidates
        if candidates:
            cur = conn_holder["cn"].cursor()
            out["date_maxes"] = [max_of(cur, ref, c) for c in candidates[:3]]
    except Exception as e:  # noqa: BLE001
        out["date_candidates_error"] = str(e)

    # Targeted checks (deep mode only where it matters)
    if mode == "deep":
        table_l = ref.table.lower()

        # Generic duplicate probe (key-based, best-effort).
        # NOTE: This does NOT prove "full-row duplicates"; it only checks duplicates at a guessed grain.
        try:
            dup_patterns: list[str] | None = None
            if "invoiceheader" in table_l:
                dup_patterns = [r"(?i)^invoice.*(num|no|id|number)$", r"(?i).*(company|division|site|plant).*"]
            elif "invoicedetail" in table_l:
                dup_patterns = [
                    r"(?i)^invoice.*(num|no|id|number)$",
                    r"(?i).*(line|lineno|seq|sequence).*",
                    r"(?i).*(item|sku).*",
                ]
            elif "purchaseordersnapshot" in table_l:
                # This table appears aggregated; use stable identifier-like columns only (avoid qty/status).
                dup_patterns = [r"(?i)^possnapshot$", r"(?i)^positnbr$", r"(?i)^poswhse$", r"(?i)^posvndnr$", r"(?i)^posdued(t|ate)$"]
            elif "demandinventorysnapshotweekly" in table_l:
                dup_patterns = [r"(?i).*(snapshot).*", r"(?i).*(week.*end).*", r"(?i).*(item|sku).*", r"(?i).*(warehouse|whse|whs).*"]
            elif "demandfulfillmentcommoncontainer" in table_l:
                dup_patterns = [r"(?i).*(week.*end).*", r"(?i).*(container|cntr).*", r"(?i).*(item|sku).*", r"(?i).*(warehouse|whse|whs).*"]
            elif "supplyplandetailsnapshotdaily" in table_l:
                dup_patterns = [r"(?i).*(snapshot).*", r"(?i).*(week.*end).*", r"(?i).*(item|sku).*", r"(?i).*(warehouse|whse|whs).*"]
            elif "dimitemmaster" in table_l:
                dup_patterns = [r"(?i).*(item|sku).*id$", r"(?i).*(item|sku).*"]

            if dup_patterns:
                keys = base.key_candidates(cols, dup_patterns)
                out["dup_generic_key_cols"] = keys[:5]
                if keys:
                    out["dup_generic"] = base.duplicate_summary(conn_holder["cn"].cursor(), ref, keys[:5])
        except Exception as e:  # noqa: BLE001
            out["dup_generic_error"] = str(e)

        # ATPWeekEnding: explicit WeekEnding max + AFIFinanceDivision NULL + dup summary on key-like cols.
        if table_l == "atpweekending":
            cur = conn_holder["cn"].cursor()
            week_cols = [c for c in cols if re.search(r"(?i)week.*end", c)]
            if week_cols:
                out["weekending_col"] = week_cols[0]
                try:
                    out["weekending_max"] = max_of(cur, ref, week_cols[0])
                except Exception as e:  # noqa: BLE001
                    out["weekending_error"] = str(e)

            if "AFIFinanceDivision" in cols:
                try:
                    null_exists, null_err = base.exists_where(conn_holder, ref, "[AFIFinanceDivision] IS NULL")
                    out["afifinancedivision_null_exists"] = null_exists
                    out["afifinancedivision_null_error"] = null_err
                except Exception as e:  # noqa: BLE001
                    out["afifinancedivision_null_error"] = str(e)

            keys = base.key_candidates(cols, [r"week.*end", r"(item|itm)", r"(warehouse|whse|whs)", r"division"])
            out["dup_key_candidates"] = keys[:5]
            if keys:
                out["dup"] = base.duplicate_summary(conn_holder["cn"].cursor(), ref, keys[:5])

            # Stricter grain guess using most non-measure columns (excludes timestamps/measures).
            strict_prefer = [
                "WeekEnding",
                "ItemSKU",
                "Warehouse",
                "SeriesNumber",
                "InsertedVersion",
                "ATPWeek",
                "AFIFinanceDivision",
                "AFISalesDivision",
                "ItemGrouping",
            ]
            strict_cols = [c for c in strict_prefer if c in cols]
            if strict_cols:
                out["dup_strict_key_cols"] = strict_cols
                out["dup_strict"] = base.duplicate_summary(conn_holder["cn"].cursor(), ref, strict_cols)

        # IMHIST: future-dated probe (best-effort)
        if table_l == "imhist":
            cur = conn_holder["cn"].cursor()
            dateish = [c for c in cols if re.search(r"(?i)(date|dt)$", c) or c.lower() in {"trndt", "trndate"}]
            # Prefer TRNDT if present
            if "TRNDT" in cols:
                dateish = ["TRNDT"] + [c for c in dateish if c != "TRNDT"]
            if dateish:
                out["future_date_candidates"] = dateish[:3]
                # Numeric date columns (e.g., CYYMMDD) cannot be compared to DATE directly.
                t = (col_types.get(dateish[0]) or "").lower()
                if t in {"int", "bigint", "decimal", "numeric", "smallint", "tinyint"}:
                    # Decide format by max magnitude
                    cur.execute(f"SELECT MAX([{dateish[0]}]) FROM {ref.fq_sql};")
                    vmax = cur.fetchone()[0]
                    try:
                        vmax_i = int(vmax) if vmax is not None else None
                    except Exception:  # noqa: BLE001
                        vmax_i = None

                    today = dt.date.today()
                    yyyymmdd = int(today.strftime("%Y%m%d"))
                    cyymmdd = 1000000 + (today.year % 100) * 10000 + today.month * 100 + today.day  # 2000s only
                    cutoff = yyyymmdd if (vmax_i or 0) >= 20000000 else cyymmdd

                    sql = f"""
                        SELECT COUNT_BIG(*) AS future_rows, MAX([{dateish[0]}]) AS max_date
                        FROM {ref.fq_sql}
                        WHERE [{dateish[0]}] > ?;
                    """
                    try:
                        cur.execute(sql, (cutoff,))
                        row = cur.fetchone()
                        out["future_probe"] = {"future_date_col": dateish[0], "future_cutoff": cutoff, "future_rows": int(row[0] or 0), "future_max_date": base.as_iso(row[1])}
                    except Exception as e:  # noqa: BLE001
                        out["future_probe"] = {"future_date_col": dateish[0], "future_rows": None, "future_error": str(e)}
                else:
                    out["future_probe"] = base.count_future_dated(cur, ref, dateish[0], dt.date.today())

    return out


def summarize_pair(
    conn_holder: dict[str, Any],
    left_raw: str,
    right_raw: str,
    *,
    mode: str,
) -> dict[str, Any]:
    left, left_resolved, left_err = resolve_to_single(left_raw, conn_holder)
    right, right_resolved, right_err = resolve_to_single(right_raw, conn_holder)
    out: dict[str, Any] = {
        "pair": [left_raw, right_raw],
        "resolved_left": left_resolved,
        "resolved_right": right_resolved,
    }
    if left_err or right_err or left is None or right is None:
        out["error"] = left_err or right_err or "Unable to resolve pair to single tables"
        return out

    ok_l, err_l = base.try_select_one(conn_holder, left)
    ok_r, err_r = base.try_select_one(conn_holder, right)
    out["left_exists"] = ok_l
    out["right_exists"] = ok_r
    out["left_error"] = err_l
    out["right_error"] = err_r
    if not ok_l or not ok_r:
        return out

    left_cols, _ = base.fetch_columns(conn_holder, left)
    right_cols, _ = base.fetch_columns(conn_holder, right)
    out["left_cols"] = left_cols
    out["right_cols"] = right_cols

    left_by_lower = {c.lower(): c for c in left_cols}
    right_by_lower = {c.lower(): c for c in right_cols}

    # Try to infer join mappings even when prefixes differ (e.g., pod* vs pom*, D* vs H*).
    def map_by_prefix(l_prefix: str, r_prefix: str) -> list[tuple[str, str]]:
        pairs: list[tuple[str, str]] = []
        for l_low, l_orig in left_by_lower.items():
            if not l_low.startswith(l_prefix.lower()):
                continue
            suffix = l_low[len(l_prefix) :]
            r_low = (r_prefix.lower() + suffix)
            r_orig = right_by_lower.get(r_low)
            if r_orig:
                pairs.append((l_orig, r_orig))
        return pairs

    def map_by_strip1() -> list[tuple[str, str]]:
        # Example: DTFRNO <-> HTFRNO (strip first char)
        pairs: list[tuple[str, str]] = []
        for l_low, l_orig in left_by_lower.items():
            if len(l_low) < 2:
                continue
            suffix = l_low[1:]
            for r_low, r_orig in right_by_lower.items():
                if len(r_low) >= 2 and r_low[1:] == suffix:
                    pairs.append((l_orig, r_orig))
        return pairs

    mappings = map_by_prefix("pod", "pom") or map_by_strip1()

    # Prefer stable identifier mappings only (avoid date/status fields that would inflate "orphans").
    preferred = [
        r"(?i)(tfrno)$",
        r"(?i)(ordernum)$",
        r"(?i)(vendornum)$",
        r"(?i)(warehouse)$",
        r"(?i)(whse)$",
        r"(?i)(whs)$",
    ]
    key_mappings: list[tuple[str, str]] = []
    for pat in preferred:
        for l_col, r_col in mappings:
            if re.search(pat, l_col) or re.search(pat, r_col):
                if (l_col, r_col) not in key_mappings:
                    key_mappings.append((l_col, r_col))

    # If still empty, allow weaker fallbacks.
    if not key_mappings:
        fallback_pats = [r"(?i)(id|key)$"]
        for pat in fallback_pats:
            for l_col, r_col in mappings:
                if re.search(pat, l_col) or re.search(pat, r_col):
                    if (l_col, r_col) not in key_mappings:
                        key_mappings.append((l_col, r_col))

    # Final fallback: case-insensitive exact-name intersection.
    if not key_mappings:
        common = [left_by_lower[k] for k in (left_by_lower.keys() & right_by_lower.keys())]
        if common:
            key_mappings = [(c, c) for c in common[:1]]

    # Cap to a small join set to avoid overly strict joins.
    key_mappings = key_mappings[:3]
    out["join_key_mappings"] = key_mappings
    if not key_mappings:
        out["orphan_detail_rows"] = None
        out["orphan_error"] = "No join keys found"
        return out

    keys_sql = " AND ".join(f"d.[{l}] = m.[{r}]" for l, r in key_mappings)
    # Probe nulls on the right-hand keys (if join failed).
    null_probe = " OR ".join(f"m.[{r}] IS NULL" for _, r in key_mappings)
    try:
        if mode == "deep":
            sql_orphans = f"""
                SELECT COUNT_BIG(*) AS orphan_rows
                FROM {left.fq_sql} d
                LEFT JOIN {right.fq_sql} m
                  ON {keys_sql}
                WHERE {null_probe};
            """
            cur_orph = base.execute_with_reconnect(conn_holder, sql_orphans)
            out["orphan_detail_rows"] = int(cur_orph.fetchone()[0] or 0)
        else:
            sql_orphans = f"""
                SELECT TOP (1) 1
                FROM {left.fq_sql} d
                LEFT JOIN {right.fq_sql} m
                  ON {keys_sql}
                WHERE {null_probe};
            """
            cur_orph = base.execute_with_reconnect(conn_holder, sql_orphans)
            out["orphan_exists"] = cur_orph.fetchone() is not None
    except Exception as e:  # noqa: BLE001
        out["orphan_detail_rows"] = None
        out["orphan_error"] = str(e)

    return out


def render_md(results: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append(f"# Table 2 live scan — Enterprise_Lakehouse ({results['today']})")
    lines.append("")
    lines.append(f"- Mode: `{results['mode']}`")
    lines.append(f"- Server: `{results['server']}`")
    lines.append(f"- Database: `{results['database']}`")
    lines.append(f"- Lakehouse: `{results['lakehouse']}`")
    lines.append(f"- Source list: `{results['source_md']}`")
    lines.append("")

    for e in results["items"]:
        if "pair" in e:
            lines.append(f"## Pair: `{e['pair'][0]}` vs `{e['pair'][1]}`")
            lines.append(f"- Resolved left: `{e.get('resolved_left')}`")
            lines.append(f"- Resolved right: `{e.get('resolved_right')}`")
            if e.get("error"):
                lines.append(f"- Error: `{e['error']}`")
                lines.append("")
                continue
            lines.append(f"- Exists: left={e.get('left_exists')} right={e.get('right_exists')}")
            if e.get("orphan_detail_rows") is not None:
                lines.append(f"- Orphan detail rows: `{e['orphan_detail_rows']}` (join mappings={e.get('join_key_mappings')})")
            elif e.get("orphan_exists") is not None:
                lines.append(f"- Orphan exists: `{e['orphan_exists']}` (join mappings={e.get('join_key_mappings')})")
            if e.get("orphan_error"):
                lines.append(f"- Orphan error: `{e['orphan_error']}`")
            lines.append("")
            continue

        lines.append(f"## Table: `{e['ref']}`")
        if e.get("note"):
            lines.append(f"- Note: {e['note']}")
        lines.append(f"- Resolved: `{e.get('resolved')}`")
        if e.get("error"):
            lines.append(f"- Error: `{e['error']}`")
            lines.append("")
            continue
        lines.append(f"- Exists: `{e.get('exists')}`")
        if e.get("freshness_col"):
            lines.append(f"- Freshness: col=`{e['freshness_col']}` max=`{e.get('freshness_max')}` days_since=`{e.get('freshness_days_since')}`")
        if e.get("date_maxes"):
            lines.append(f"- Date maxes: `{e['date_maxes']}`")
        if e.get("weekending_max"):
            lines.append(f"- ATPWeekEnding WeekEnding max: `{e['weekending_max']}`")
        if e.get("afifinancedivision_null_exists") is not None:
            lines.append(f"- AFIFinanceDivision NULL exists: `{e['afifinancedivision_null_exists']}`")
        if e.get("dup"):
            lines.append(f"- Duplicates (key-based): `{e['dup']}`")
        if e.get("dup_strict"):
            lines.append(f"- Duplicates (strict-grain): `{e['dup_strict']}`")
        if e.get("dup_generic"):
            lines.append(f"- Duplicates (generic grain guess): `{e['dup_generic']}`")
        if e.get("future_probe"):
            lines.append(f"- Future-dated probe: `{e['future_probe']}`")
        if e.get("exists_error") or e.get("freshness_error"):
            lines.append(f"- Errors: `{e.get('exists_error') or e.get('freshness_error')}`")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Scan Table 2 items in Enterprise_Lakehouse (exclude *_1 schemas).")
    ap.add_argument("--mode", choices=["light", "deep"], default="deep")
    ap.add_argument(
        "--source-md",
        default="Enterprise_SupplyChain_Dev_architect/artifacts/build_runs/20260617_125319_de_us_status_verify/status_table_with_aric_check.md",
        help="Markdown file containing Table 2 (Focus list) section.",
    )
    args = ap.parse_args()

    # Sandbox-safe Azure CLI config (prevents az from writing to ~/.azure).
    if not os.environ.get("AZURE_CONFIG_DIR"):
        repo_root = Path(__file__).resolve().parents[2]
        os.environ["AZURE_CONFIG_DIR"] = str(repo_root / ".azure_user")

    source_md = Path(args.source_md)
    if not source_md.exists():
        raise SystemExit(f"Missing source markdown: {source_md}")

    run_id = dt.datetime.now().strftime("%Y%m%d_%H%M%S") + "_de_us_table2_scan"
    out_dir = Path(__file__).resolve().parents[1] / "artifacts" / "build_runs" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    items = parse_table2_items(source_md)

    results: dict[str, Any] = {
        "run_id": run_id,
        "timestamp_local": dt.datetime.now().isoformat(sep=" ", timespec="seconds"),
        "today": dt.date.today().isoformat(),
        "server": base.SERVER,
        "database": base.DATABASE,
        "lakehouse": base.LAKEHOUSE,
        "mode": args.mode,
        "source_md": str(source_md),
        "items": [],
    }

    conn_holder: dict[str, Any] = {"cn": base.connect()}
    try:
        for idx, it in enumerate(items, start=1):
            label = it.left if it.kind == "ref" else f"{it.left} vs {it.right}"
            print(f"[{idx}/{len(items)}] {label}", flush=True)

            if it.kind == "pair" and it.right:
                results["items"].append(summarize_pair(conn_holder, it.left, it.right, mode=args.mode))
                continue

            results["items"].append(summarize_one_table(conn_holder, it.left, mode=args.mode, note=it.note))
    finally:
        try:
            conn_holder["cn"].close()
        except Exception:  # noqa: BLE001
            pass

    (out_dir / "results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "results.md").write_text(render_md(results), encoding="utf-8")

    print(f"Wrote: {out_dir}/results.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
