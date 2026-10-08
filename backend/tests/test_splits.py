"""Unit tests for amount parsing and the three split types (no database needed).

Docstring format used by docs/build_test_plan.py:
    TC-ID | scenario | input | expected result
"""
from decimal import Decimal

import pytest

from errors import ValidationError
from money import parse_amount, parse_percentage
from splits import compute_splits

MEMBERS = [1, 2, 3, 4, 5]


def amounts(result):
    return {r["user_id"]: r["amount_cents"] for r in result}


def test_equal_split_exact():
    """TC-SPL-01 | Equal split divides evenly | Rs 3000 between 5 members | Each share is Rs 600"""
    r = compute_splits("equal", 300000, [{"user_id": u} for u in MEMBERS], MEMBERS)
    assert set(amounts(r).values()) == {60000}
    assert sum(amounts(r).values()) == 300000


def test_equal_split_remainder_is_distributed():
    """TC-SPL-02 | Equal split with remainder | Rs 100.00 between 3 members | Shares 33.34 / 33.33 / 33.33, total exactly 100.00"""
    r = compute_splits("equal", 10000, [{"user_id": u} for u in (1, 2, 3)], MEMBERS)
    assert sorted(amounts(r).values(), reverse=True) == [3334, 3333, 3333]
    assert sum(amounts(r).values()) == 10000


def test_equal_split_subset_of_members():
    """TC-SPL-03 | Equal split among a subset | Rs 900 between members 1 and 2 only | Only those two get Rs 450"""
    r = compute_splits("equal", 90000, [{"user_id": 1}, {"user_id": 2}], MEMBERS)
    assert amounts(r) == {1: 45000, 2: 45000}


def test_custom_split_valid():
    """TC-SPL-04 | Custom split that adds up | 500+700+600+400+800 = Rs 3000 | Accepted, amounts kept as entered"""
    entries = [{"user_id": u, "amount": a} for u, a in zip(MEMBERS, (500, 700, 600, 400, 800))]
    r = compute_splits("custom", 300000, entries, MEMBERS)
    assert amounts(r) == {1: 50000, 2: 70000, 3: 60000, 4: 40000, 5: 80000}


def test_custom_split_total_mismatch():
    """TC-SPL-05 | Custom split does not add up | Shares total Rs 2900 for a Rs 3000 expense | Rejected with a validation error"""
    entries = [{"user_id": u, "amount": a} for u, a in zip(MEMBERS, (500, 700, 600, 400, 700))]
    with pytest.raises(ValidationError) as exc:
        compute_splits("custom", 300000, entries, MEMBERS)
    assert "add up" in exc.value.message


def test_custom_split_negative_or_zero_share():
    """TC-SPL-06 | Custom split with zero / negative share | Share of 0 and of -100 | Rejected"""
    for bad in (0, -100):
        entries = [{"user_id": 1, "amount": bad}, {"user_id": 2, "amount": 3000 - bad}]
        with pytest.raises(ValidationError):
            compute_splits("custom", 300000, entries, MEMBERS)


def test_percentage_split_valid():
    """TC-SPL-07 | Percentage split totalling 100 | 20/20/25/15/20 % of Rs 3000 | Rs 600/600/750/450/600"""
    pcts = (20, 20, 25, 15, 20)
    entries = [{"user_id": u, "percentage": p} for u, p in zip(MEMBERS, pcts)]
    r = compute_splits("percentage", 300000, entries, MEMBERS)
    assert amounts(r) == {1: 60000, 2: 60000, 3: 75000, 4: 45000, 5: 60000}
    assert r[0]["percentage"] == Decimal("20")


def test_percentage_split_rounding_keeps_total():
    """TC-SPL-08 | Percentage split that needs rounding | 33.33/33.33/33.34 % of Rs 100.01 | Shares add up to exactly Rs 100.01"""
    entries = [{"user_id": 1, "percentage": 33.33}, {"user_id": 2, "percentage": 33.33},
               {"user_id": 3, "percentage": 33.34}]
    r = compute_splits("percentage", 10001, entries, MEMBERS)
    assert sum(amounts(r).values()) == 10001


def test_percentage_total_not_100():
    """TC-SPL-09 | Percentages do not total 100 | 50 % + 40 % | Rejected"""
    entries = [{"user_id": 1, "percentage": 50}, {"user_id": 2, "percentage": 40}]
    with pytest.raises(ValidationError) as exc:
        compute_splits("percentage", 10000, entries, MEMBERS)
    assert "100" in exc.value.message


def test_split_rejects_non_member_and_duplicates():
    """TC-SPL-10 | Participant is not a trip member / listed twice | user 99, and user 1 twice | Rejected"""
    with pytest.raises(ValidationError):
        compute_splits("equal", 10000, [{"user_id": 99}], MEMBERS)
    with pytest.raises(ValidationError):
        compute_splits("equal", 10000, [{"user_id": 1}, {"user_id": 1}], MEMBERS)


def test_split_rejects_bad_type_and_empty_list():
    """TC-SPL-11 | Unknown split type / no participants | split_type 'random', splits [] | Rejected"""
    with pytest.raises(ValidationError):
        compute_splits("random", 10000, [{"user_id": 1}], MEMBERS)
    with pytest.raises(ValidationError):
        compute_splits("equal", 10000, [], MEMBERS)


@pytest.mark.parametrize("value", [0, -5, "abc", None, True, "NaN", "Infinity", 1.234, 1e12])
def test_parse_amount_rejects_invalid(value):
    """TC-AMT-01 | Invalid amounts are rejected | 0, -5, 'abc', null, true, NaN, 1.234, 1e12 | ValidationError"""
    with pytest.raises(ValidationError):
        parse_amount(value)


def test_parse_amount_accepts_valid():
    """TC-AMT-02 | Valid amounts are parsed to paise | 3600, '49.99', 0.1 | 360000, 4999, 10"""
    assert parse_amount(3600) == 360000
    assert parse_amount("49.99") == 4999
    assert parse_amount(0.1) == 10


def test_parse_percentage_bounds():
    """TC-AMT-03 | Percentage bounds | 0, 100.01, 100 | 0 and 100.01 rejected, 100 accepted"""
    for bad in (0, -1, 100.01):
        with pytest.raises(ValidationError):
            parse_percentage(bad)
    assert parse_percentage(100) == Decimal("100")
