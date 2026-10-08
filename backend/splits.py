"""Expense splitting: equal / custom / percentage.

`compute_splits` validates the request's split description and returns the exact amount
(in cents) each participant owes. The returned amounts always add up to the expense
total, whatever the rounding.
"""
from decimal import Decimal, ROUND_FLOOR

from errors import ValidationError
from money import parse_amount, parse_percentage

SPLIT_TYPES = ("equal", "custom", "percentage")


def _participant_ids(entries, member_ids):
    if not isinstance(entries, list) or not entries:
        raise ValidationError("splits must be a non-empty list of participants")
    ids = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValidationError("Each split entry must be an object")
        uid = entry.get("user_id")
        if isinstance(uid, bool) or not isinstance(uid, int):
            raise ValidationError("Each split entry needs an integer user_id")
        if uid in ids:
            raise ValidationError(f"User {uid} appears more than once in the split")
        if uid not in member_ids:
            raise ValidationError(f"User {uid} is not a member of this trip")
        ids.append(uid)
    return ids


def _equal(total_cents, ids):
    base, remainder = divmod(total_cents, len(ids))
    # the first `remainder` participants pay one extra paisa so the total matches exactly
    return [
        {"user_id": uid, "amount_cents": base + (1 if i < remainder else 0), "percentage": None}
        for i, uid in enumerate(ids)
    ]


def _custom(total_cents, entries, ids):
    result = []
    for uid, entry in zip(ids, entries):
        cents = parse_amount(entry.get("amount"), field=f"amount for user {uid}")
        result.append({"user_id": uid, "amount_cents": cents, "percentage": None})
    assigned = sum(r["amount_cents"] for r in result)
    if assigned != total_cents:
        raise ValidationError(
            "The individual amounts must add up to the expense amount",
            details={"expense_amount": total_cents / 100, "split_total": assigned / 100},
        )
    return result


def _percentage(total_cents, entries, ids):
    pcts = [parse_percentage(e.get("percentage"), field=f"percentage for user {uid}")
            for uid, e in zip(ids, entries)]
    if sum(pcts) != Decimal(100):
        raise ValidationError(
            "Percentages must add up to 100",
            details={"percentage_total": float(sum(pcts))},
        )
    # largest-remainder method: floor every share, then hand the leftover cents to the
    # participants whose exact share had the biggest fractional part.
    exact = [Decimal(total_cents) * p / 100 for p in pcts]
    floors = [int(x.to_integral_value(ROUND_FLOOR)) for x in exact]
    leftover = total_cents - sum(floors)
    order = sorted(range(len(ids)), key=lambda i: (-(exact[i] - floors[i]), i))
    for i in order[:leftover]:
        floors[i] += 1
    return [{"user_id": uid, "amount_cents": floors[i], "percentage": pcts[i]}
            for i, uid in enumerate(ids)]


def compute_splits(split_type, total_cents, entries, member_ids):
    """Return [{user_id, amount_cents, percentage}] or raise ValidationError."""
    if split_type not in SPLIT_TYPES:
        raise ValidationError(f"split_type must be one of: {', '.join(SPLIT_TYPES)}")
    ids = _participant_ids(entries, set(member_ids))
    if split_type == "equal":
        return _equal(total_cents, ids)
    if split_type == "custom":
        return _custom(total_cents, entries, ids)
    return _percentage(total_cents, entries, ids)
