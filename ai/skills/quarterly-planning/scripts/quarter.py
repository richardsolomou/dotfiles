#!/usr/bin/env python3
"""Compute the current and next calendar quarter and the key planning dates.

PostHog uses calendar quarters: Q1 Jan–Mar, Q2 Apr–Jun, Q3 Jul–Sep, Q4 Oct–Dec.
Quarterly planning runs in the closing weeks of a quarter to set goals for the
quarter that follows, so this reports both the current quarter (the one being
reviewed) and the next quarter (the one being planned), plus how many days are
left in the current quarter.

Usage: python3 quarter.py [YYYY-MM-DD]   (defaults to today)

Output (tab-separated, single line):
  cur_label\tcur_start\tcur_end\tnext_label\tnext_start\tnext_end\tdays_until_cur_end
"""

import sys
from datetime import date, datetime, timedelta


def quarter_of(d):
    """Return the calendar quarter (1-4) containing date d."""
    return (d.month - 1) // 3 + 1


def quarter_bounds(year, q):
    """Return (start, end) dates for quarter q of the given year, inclusive."""
    start_month = (q - 1) * 3 + 1
    start = date(year, start_month, 1)
    if q == 4:
        end = date(year, 12, 31)
    else:
        end = date(year, start_month + 3, 1) - timedelta(days=1)
    return start, end


def next_quarter(year, q):
    """Return (year, quarter) of the quarter following q."""
    if q == 4:
        return year + 1, 1
    return year, q + 1


def label(year, q):
    return f"Q{q} {year}"


def compute(today):
    """Build the planning context for the quarter containing today."""
    q = quarter_of(today)
    cur_start, cur_end = quarter_bounds(today.year, q)
    ny, nq = next_quarter(today.year, q)
    next_start, next_end = quarter_bounds(ny, nq)
    return {
        "cur_label": label(today.year, q),
        "cur_start": cur_start,
        "cur_end": cur_end,
        "next_label": label(ny, nq),
        "next_start": next_start,
        "next_end": next_end,
        "days_until_cur_end": (cur_end - today).days,
    }


def to_tsv(ctx):
    return "\t".join([
        ctx["cur_label"],
        ctx["cur_start"].isoformat(),
        ctx["cur_end"].isoformat(),
        ctx["next_label"],
        ctx["next_start"].isoformat(),
        ctx["next_end"].isoformat(),
        str(ctx["days_until_cur_end"]),
    ])


def main():
    if len(sys.argv) > 1:
        today = datetime.strptime(sys.argv[1], "%Y-%m-%d").date()
    else:
        today = date.today()
    print(to_tsv(compute(today)))


if __name__ == "__main__":
    main()
