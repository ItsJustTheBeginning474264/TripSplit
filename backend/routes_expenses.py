from flask import Blueprint, g, jsonify, request

from auth import db_time, login_required, utcnow
from db import get_db
from errors import ForbiddenError, NotFoundError, ValidationError
from money import dec_from_db, parse_amount, to_decimal
from services import (delete_pending_settlements, json_body, member_ids, parse_datetime,
                      require_active, require_member, require_text)
from splits import compute_splits

bp = Blueprint("expenses", __name__, url_prefix="/api")

CATEGORIES = ("Food", "Hotel", "Transportation", "Activities", "Shopping", "Tickets", "Fuel", "Other")
_CATEGORY_LOOKUP = {c.lower(): c for c in CATEGORIES}


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _parse_expense(db, trip_id, data, default_payer):
    """Validate an expense request body. Returns a dict ready to be stored.
    `default_payer` is used when the body has no paid_by (the current user when adding,
    the existing payer when editing, so an edit never silently changes who paid)."""
    members = member_ids(db, trip_id)
    description = require_text(data, "description", 255, "Description")
    total_cents = parse_amount(data.get("amount"), "Amount")

    category = data.get("category", "Other")
    if not isinstance(category, str) or category.strip().lower() not in _CATEGORY_LOOKUP:
        raise ValidationError(f"category must be one of: {', '.join(CATEGORIES)}")
    category = _CATEGORY_LOOKUP[category.strip().lower()]

    paid_by = data.get("paid_by", default_payer)
    if isinstance(paid_by, bool) or not isinstance(paid_by, int):
        raise ValidationError("paid_by must be a user id")
    if paid_by not in members:
        raise ValidationError("The payer must be a member of this trip")

    splits = compute_splits(data.get("split_type"), total_cents, data.get("splits"), members)
    return {
        "description": description,
        "amount_cents": total_cents,
        "category": category,
        "paid_by": paid_by,
        "split_type": data.get("split_type"),
        "expense_date": parse_datetime(data.get("expense_date")),
        "splits": splits,
    }


def _insert_splits(db, expense_id, splits):
    for s in splits:
        db.execute(
            "INSERT INTO expense_splits (expense_id, user_id, amount, percentage) VALUES (%s, %s, %s, %s)",
            (expense_id, s["user_id"], str(to_decimal(s["amount_cents"])),
             None if s["percentage"] is None else str(s["percentage"])))


_EXPENSE_SELECT = (
    "SELECT e.expense_id, e.trip_id, e.paid_by, p.name AS paid_by_name, "
    "       e.created_by, c.name AS created_by_name, e.description, e.amount, e.category, "
    "       e.split_type, e.expense_date, e.created_at "
    "FROM expenses e "
    "JOIN users p ON p.user_id = e.paid_by "
    "JOIN users c ON c.user_id = e.created_by ")


def _expense_json(row, splits):
    body = dict(row)
    body["amount"] = dec_from_db(row["amount"])
    body["splits"] = [{
        "user_id": s["user_id"], "name": s["name"], "amount": dec_from_db(s["amount"]),
        "percentage": None if s["percentage"] is None else float(s["percentage"]),
    } for s in splits]
    return body


def _splits_for(db, expense_ids_subquery, params):
    rows = db.query(
        "SELECT es.expense_id, es.user_id, u.name, es.amount, es.percentage "
        "FROM expense_splits es JOIN users u ON u.user_id = es.user_id "
        "WHERE es.expense_id IN (" + expense_ids_subquery + ") ORDER BY es.split_id", params)
    grouped = {}
    for r in rows:
        grouped.setdefault(r["expense_id"], []).append(r)
    return grouped


def _load_expense(db, expense_id):
    row = db.query_one(_EXPENSE_SELECT + "WHERE e.expense_id = %s", (expense_id,))
    if row is None:
        raise NotFoundError("Expense not found")
    return row


def _require_editor(membership, expense):
    if membership["role"] != "admin" and expense["created_by"] != g.user_id:
        raise ForbiddenError("Only the person who added this expense or the trip admin can change it")


