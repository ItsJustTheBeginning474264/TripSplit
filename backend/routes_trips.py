import secrets

from flask import Blueprint, g, jsonify

from auth import login_required
from db import IntegrityErrors, get_db
from errors import ConflictError, ForbiddenError, NotFoundError, ValidationError
from money import cents_from_db, dec_from_db, to_decimal
from services import (json_body, member_balances, parse_date_only, require_member, require_text)

bp = Blueprint("trips", __name__, url_prefix="/api")

# no 0/O/1/I so codes are easy to read out loud
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LEN = 6


def _new_invite_code(db):
    for _ in range(20):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
        if db.query_one("SELECT trip_id FROM trips WHERE invite_code = %s", (code,)) is None:
            return code
    raise ConflictError("Could not generate an invite code, please try again")


def _trip_json(row, role=None):
    body = {
        "trip_id": row["trip_id"],
        "trip_name": row["trip_name"],
        "destination": row["destination"],
        "start_date": row["start_date"],
        "end_date": row["end_date"],
        "created_by": row["created_by"],
        "invite_code": row["invite_code"],
        "status": row["status"],
    }
    if role is not None:
        body["role"] = role
    return body


def _require_admin(membership):
    if membership["role"] != "admin":
        raise ForbiddenError("Only the trip admin can do this")


