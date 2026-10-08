"""API tests: trips, joining, members, authorization."""
from helpers import (add_expense, create_trip, equal_split, join, make_trip_with_members,
                     raw_query, register)


def test_create_trip(client, app):
    """TC-TRP-01 | Create a trip | Goa Trip 2026, Goa, 10-15 Dec | 201, creator is admin, 6-character invite code, creator is a member"""
    u = register(client, "Ishani")
    trip = create_trip(client, u)
    assert trip["role"] == "admin" and trip["status"] == "active"
    assert len(trip["invite_code"]) == 6 and trip["invite_code"].isalnum()
    members = client.get(f"/api/trips/{trip['trip_id']}/members", headers=u.headers).get_json()["members"]
    assert [(m["user_id"], m["role"]) for m in members] == [(u.id, "admin")]


def test_create_trip_validation(client):
    """TC-TRP-02 | Trip validation | end before start, empty name, bad date, missing destination | 400 each"""
    u = register(client, "Ishani")
    base = {"trip_name": "T", "destination": "Goa", "start_date": "2026-12-10", "end_date": "2026-12-15"}
    for change in ({"end_date": "2026-12-01"}, {"trip_name": "  "}, {"start_date": "10/12/2026"},
                   {"destination": None}, {"end_date": "2026-02-30"}):
        r = client.post("/api/trips", headers=u.headers, json={**base, **change})
        assert r.status_code == 400, change


def test_invite_codes_are_unique(client):
    """TC-TRP-03 | Invite codes are unique | Create 25 trips | 25 different codes"""
    u = register(client, "Ishani")
    codes = {create_trip(client, u, name=f"Trip {i}")["invite_code"] for i in range(25)}
    assert len(codes) == 25


def test_list_only_my_trips(client):
    """TC-TRP-04 | My Trips lists only my own trips | Two users each create a trip | Each sees only their trip, with member count and total"""
    a, b = register(client, "Ishani"), register(client, "Rahul")
    ta, tb = create_trip(client, a, name="A trip"), create_trip(client, b, name="B trip")
    la = client.get("/api/trips", headers=a.headers).get_json()["trips"]
    assert [t["trip_id"] for t in la] == [ta["trip_id"]]
    assert la[0]["member_count"] == 1 and la[0]["total_expenses"] == 0
    lb = client.get("/api/trips", headers=b.headers).get_json()["trips"]
    assert [t["trip_id"] for t in lb] == [tb["trip_id"]]


def test_join_trip(client):
    """TC-JON-01 | Join with a valid invite code (case-insensitive) | Rahul joins with lower-case code | 201, role member"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    c = register(client, "Sneha")
    r = client.post("/api/trips/join", headers=c.headers,
                    json={"invite_code": f"  {trip['invite_code'].lower()} "})
    assert r.status_code == 201 and r.get_json()["trip"]["role"] == "member"


def test_join_invalid_code(client):
    """TC-JON-02 | Join with an invalid code | 'ZZZZZZ' and empty | 404 and 400"""
    u = register(client, "Rahul")
    assert client.post("/api/trips/join", headers=u.headers, json={"invite_code": "ZZZZZZ"}).status_code == 404
    assert client.post("/api/trips/join", headers=u.headers, json={"invite_code": ""}).status_code == 400


def test_join_twice_is_rejected(client, app):
    """TC-JON-03 | Duplicate membership | Join the same trip twice (and the admin joins own trip) | 409, still exactly one membership row"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    assert client.post("/api/trips/join", headers=b.headers,
                       json={"invite_code": trip["invite_code"]}).status_code == 409
    assert client.post("/api/trips/join", headers=a.headers,
                       json={"invite_code": trip["invite_code"]}).status_code == 409
    rows = raw_query(app, "SELECT COUNT(*) FROM trip_members WHERE trip_id=? AND user_id=?",
                     (trip["trip_id"], b.id))
    assert rows[0][0] == 1


