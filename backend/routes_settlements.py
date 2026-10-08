from flask import Blueprint, g, jsonify, request

from auth import db_time, login_required, utcnow
from db import get_db
from errors import ForbiddenError, NotFoundError, ValidationError
from services import (generate_settlements, list_settlements, member_balances,
                      public_balances, require_active, require_member)

bp = Blueprint("settlements", __name__, url_prefix="/api")


@bp.get("/trips/<int:trip_id>/settlements")
@login_required
def get_settlements(trip_id):
    """Stored settlement plan + history (pending first, then paid)."""
    db = get_db()
    require_member(db, trip_id, g.user_id)
    settlements = list_settlements(db, trip_id)
    outstanding = [b for b in public_balances(member_balances(db, trip_id)) if b["remaining"] != 0]
    return jsonify({
        "settlements": settlements,
        "all_settled": not outstanding,
        "needs_calculation": bool(outstanding) and not any(s["status"] == "pending" for s in settlements),
    })


@bp.post("/trips/<int:trip_id>/settlements/generate")
@login_required
def generate(trip_id):
    """(Re)calculate the minimal set of payments from the current net balances."""
    db = get_db()
    trip, _ = require_member(db, trip_id, g.user_id)
    require_active(trip)
    generate_settlements(db, trip_id)
    outstanding = [b for b in member_balances(db, trip_id) if b["_remaining_cents"] != 0]
    return jsonify({"settlements": list_settlements(db, trip_id), "all_settled": not outstanding})


@bp.put("/settlements/<int:settlement_id>/pay")
@login_required
def mark_paid(settlement_id):
    """Mark a settlement as paid (default) or back to pending: {"status": "pending"}.
    Allowed for the payer, the receiver and the trip admin."""
    db = get_db()
    data = request.get_json(silent=True) or {}
    if not isinstance(data, dict):
        raise ValidationError("Request body must be a JSON object")
    status = data.get("status", "paid")
    if status not in ("paid", "pending"):
        raise ValidationError("status must be 'paid' or 'pending'")

    row = db.query_one("SELECT * FROM settlements WHERE settlement_id = %s", (settlement_id,))
    if row is None:
        raise NotFoundError("Settlement not found")
    _, membership = require_member(db, row["trip_id"], g.user_id)
    if g.user_id not in (row["payer_id"], row["receiver_id"]) and membership["role"] != "admin":
        raise ForbiddenError("Only the payer, the receiver or the trip admin can update this payment")

    paid_at = db_time(utcnow()) if status == "paid" else None
    if row["status"] != status:
        db.execute("UPDATE settlements SET status = %s, paid_at = %s WHERE settlement_id = %s",
                   (status, paid_at, settlement_id))
    updated = [s for s in list_settlements(db, row["trip_id"]) if s["settlement_id"] == settlement_id][0]
    return jsonify({"settlement": updated})