# ---------------------------------------------------------------------------
# create / list / join
# ---------------------------------------------------------------------------
@bp.post("/trips")
@login_required
def create_trip():
    data = json_body()
    name = require_text(data, "trip_name", 100, "Trip name")
    destination = require_text(data, "destination", 100, "Destination")
    start = parse_date_only(data.get("start_date"), "start_date")
    end = parse_date_only(data.get("end_date"), "end_date")
    if end < start:
        raise ValidationError("End date cannot be before the start date")

    db = get_db()
    with db.transaction():          # trip + admin membership are stored atomically
        code = _new_invite_code(db)
        res = db.execute(
            "INSERT INTO trips (trip_name, destination, start_date, end_date, created_by, invite_code) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (name, destination, start.isoformat(), end.isoformat(), g.user_id, code))
        db.execute("INSERT INTO trip_members (trip_id, user_id, role) VALUES (%s, %s, 'admin')",
                   (res.lastrowid, g.user_id))
    trip = db.query_one("SELECT * FROM trips WHERE trip_id = %s", (res.lastrowid,))
    return jsonify({"trip": _trip_json(trip, "admin")}), 201


@bp.get("/trips")
@login_required
def list_trips():
    rows = get_db().query(
        "SELECT t.*, tm.role, "
        "       (SELECT COUNT(*) FROM trip_members m WHERE m.trip_id = t.trip_id) AS member_count, "
        "       COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.trip_id = t.trip_id), 0) AS total_expenses "
        "FROM trips t "
        "JOIN trip_members tm ON tm.trip_id = t.trip_id "
        "WHERE tm.user_id = %s "
        "ORDER BY t.start_date DESC, t.trip_id DESC", (g.user_id,))
    trips = []
    for r in rows:
        body = _trip_json(r, r["role"])
        body["member_count"] = r["member_count"]
        body["total_expenses"] = dec_from_db(r["total_expenses"])
        trips.append(body)
    return jsonify({"trips": trips})


@bp.post("/trips/join")
@login_required
def join_trip():
    data = json_body()
    code = data.get("invite_code")
    if not isinstance(code, str) or not code.strip():
        raise ValidationError("Invite code is required")
    code = code.strip().upper()

    db = get_db()
    trip = db.query_one("SELECT * FROM trips WHERE invite_code = %s", (code,))
    if trip is None:
        raise NotFoundError("Invalid invite code")
    if trip["status"] != "active":
        raise ConflictError("This trip is completed and no longer accepts new members")
    existing = db.query_one("SELECT trip_member_id FROM trip_members WHERE trip_id = %s AND user_id = %s",
                            (trip["trip_id"], g.user_id))
    if existing:
        raise ConflictError("You are already a member of this trip")
    try:
        db.execute("INSERT INTO trip_members (trip_id, user_id, role) VALUES (%s, %s, 'member')",
                   (trip["trip_id"], g.user_id))
    except IntegrityErrors:
        raise ConflictError("You are already a member of this trip")
    return jsonify({"trip": _trip_json(trip, "member")}), 201


# ---------------------------------------------------------------------------
# details (dashboard) / update / delete
# ---------------------------------------------------------------------------
@bp.get("/trips/<int:trip_id>")
@login_required
def trip_detail(trip_id):
    db = get_db()
    trip, membership = require_member(db, trip_id, g.user_id)
    totals = db.query_one("SELECT member_count, expense_count, total_expenses "
                          "FROM v_trip_totals WHERE trip_id = %s", (trip_id,))
    mine = next((b for b in member_balances(db, trip_id) if b["user_id"] == g.user_id), None)
    categories = db.query(
        "SELECT category, COUNT(*) AS expense_count, SUM(amount) AS total "
        "FROM expenses WHERE trip_id = %s "
        "GROUP BY category HAVING SUM(amount) > 0 ORDER BY total DESC", (trip_id,))
    body = _trip_json(trip, membership["role"])
    body["member_count"] = totals["member_count"]
    body["total_expenses"] = dec_from_db(totals["total_expenses"])
    return jsonify({
        "trip": body,
        "summary": {
            "total_members": totals["member_count"],
            "expense_count": totals["expense_count"],
            "total_expenses": dec_from_db(totals["total_expenses"]),
            "my_paid": mine["paid"],
            "my_share": mine["share"],
            "my_balance": mine["balance"],
            "my_remaining": mine["remaining"],
        },
        "by_category": [
            {"category": c["category"], "expense_count": c["expense_count"],
             "total": dec_from_db(c["total"])} for c in categories],
    })


@bp.put("/trips/<int:trip_id>")
@login_required
def update_trip(trip_id):
    data = json_body()
    db = get_db()
    trip, membership = require_member(db, trip_id, g.user_id)
    _require_admin(membership)

    name = require_text(data, "trip_name", 100, "Trip name") if "trip_name" in data else trip["trip_name"]
    dest = require_text(data, "destination", 100, "Destination") if "destination" in data else trip["destination"]
    start = parse_date_only(data["start_date"] if "start_date" in data else str(trip["start_date"]),
                            "start_date")
    end = parse_date_only(data["end_date"] if "end_date" in data else str(trip["end_date"]), "end_date")
    if end < start:
        raise ValidationError("End date cannot be before the start date")
    status = data.get("status", trip["status"])
    if status not in ("active", "completed"):
        raise ValidationError("status must be 'active' or 'completed'")

    db.execute("UPDATE trips SET trip_name = %s, destination = %s, start_date = %s, end_date = %s, "
               "status = %s WHERE trip_id = %s",
               (name, dest, start.isoformat(), end.isoformat(), status, trip_id))
    trip = db.query_one("SELECT * FROM trips WHERE trip_id = %s", (trip_id,))
    return jsonify({"trip": _trip_json(trip, membership["role"])})


@bp.delete("/trips/<int:trip_id>")
@login_required
def delete_trip(trip_id):
    db = get_db()
    _, membership = require_member(db, trip_id, g.user_id)
    _require_admin(membership)
    db.execute("DELETE FROM trips WHERE trip_id = %s", (trip_id,))   # members/expenses cascade
    return jsonify({"message": "Trip deleted"})


# ---------------------------------------------------------------------------
# members / balances
# ---------------------------------------------------------------------------
@bp.get("/trips/<int:trip_id>/members")
@login_required
def trip_members(trip_id):
    db = get_db()
    require_member(db, trip_id, g.user_id)
    rows = db.query(
        "SELECT u.user_id, u.name, u.email, u.profile_image, tm.role, tm.joined_at "
        "FROM trip_members tm JOIN users u ON u.user_id = tm.user_id "
        "WHERE tm.trip_id = %s ORDER BY tm.trip_member_id", (trip_id,))
    return jsonify({"members": rows})


@bp.get("/trips/<int:trip_id>/balances")
@login_required
def trip_balances(trip_id):
    db = get_db()
    require_member(db, trip_id, g.user_id)
    rows = member_balances(db, trip_id)
    total = sum(cents_from_db(r["paid"]) for r in rows)
    return jsonify({
        "balances": [{k: v for k, v in r.items() if not k.startswith("_")} for r in rows],
        "total_expenses": to_decimal(total),
    })
