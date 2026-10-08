"""API tests: adding / editing / deleting expenses, the three split types, validation."""
from helpers import (add_expense, balances, equal_split, make_trip_with_members, raw_query, register)


def shares(resp):
    return {s["user_id"]: s["amount"] for s in resp.get_json()["expense"]["splits"]}


def test_equal_split_via_api(client):
    """TC-EXP-01 | Add expense, equal split | Rs 3000 paid by Rahul, shared by 5 | 201, every share Rs 600"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul", "Sneha", "Aditi", "Rohan")
    r = add_expense(client, users[1], trip["trip_id"], amount=3000, split_type="equal",
                    splits=equal_split(users))
    assert r.status_code == 201
    exp = r.get_json()["expense"]
    assert exp["paid_by"] == users[1].id and exp["paid_by_name"] == "Rahul" and exp["amount"] == 3000
    assert set(shares(r).values()) == {600}


def test_equal_split_remainder_via_api(client):
    """TC-EXP-02 | Equal split that does not divide evenly | Rs 100 between 3 | Shares 33.34 + 33.33 + 33.33 = 100.00"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul", "Sneha")
    r = add_expense(client, users[0], trip["trip_id"], amount=100, split_type="equal",
                    splits=equal_split(users))
    assert r.status_code == 201
    assert round(sum(shares(r).values()), 2) == 100.00
    assert sorted(shares(r).values()) == [33.33, 33.33, 33.34]


def test_custom_split_via_api(client):
    """TC-EXP-03 | Add expense, custom split | 500/700/600/400/800 for Rs 3000 | 201, shares stored as entered"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul", "Sneha", "Aditi", "Rohan")
    entries = [{"user_id": u.id, "amount": a} for u, a in zip(users, (500, 700, 600, 400, 800))]
    r = add_expense(client, users[0], trip["trip_id"], amount=3000, split_type="custom", splits=entries)
    assert r.status_code == 201
    assert list(shares(r).values()) == [500, 700, 600, 400, 800]


def test_custom_split_mismatch_via_api(client, app):
    """TC-EXP-04 | Custom split that does not match the amount | Shares total Rs 2900 for Rs 3000 | 400 and nothing is stored"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    entries = [{"user_id": users[0].id, "amount": 1500}, {"user_id": users[1].id, "amount": 1400}]
    r = add_expense(client, users[0], trip["trip_id"], amount=3000, split_type="custom", splits=entries)
    assert r.status_code == 400
    assert raw_query(app, "SELECT COUNT(*) FROM expenses")[0][0] == 0


def test_percentage_split_via_api(client):
    """TC-EXP-05 | Add expense, percentage split | 20/20/25/15/20 % of Rs 3000 | 201, Rs 600/600/750/450/600 and percentages stored"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul", "Sneha", "Aditi", "Rohan")
    entries = [{"user_id": u.id, "percentage": p} for u, p in zip(users, (20, 20, 25, 15, 20))]
    r = add_expense(client, users[0], trip["trip_id"], amount=3000, split_type="percentage", splits=entries)
    assert r.status_code == 201
    assert list(shares(r).values()) == [600, 600, 750, 450, 600]
    assert [s["percentage"] for s in r.get_json()["expense"]["splits"]] == [20, 20, 25, 15, 20]


def test_percentage_not_100_via_api(client):
    """TC-EXP-06 | Percentages not totalling 100 | 50 % + 40 % | 400"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    entries = [{"user_id": users[0].id, "percentage": 50}, {"user_id": users[1].id, "percentage": 40}]
    r = add_expense(client, users[0], trip["trip_id"], amount=1000, split_type="percentage", splits=entries)
    assert r.status_code == 400


def test_zero_and_negative_amount(client):
    """TC-EXP-07 | Zero or negative expense amount | 0, -500 | 400 each"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    for bad in (0, -500, "0.00"):
        r = add_expense(client, users[0], trip["trip_id"], amount=bad, split_type="equal",
                        splits=equal_split(users))
        assert r.status_code == 400, bad


def test_invalid_amount_formats(client):
    """TC-EXP-08 | Non-numeric / over-precise / missing amount | 'abc', 10.555, null, missing | 400 each"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    for bad in ("abc", 10.555, None):
        r = add_expense(client, users[0], trip["trip_id"], amount=bad, split_type="equal",
                        splits=equal_split(users))
        assert r.status_code == 400, bad
    r = client.post(f"/api/trips/{trip['trip_id']}/expenses", headers=users[0].headers,
                    json={"description": "x", "split_type": "equal", "splits": equal_split(users)})
    assert r.status_code == 400