def test_members_share_the_same_data(client):
    """TC-JON-04 | All members see the same trip data | 3 members, one adds an expense | Every member sees the same members, expense and total"""
    trip, (a, b, c) = make_trip_with_members(client, "Ishani", "Rahul", "Sneha")
    tid = trip["trip_id"]
    r = add_expense(client, b, tid, amount=3600, split_type="equal", splits=equal_split([a, b, c]))
    assert r.status_code == 201
    for u in (a, b, c):
        members = client.get(f"/api/trips/{tid}/members", headers=u.headers).get_json()["members"]
        assert sorted(m["name"] for m in members) == ["Ishani", "Rahul", "Sneha"]
        exps = client.get(f"/api/trips/{tid}/expenses", headers=u.headers).get_json()
        assert len(exps["expenses"]) == 1 and exps["total"] == 3600
        detail = client.get(f"/api/trips/{tid}", headers=u.headers).get_json()
        assert detail["summary"]["total_expenses"] == 3600 and detail["summary"]["total_members"] == 3


def test_join_completed_trip(client):
    """TC-JON-05 | Cannot join a completed trip | Admin completes the trip, then a new user joins | 409"""
    trip, (a,) = make_trip_with_members(client, "Ishani")
    client.put(f"/api/trips/{trip['trip_id']}", headers=a.headers, json={"status": "completed"})
    late = register(client, "Late")
    assert client.post("/api/trips/join", headers=late.headers,
                       json={"invite_code": trip["invite_code"]}).status_code == 409


def test_non_member_cannot_see_trip(client):
    """TC-SEC-01 | Non-member cannot read a trip | Outsider requests detail, members, expenses, balances, settlements | 403 for each"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    out = register(client, "Outsider")
    tid = trip["trip_id"]
    for path in ("", "/members", "/expenses", "/balances", "/settlements"):
        assert client.get(f"/api/trips/{tid}{path}", headers=out.headers).status_code == 403, path
    assert client.post(f"/api/trips/{tid}/settlements/generate", headers=out.headers).status_code == 403


def test_unknown_trip(client):
    """TC-TRP-05 | Unknown trip id | GET /api/trips/9999 | 404"""
    u = register(client, "Ishani")
    assert client.get("/api/trips/9999", headers=u.headers).status_code == 404
    assert client.get("/api/trips/9999/expenses", headers=u.headers).status_code == 404


def test_only_admin_can_edit_trip(client):
    """TC-TRP-06 | Only the admin edits or completes a trip | Member tries, then admin | 403, then 200"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    url = f"/api/trips/{trip['trip_id']}"
    assert client.put(url, headers=b.headers, json={"trip_name": "Hacked"}).status_code == 403
    r = client.put(url, headers=a.headers, json={"trip_name": "Goa 2026!", "status": "completed"})
    assert r.status_code == 200 and r.get_json()["trip"]["status"] == "completed"
    assert client.put(url, headers=a.headers, json={"status": "bogus"}).status_code == 400
    assert client.put(url, headers=a.headers, json={"end_date": "2000-01-01"}).status_code == 400


def test_delete_trip_cascades(client, app):
    """TC-TRP-07 | Admin deletes a trip | Member tries first, then admin | 403, then 200; memberships, expenses and splits are removed (ON DELETE CASCADE)"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    tid = trip["trip_id"]
    add_expense(client, a, tid, amount=100, split_type="equal", splits=equal_split([a, b]))
    assert client.delete(f"/api/trips/{tid}", headers=b.headers).status_code == 403
    assert client.delete(f"/api/trips/{tid}", headers=a.headers).status_code == 200
    for table in ("trip_members", "expenses", "expense_splits"):
        assert raw_query(app, f"SELECT COUNT(*) FROM {table}")[0][0] == 0
    assert client.get(f"/api/trips/{tid}", headers=a.headers).status_code == 404