# ---------------------------------------------------------------------------
# routes
# ---------------------------------------------------------------------------
@bp.post("/trips/<int:trip_id>/expenses")
@login_required
def add_expense(trip_id):
    data = json_body()
    db = get_db()
    trip, _ = require_member(db, trip_id, g.user_id)
    require_active(trip)
    exp = _parse_expense(db, trip_id, data, g.user_id)

    with db.transaction():          # expense + splits + invalidating old suggestions: all or nothing
        db.lock_trip(trip_id)
        res = db.execute(
            "INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, category, "
            "                      split_type, expense_date, created_at) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (trip_id, exp["paid_by"], g.user_id, exp["description"], str(to_decimal(exp["amount_cents"])),
             exp["category"], exp["split_type"], db_time(exp["expense_date"]), db_time(utcnow())))
        _insert_splits(db, res.lastrowid, exp["splits"])
        delete_pending_settlements(db, trip_id)

    row = _load_expense(db, res.lastrowid)
    splits = _splits_for(db, "%s", (res.lastrowid,)).get(res.lastrowid, [])
    return jsonify({"expense": _expense_json(row, splits)}), 201


@bp.get("/trips/<int:trip_id>/expenses")
@login_required
def list_expenses(trip_id):
    db = get_db()
    require_member(db, trip_id, g.user_id)
    sql, params = _EXPENSE_SELECT + "WHERE e.trip_id = %s", [trip_id]

    category = request.args.get("category")
    if category:
        if category.strip().lower() not in _CATEGORY_LOOKUP:
            raise ValidationError(f"category must be one of: {', '.join(CATEGORIES)}")
        sql += " AND e.category = %s"
        params.append(_CATEGORY_LOOKUP[category.strip().lower()])
    paid_by = request.args.get("paid_by")
    if paid_by:
        if not paid_by.isdigit():
            raise ValidationError("paid_by must be a user id")
        sql += " AND e.paid_by = %s"
        params.append(int(paid_by))
    rows = db.query(sql + " ORDER BY e.expense_date DESC, e.expense_id DESC", params)

    splits = _splits_for(db, "SELECT expense_id FROM expenses WHERE trip_id = %s", (trip_id,))
    expenses = [_expense_json(r, splits.get(r["expense_id"], [])) for r in rows]
    total = sum(e["amount"] for e in expenses)
    return jsonify({"expenses": expenses, "total": total})


@bp.get("/expenses/<int:expense_id>")
@login_required
def get_expense(expense_id):
    db = get_db()
    row = _load_expense(db, expense_id)
    require_member(db, row["trip_id"], g.user_id)
    splits = _splits_for(db, "%s", (expense_id,)).get(expense_id, [])
    return jsonify({"expense": _expense_json(row, splits)})


@bp.put("/expenses/<int:expense_id>")
@login_required
def update_expense(expense_id):
    data = json_body()
    db = get_db()
    row = _load_expense(db, expense_id)
    trip, membership = require_member(db, row["trip_id"], g.user_id)
    _require_editor(membership, row)
    require_active(trip)
    exp = _parse_expense(db, row["trip_id"], data, row["paid_by"])

    with db.transaction():
        db.lock_trip(row["trip_id"])
        db.execute(
            "UPDATE expenses SET paid_by = %s, description = %s, amount = %s, category = %s, "
            "split_type = %s, expense_date = %s WHERE expense_id = %s",
            (exp["paid_by"], exp["description"], str(to_decimal(exp["amount_cents"])), exp["category"],
             exp["split_type"], db_time(exp["expense_date"]), expense_id))
        db.execute("DELETE FROM expense_splits WHERE expense_id = %s", (expense_id,))
        _insert_splits(db, expense_id, exp["splits"])
        delete_pending_settlements(db, row["trip_id"])

    row = _load_expense(db, expense_id)
    splits = _splits_for(db, "%s", (expense_id,)).get(expense_id, [])
    return jsonify({"expense": _expense_json(row, splits)})


@bp.delete("/expenses/<int:expense_id>")
@login_required
def delete_expense(expense_id):
    db = get_db()
    row = _load_expense(db, expense_id)
    trip, membership = require_member(db, row["trip_id"], g.user_id)
    _require_editor(membership, row)
    require_active(trip)
    with db.transaction():
        db.lock_trip(row["trip_id"])
        db.execute("DELETE FROM expenses WHERE expense_id = %s", (expense_id,))   # splits cascade
        delete_pending_settlements(db, row["trip_id"])
    return jsonify({"message": "Expense deleted"})
