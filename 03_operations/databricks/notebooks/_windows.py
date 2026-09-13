"""Date windows for the SCM slice. No Spark import — CI can call this.

[Reconstructed] helper. ADR-011 uses last N fully completed UTC months.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone


def utc_today(now: datetime | None = None) -> str:
    stamp = now or datetime.now(timezone.utc)
    return stamp.strftime("%Y-%m-%d")


def lookback_start(days: int, now: datetime | None = None) -> str:
    stamp = now or datetime.now(timezone.utc)
    return (stamp - timedelta(days=days)).strftime("%Y-%m-%d")


def add_months(d: date, months: int) -> date:
    month0 = d.month - 1 + months
    year = d.year + month0 // 12
    month = month0 % 12 + 1
    return date(year, month, 1)


def completed_month_window(months: int = 3, now: datetime | None = None) -> tuple[str, str]:
    """Last `months` fully completed UTC calendar months.

    Half-open [start, end_exclusive). Current incomplete month is excluded.
    Example: 2026-09-13 → [2026-06-01, 2026-09-01).
    """
    if months < 1:
        raise ValueError("months must be >= 1")
    stamp = now or datetime.now(timezone.utc)
    today = stamp.date()
    end = date(today.year, today.month, 1)
    start = add_months(end, -months)
    return start.isoformat(), end.isoformat()


def daterange(start: str, end_exclusive: str):
    cur = datetime.strptime(start, "%Y-%m-%d").date()
    end = datetime.strptime(end_exclusive, "%Y-%m-%d").date()
    while cur < end:
        yield cur.strftime("%Y-%m-%d")
        cur += timedelta(days=1)