def test_non_member_cannot_add_expense(client, app):
    """TC-EXP-09 | User not in the trip adds an expense | Outsider POSTs to the trip | 403 and nothing stored"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    outsider = register(client, "Outsider")
    r = add_expense(client, outsider, trip["trip_id"], amount=500, split_type="equal",
                    splits=equal_split(users))
    assert r.status_code == 403
    assert raw_query(app, "SELECT COUNT(*) FROM expenses")[0][0] == 0


def test_participant_or_payer_not_in_trip(client):
    """TC-EXP-10 | Split / payer includes someone outside the trip | Outsider listed as participant, then as payer | 400 each"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    outsider = register(client, "Outsider")
    r = add_expense(client, users[0], trip["trip_id"], amount=500, split_type="equal",
                    splits=equal_split([users[0], outsider]))
    assert r.status_code == 400
    r = add_expense(client, users[0], trip["trip_id"], amount=500, split_type="equal",
                    splits=equal_split(users), paid_by=outsider.id)
    assert r.status_code == 400


def test_other_field_validation(client):
    """TC-EXP-11 | Empty description, bad category, bad split type, no participants, bad date | 400 each"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    base = dict(amount=500, split_type="equal", splits=equal_split(users))
    for change in ({"description": "  "}, {"category": "Gambling"}, {"split_type": "random"},
                   {"splits": []}, {"expense_date": "yesterday"}):
        r = add_expense(client, users[0], trip["trip_id"], **{**base, **change})
        assert r.status_code == 400, change


def test_category_is_case_insensitive_and_filterable(client):
    """TC-EXP-12 | Category filter | Add Food, Hotel and Fuel expenses, filter ?category=hotel | Only the hotel expense returned"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    tid = trip["trip_id"]
    for cat, amt in (("food", 300), ("Hotel", 5000), ("FUEL", 700)):
        assert add_expense(client, users[0], tid, amount=amt, category=cat, split_type="equal",
                           splits=equal_split(users)).status_code == 201
    r = client.get(f"/api/trips/{tid}/expenses?category=hotel", headers=users[1].headers).get_json()
    assert [e["category"] for e in r["expenses"]] == ["Hotel"] and r["total"] == 5000
    assert client.get(f"/api/trips/{tid}/expenses?category=zzz", headers=users[1].headers).status_code == 400
    detail = client.get(f"/api/trips/{tid}", headers=users[1].headers).get_json()
    assert [c["category"] for c in detail["by_category"]] == ["Hotel", "Fuel", "Food"]


def test_expense_details(client):
    """TC-EXP-13 | Expense details screen data | GET /api/expenses/{id} by a member and by an outsider | 200 with splits, 403 for outsider"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul")
    exp = add_expense(client, users[0], trip["trip_id"], amount=200, split_type="equal",
                      splits=equal_split(users)).get_json()["expense"]
    ok = client.get(f"/api/expenses/{exp['expense_id']}", headers=users[1].headers)
    assert ok.status_code == 200 and len(ok.get_json()["expense"]["splits"]) == 2
    out = register(client, "Outsider")
    assert client.get(f"/api/expenses/{exp['expense_id']}", headers=out.headers).status_code == 403
    assert client.get("/api/expenses/9999", headers=users[0].headers).status_code == 404


def test_edit_expense_permissions(client):
    """TC-EXP-14 | Edit an expense | Another member tries, the creator edits, the admin edits | 403, 200, 200 and balances follow the change"""
    trip, (admin, b, c) = make_trip_with_members(client, "Ishani", "Rahul", "Sneha")
    tid = trip["trip_id"]
    exp = add_expense(client, b, tid, amount=900, split_type="equal", splits=equal_split([admin, b, c])
                      ).get_json()["expense"]
    url = f"/api/expenses/{exp['expense_id']}"
    body = {"description": "Dinner v2", "amount": 1200, "category": "Food", "split_type": "equal",
            "splits": equal_split([admin, b, c])}
    assert client.put(url, headers=c.headers, json=body).status_code == 403
    r = client.put(url, headers=b.headers, json=body)
    assert r.status_code == 200 and r.get_json()["expense"]["amount"] == 1200
    assert balances(client, b, tid)[b.id]["balance"] == 800          # paid 1200, share 400
    r = client.put(url, headers=admin.headers, json={**body, "amount": 600})
    assert r.status_code == 200
    assert balances(client, b, tid)[b.id]["balance"] == 400
    bad = client.put(url, headers=b.headers, json={**body, "amount": -1})
    assert bad.status_code == 400


def test_delete_expense(client, app):
    """TC-EXP-15 | Delete an expense | Other member tries, creator deletes | 403, 200; its splits are removed and balances return to 0"""
    trip, (a, b, c) = make_trip_with_members(client, "Ishani", "Rahul", "Sneha")
    tid = trip["trip_id"]
    exp = add_expense(client, b, tid, amount=900, split_type="equal", splits=equal_split([a, b, c])
                      ).get_json()["expense"]
    url = f"/api/expenses/{exp['expense_id']}"
    assert client.delete(url, headers=c.headers).status_code == 403
    assert client.delete(url, headers=b.headers).status_code == 200
    assert raw_query(app, "SELECT COUNT(*) FROM expense_splits")[0][0] == 0
    assert all(v["balance"] == 0 for v in balances(client, a, tid).values())
    assert client.delete(url, headers=b.headers).status_code == 404


def test_completed_trip_is_read_only(client):
    """TC-EXP-16 | Completed trip rejects expense changes | Admin completes the trip, then adds an expense | 409; reopening allows it again"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    tid = trip["trip_id"]
    client.put(f"/api/trips/{tid}", headers=a.headers, json={"status": "completed"})
    assert add_expense(client, a, tid, amount=100, split_type="equal",
                       splits=equal_split([a, b])).status_code == 409
    client.put(f"/api/trips/{tid}", headers=a.headers, json={"status": "active"})
    assert add_expense(client, a, tid, amount=100, split_type="equal",
                       splits=equal_split([a, b])).status_code == 201


