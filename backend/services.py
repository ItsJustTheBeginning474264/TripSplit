"""Shared helpers used by the route modules: request parsing, authorization checks,
balance calculation and settlement generation."""
from datetime import date, datetime, timezone

from flask import request

from auth import db_time, utcnow
from errors import ConflictError, ForbiddenError, NotFoundError, ValidationError
from money import cents_from_db, dec_from_db, to_decimal
from settlement import compute_settlements


# ---------------------------------------------------------------------------
# request parsing / validation
# ---------------------------------------------------------------------------
def json_body():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise ValidationError("Request body must be a JSON object")
    return data


def require_text(data, field, max_len, label=None):
    label = label or field
    value = data.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{label} is required")
    value = value.strip()
    if len(value) > max_len:
        raise ValidationError(f"{label} must be at most {max_len} characters")
    return value


def parse_date_only(value, field):
    if not isinstance(value, str):
        raise ValidationError(f"{field} is required (format YYYY-MM-DD)")
    try:
        return date.fromisoformat(value.strip())
    except ValueError:
        raise ValidationError(f"{field} must be a valid date in YYYY-MM-DD format")


def parse_datetime(value, field="expense_date"):
    """Accepts YYYY-MM-DD or an ISO date-time; returns a naive datetime (UTC if aware)."""
    if value is None:
        return utcnow()
    if not isinstance(value, str):
        raise ValidationError(f"{field} must be an ISO date or date-time string")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        raise ValidationError(f"{field} must be a valid ISO date or date-time")
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.replace(microsecond=0)


# ---------------------------------------------------------------------------
# authorization
# ---------------------------------------------------------------------------
def get_trip_or_404(db, trip_id):
    trip = db.query_one("SELECT * FROM trips WHERE trip_id = %s", (trip_id,))
    if trip is None:
        raise NotFoundError("Trip not found")
    return trip


def require_member(db, trip_id, user_id):
    """Returns (trip, membership). 404 if the trip doesn't exist, 403 if not a member."""
    trip = get_trip_or_404(db, trip_id)
    membership = db.query_one(
        "SELECT * FROM trip_members WHERE trip_id = %s AND user_id = %s", (trip_id, user_id))
    if membership is None:
        raise ForbiddenError("You are not a member of this trip")
    return trip, membership


def require_active(trip):
    if trip["status"] != "active":
        raise ConflictError("This trip is completed; reopen it to make changes")


def member_ids(db, trip_id):
    rows = db.query("SELECT user_id FROM trip_members WHERE trip_id = %s", (trip_id,))
    return [r["user_id"] for r in rows]


# ---------------------------------------------------------------------------
# balances
# ---------------------------------------------------------------------------
def member_balances(db, trip_id):
    """Per-member paid / share / balance, read from the v_member_balances view."""
    rows = db.query(
        "SELECT user_id, name, total_paid, total_share, settled_out, settled_in "
        "FROM v_member_balances WHERE trip_id = %s ORDER BY name, user_id", (trip_id,))
    result = []
    for r in rows:
        paid, share = cents_from_db(r["total_paid"]), cents_from_db(r["total_share"])
        out, inc = cents_from_db(r["settled_out"]), cents_from_db(r["settled_in"])
        balance = paid - share
        result.append({
            "user_id": r["user_id"],
            "name": r["name"],
            "paid": to_decimal(paid),
            "share": to_decimal(share),
            "balance": to_decimal(balance),                # + receives, - owes
            "settled_out": to_decimal(out),
            "settled_in": to_decimal(inc),
            "remaining": to_decimal(balance + out - inc),  # still to be settled
            "_remaining_cents": balance + out - inc,
        })
    return result


def public_balances(rows):
    return [{k: v for k, v in r.items() if not k.startswith("_")} for r in rows]


# ---------------------------------------------------------------------------
# settlements
# ---------------------------------------------------------------------------
def delete_pending_settlements(db, trip_id):
    db.execute("DELETE FROM settlements WHERE trip_id = %s AND status = 'pending'", (trip_id,))


def generate_settlements(db, trip_id):
    """Replace the trip's pending settlements with a freshly computed minimal plan.
    Payments already marked 'paid' are kept and already counted in the balances."""
    with db.transaction():
        db.lock_trip(trip_id)
        delete_pending_settlements(db, trip_id)
        balances = {r["user_id"]: r["_remaining_cents"] for r in member_balances(db, trip_id)}
        now = db_time(utcnow())
        for payer, receiver, cents in compute_settlements(balances):
            db.execute(
                "INSERT INTO settlements (trip_id, payer_id, receiver_id, amount, status, created_at) "
                "VALUES (%s, %s, %s, %s, 'pending', %s)",
                (trip_id, payer, receiver, str(to_decimal(cents)), now))


def list_settlements(db, trip_id):
    rows = db.query(
        "SELECT s.settlement_id, s.trip_id, s.payer_id, p.name AS payer_name, "
        "       s.receiver_id, r.name AS receiver_name, s.amount, s.status, s.created_at, s.paid_at "
        "FROM settlements s "
        "JOIN users p ON p.user_id = s.payer_id "
        "JOIN users r ON r.user_id = s.receiver_id "
        "WHERE s.trip_id = %s "
        "ORDER BY CASE s.status WHEN 'pending' THEN 0 ELSE 1 END, s.settlement_id", (trip_id,))
    for row in rows:
        row["amount"] = dec_from_db(row["amount"])
    return rows
