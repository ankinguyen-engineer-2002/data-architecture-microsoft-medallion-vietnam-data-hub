#!/usr/bin/env python3
"""Remove generated __generated_source_wrapper wrappers from active SQL view files.

This is intentionally narrow: it only unwraps the generated pattern created
during the Enterprise _Wrk migration, preserving the inner business SELECT and
moving LoadDT into that SELECT when the wrapper had added it.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess


def iter_code_positions(text: str):
    i = 0
    depth = 0
    state = "code"
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if ch == "-" and nxt == "-":
                state = "line_comment"
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if ch == "'":
                state = "string"
                i += 1
                continue
            if ch == "[":
                state = "bracket"
                i += 1
                continue
            if ch == "(":
                depth += 1
            elif ch == ")" and depth > 0:
                depth -= 1
            yield i, ch, depth
            i += 1
            continue
        if state == "line_comment":
            if ch in "\r\n":
                state = "code"
            i += 1
            continue
        if state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue
        if state == "string":
            if ch == "'" and nxt == "'":
                i += 2
            elif ch == "'":
                state = "code"
                i += 1
            else:
                i += 1
            continue
        if state == "bracket":
            if ch == "]":
                state = "code"
            i += 1


def token_at(text: str, idx: int, token: str) -> bool:
    end = idx + len(token)
    if text[idx:end].upper() != token.upper():
        return False
    before_ok = idx == 0 or not (text[idx - 1].isalnum() or text[idx - 1] == "_")
    after_ok = end >= len(text) or not (text[end].isalnum() or text[end] == "_")
    return before_ok and after_ok


def find_top_level_token(text: str, token: str, start: int = 0) -> int | None:
    for idx, _, depth in iter_code_positions(text[start:]):
        actual = start + idx
        if depth == 0 and token_at(text, actual, token):
            return actual
    return None


def find_matching_paren(text: str, open_idx: int) -> int | None:
    depth = 0
    state = "code"
    i = open_idx
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if ch == "-" and nxt == "-":
                state = "line_comment"
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if ch == "'":
                state = "string"
                i += 1
                continue
            if ch == "[":
                state = "bracket"
                i += 1
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i
            i += 1
            continue
        if state == "line_comment":
            if ch in "\r\n":
                state = "code"
            i += 1
            continue
        if state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue
        if state == "string":
            if ch == "'" and nxt == "'":
                i += 2
            elif ch == "'":
                state = "code"
                i += 1
            else:
                i += 1
            continue
        if state == "bracket":
            if ch == "]":
                state = "code"
            i += 1
    return None


def split_header_body(sql: str) -> tuple[str, str]:
    match = re.search(r"\bAS\b", sql, flags=re.IGNORECASE)
    if not match:
        raise ValueError("missing CREATE VIEW AS header")
    return sql[: match.end()], sql[match.end() :].strip().rstrip(";")


def select_list_has_loaddt(select_sql: str) -> bool:
    from_pos = find_top_level_token(select_sql, "FROM")
    select_list = select_sql[: from_pos if from_pos is not None else len(select_sql)]
    return (
        re.search(r"\[?LoadDT\]?\s*=", select_list, flags=re.IGNORECASE) is not None
        or re.search(r"\bAS\s+\[?LoadDT\]?\b", select_list, flags=re.IGNORECASE) is not None
        or re.search(r"\bLoadDT\b", select_list, flags=re.IGNORECASE) is not None
    )


def add_loaddt_to_select_segment(sql: str, select_pos: int) -> tuple[str, bool]:
    from_pos = find_top_level_token(sql, "FROM", start=select_pos)
    if from_pos is None:
        raise ValueError("cannot find top-level FROM for LoadDT insertion")
    select_list = sql[select_pos:from_pos]
    if select_list_has_loaddt(select_list):
        return sql, False
    return (
        sql[:from_pos].rstrip()
        + ",\n    CAST(SYSUTCDATETIME() AS datetime2(6)) AS [LoadDT]\n"
        + sql[from_pos:].lstrip(),
        True,
    )


def add_loaddt_to_top_level_selects(sql: str) -> str:
    select_positions = [
        idx for idx, _, depth in iter_code_positions(sql) if depth == 0 and token_at(sql, idx, "SELECT")
    ]
    if not select_positions:
        raise ValueError("cannot find top-level SELECT for LoadDT insertion")

    first_from = find_top_level_token(sql, "FROM", start=select_positions[0])
    if first_from is not None and select_list_has_loaddt(sql[select_positions[0] : first_from]):
        # For UNION queries, the first branch defines the output column names.
        # If it already exposes LoadDT, the sibling branches already carry the
        # same ordinal expression even when they do not repeat the alias.
        return sql

    updated = sql
    for select_pos in reversed(select_positions):
        updated, _ = add_loaddt_to_select_segment(updated, select_pos)
    return updated


def unwrap_generated_source_wrapper(sql: str) -> tuple[str, bool]:
    header, body = split_header_body(sql)
    match = re.search(r"\b__generated_source_wrapper\b\s+AS\s*\(", body, flags=re.IGNORECASE)
    if not match:
        return sql, False
    open_idx = body.find("(", match.start())
    close_idx = find_matching_paren(body, open_idx)
    if close_idx is None:
        raise ValueError("cannot find closing parenthesis for __generated_source_wrapper")

    source_sql = body[open_idx + 1 : close_idx].strip().rstrip(";")
    wrapper_tail = body[close_idx + 1 :].strip().rstrip(";")
    wrapper_added_loaddt = (
        re.search(r"\[?LoadDT\]?\s*=", wrapper_tail, flags=re.IGNORECASE) is not None
        or re.search(r"\bAS\s+\[?LoadDT\]?\b", wrapper_tail, flags=re.IGNORECASE) is not None
    )
    if wrapper_added_loaddt:
        source_sql = add_loaddt_to_top_level_selects(source_sql)

    prefix = body[: match.start()].rstrip()
    if prefix.endswith(","):
        prefix = prefix[:-1].rstrip()
    if prefix.strip().upper() == "WITH":
        new_body = source_sql
    else:
        new_body = prefix + "\n" + source_sql
    return header + "\n" + new_body.strip() + ";\n", True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument(
        "--from-git-head",
        action="store_true",
        help="Regenerate changed files from HEAD content instead of current working tree content.",
    )
    args = parser.parse_args()

    repo = pathlib.Path(args.repo_root).resolve()
    roots = [repo / "02_marts", repo / "03_operations" / "deployment" / "sqlproj"]
    changed: list[pathlib.Path] = []
    candidates: list[pathlib.Path] = []
    if args.from_git_head:
        raw = subprocess.check_output(
            ["git", "ls-files", "02_marts", "03_operations/deployment/sqlproj"],
            cwd=repo,
            text=True,
        )
        candidates = [repo / line for line in raw.splitlines() if line.endswith(".sql")]
    else:
        for root in roots:
            candidates.extend(root.rglob("*.sql"))

    for path in candidates:
            if args.from_git_head:
                rel = path.relative_to(repo).as_posix()
                try:
                    text = subprocess.check_output(["git", "show", f"HEAD:{rel}"], cwd=repo)
                    text = text.decode("utf-8", "ignore")
                except subprocess.CalledProcessError:
                    continue
            else:
                text = path.read_text(errors="ignore")
            if "__generated_source_wrapper" not in text:
                continue
            new_text, did_change = unwrap_generated_source_wrapper(text)
            if "__generated_source_wrapper" in new_text:
                raise RuntimeError(f"unwrap left __generated_source_wrapper in {path}")
            if did_change:
                changed.append(path)
                if args.apply:
                    path.write_text(new_text)

    print(f"files_to_change={len(changed)}")
    for path in changed:
        print(path.relative_to(repo))
    if not args.apply:
        print("dry_run=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
