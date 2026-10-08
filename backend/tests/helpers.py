"""Small helpers shared by the API tests."""
import sqlite3


class User:
    def __init__(self, user_id, name, email, token):
        self.id = user_id
        self.name = name
        self.email = email
        self.headers = {"Authorization": f"Bearer {token}"}
        self.token = token


def register(client, name, email=None, password="secret123"):
    email = email or f"{name.lower()}@example.com"
    r = client.post("/api/register", json={"name": name, "email": email, "password": password})
    assert r.status_code == 201, r.get_json()
    body = r.get_json()
    return User(body["user"]["user_id"], name, email, body["token"])


def create_trip(client, owner, name="Goa Trip 2026", destination="Goa",
                start="2026-12-10", end="2026-12-15"):
    r = client.post("/api/trips", headers=owner.headers, json={
        "trip_name": name, "destination": destination, "start_date": start, "end_date": end})
    assert r.status_code == 201, r.get_json()
    return r.get_json()["trip"]


def join(client, user, code):
    r = client.post("/api/trips/join", headers=user.headers, json={"invite_code": code})
    assert r.status_code == 201, r.get_json()
    return r.get_json()["trip"]


def make_trip_with_members(client, *names):
    """First name creates the trip (admin); the others join. Returns (trip, [users])."""
    users = [register(client, n) for n in names]
    trip = create_trip(client, users[0])
    for u in users[1:]:
        join(client, u, trip["invite_code"])
    return trip, users


def add_expense(client, user, trip_id, **fields):
    body = {"description": "Dinner", "amount": 3000, "category": "Food"}
    body.update(fields)
    return client.post(f"/api/trips/{trip_id}/expenses", headers=user.headers, json=body)


def equal_split(users):
    return [{"user_id": u.id} for u in users]


def balances(client, user, trip_id):
    r = client.get(f"/api/trips/{trip_id}/balances", headers=user.headers)
    assert r.status_code == 200, r.get_json()
    return {b["user_id"]: b for b in r.get_json()["balances"]}


def raw_query(app, sql, params=()):
    conn = sqlite3.connect(app.config["DB_FILE"])
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()