def test_sql_injection_text_is_stored_literally(client, app):
    """TC-SEC-02 | SQL injection attempt in text fields | description "x'); DROP TABLE expenses;--" | Stored as plain text (parameterised queries), tables intact"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    evil = "x'); DROP TABLE expenses;--"
    r = add_expense(client, a, trip["trip_id"], description=evil, amount=100, split_type="equal",
                    splits=equal_split([a, b]))
    assert r.status_code == 201 and r.get_json()["expense"]["description"] == evil
    assert raw_query(app, "SELECT description FROM expenses")[0][0] == evil
    login = client.post("/api/login", json={"email": "' OR '1'='1@x.com", "password": "' OR '1'='1"})
    assert login.status_code in (400, 401)


def test_database_constraints_reject_bad_rows(app):
    """TC-DB-01 | Database-level constraints | Duplicate email, negative amount, unknown trip, end before start, payer = receiver, duplicate membership inserted directly via SQL | IntegrityError for each"""
    import sqlite3
    conn = sqlite3.connect(app.config["DB_FILE"])
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO users (name, email, password_hash) VALUES ('A', 'a@x.com', 'h')")
    conn.execute("INSERT INTO users (name, email, password_hash) VALUES ('B', 'b@x.com', 'h')")
    conn.execute("INSERT INTO trips (trip_name, destination, start_date, end_date, created_by, invite_code) "
                 "VALUES ('T', 'D', '2026-01-01', '2026-01-02', 1, 'ABC123')")
    conn.execute("INSERT INTO trip_members (trip_id, user_id) VALUES (1, 1)")
    bad_statements = {
        "duplicate email": "INSERT INTO users (name, email, password_hash) VALUES ('C', 'a@x.com', 'h')",
        "negative amount": "INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, split_type, "
                           "expense_date) VALUES (1, 1, 1, 'x', -10, 'equal', '2026-01-01')",
        "zero amount": "INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, split_type, "
                       "expense_date) VALUES (1, 1, 1, 'x', 0, 'equal', '2026-01-01')",
        "unknown trip": "INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, split_type, "
                        "expense_date) VALUES (999, 1, 1, 'x', 10, 'equal', '2026-01-01')",
        "end before start": "INSERT INTO trips (trip_name, destination, start_date, end_date, created_by, "
                            "invite_code) VALUES ('T2', 'D', '2026-02-02', '2026-01-01', 1, 'ZZZ999')",
        "payer equals receiver": "INSERT INTO settlements (trip_id, payer_id, receiver_id, amount) "
                                 "VALUES (1, 1, 1, 5)",
        "duplicate membership": "INSERT INTO trip_members (trip_id, user_id) VALUES (1, 1)",
    }
    for label, sql in bad_statements.items():
        try:
            conn.execute(sql)
        except sqlite3.IntegrityError:
            continue
        raise AssertionError(f"constraint did not fire for: {label}")
    conn.close()
