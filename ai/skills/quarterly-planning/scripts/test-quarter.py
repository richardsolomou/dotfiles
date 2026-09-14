"""Tests for quarter.py quarter detection and bounds logic."""

import importlib.util
from datetime import date
from pathlib import Path

# The module uses a name that's fine to import directly, but load it by path so
# tests work regardless of the current working directory.
_spec = importlib.util.spec_from_file_location(
    "quarter", Path(__file__).resolve().parent / "quarter.py"
)
assert _spec is not None and _spec.loader is not None
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
quarter_of = _mod.quarter_of
quarter_bounds = _mod.quarter_bounds
next_quarter = _mod.next_quarter
compute = _mod.compute
to_tsv = _mod.to_tsv


# --- quarter_of ---


def test_quarter_of_boundaries():
    assert quarter_of(date(2026, 1, 1)) == 1
    assert quarter_of(date(2026, 3, 31)) == 1
    assert quarter_of(date(2026, 4, 1)) == 2
    assert quarter_of(date(2026, 6, 30)) == 2
    assert quarter_of(date(2026, 7, 1)) == 3
    assert quarter_of(date(2026, 9, 30)) == 3
    assert quarter_of(date(2026, 10, 1)) == 4
    assert quarter_of(date(2026, 12, 31)) == 4


# --- quarter_bounds ---


def test_quarter_bounds_q1():
    assert quarter_bounds(2026, 1) == (date(2026, 1, 1), date(2026, 3, 31))


def test_quarter_bounds_q2():
    assert quarter_bounds(2026, 2) == (date(2026, 4, 1), date(2026, 6, 30))


def test_quarter_bounds_q3():
    assert quarter_bounds(2026, 3) == (date(2026, 7, 1), date(2026, 9, 30))


def test_quarter_bounds_q4_ends_on_dec_31():
    assert quarter_bounds(2026, 4) == (date(2026, 10, 1), date(2026, 12, 31))


# --- next_quarter ---


def test_next_quarter_within_year():
    assert next_quarter(2026, 1) == (2026, 2)
    assert next_quarter(2026, 3) == (2026, 4)


def test_next_quarter_wraps_year():
    assert next_quarter(2026, 4) == (2027, 1)


# --- compute ---


def test_compute_mid_quarter():
    ctx = compute(date(2026, 6, 15))
    assert ctx["cur_label"] == "Q2 2026"
    assert ctx["cur_start"] == date(2026, 4, 1)
    assert ctx["cur_end"] == date(2026, 6, 30)
    assert ctx["next_label"] == "Q3 2026"
    assert ctx["next_start"] == date(2026, 7, 1)
    assert ctx["next_end"] == date(2026, 9, 30)
    assert ctx["days_until_cur_end"] == 15


def test_compute_year_boundary():
    ctx = compute(date(2026, 12, 20))
    assert ctx["cur_label"] == "Q4 2026"
    assert ctx["next_label"] == "Q1 2027"
    assert ctx["next_start"] == date(2027, 1, 1)
    assert ctx["days_until_cur_end"] == 11


def test_compute_last_day_of_quarter():
    ctx = compute(date(2026, 3, 31))
    assert ctx["cur_label"] == "Q1 2026"
    assert ctx["days_until_cur_end"] == 0


# --- to_tsv ---


def test_to_tsv_shape():
    tsv = to_tsv(compute(date(2026, 6, 15)))
    fields = tsv.split("\t")
    assert fields == [
        "Q2 2026", "2026-04-01", "2026-06-30",
        "Q3 2026", "2026-07-01", "2026-09-30", "15",
    ]
