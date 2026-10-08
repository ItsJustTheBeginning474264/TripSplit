"""Creates demo data (the Goa Trip 2026 from the project brief) through the real API.

    python seed_demo.py

Uses whatever database is configured via environment variables (see config.py), so run
it after `mysql < database/schema.sql`. All demo users have the password  demo123 .
"""
from app import create_app

PASSWORD = "demo123"
NAMES = ["Ishani", "Rahul", "Sneha", "Aditi", "Rohan", "Neha"]


def main():
    app = create_app()
    client = app.test_client()

    users = {}
    for name in NAMES:
        email = f"{name.lower()}@example.com"
        r = client.post("/api/register", json={"name": name, "email": email, "password": PASSWORD})
        if r.status_code == 409:                       # already seeded: log in instead
            r = client.post("/api/login", json={"email": email, "password": PASSWORD})
        body = r.get_json()
        users[name] = {"id": body["user"]["user_id"], "h": {"Authorization": f"Bearer {body['token']}"}}

    r = client.post("/api/trips", headers=users["Ishani"]["h"], json={
        "trip_name": "GOA TRIP 2026", "destination": "Goa",
        "start_date": "2026-12-10", "end_date": "2026-12-15"})
    trip = r.get_json()["trip"]
    for name in NAMES[1:]:
        client.post("/api/trips/join", headers=users[name]["h"], json={"invite_code": trip["invite_code"]})

    everyone = [{"user_id": users[n]["id"]} for n in NAMES]

    def expense(payer, desc, amount, category, split_type="equal", splits=None, date="2026-12-10"):
        r = client.post(f"/api/trips/{trip['trip_id']}/expenses", headers=users[payer]["h"], json={
            "description": desc, "amount": amount, "category": category, "split_type": split_type,
            "splits": splits or everyone, "expense_date": date})
        assert r.status_code == 201, r.get_json()

    expense("Ishani", "Beach resort - 5 nights", 12000, "Hotel", date="2026-12-10")
    expense("Rahul", "Dinner at the shack", 3600, "Food", date="2026-12-11")
    expense("Sneha", "Scooter rentals", 3000, "Transportation", date="2026-12-11")
    expense("Aditi", "Water sports", 2500, "Activities", "custom", [
        {"user_id": users[n]["id"], "amount": a} for n, a in
        (("Ishani", 500), ("Rahul", 700), ("Sneha", 600), ("Aditi", 400), ("Rohan", 300))],
        date="2026-12-12")
    expense("Rohan", "Fuel", 1500, "Fuel", date="2026-12-13")
    expense("Ishani", "Souvenirs", 2000, "Shopping", "percentage", [
        {"user_id": users[n]["id"], "percentage": p} for n, p in
        (("Ishani", 20), ("Rahul", 20), ("Sneha", 25), ("Aditi", 15), ("Rohan", 20))],
        date="2026-12-14")
    expense("Neha", "Farewell dinner", 4000, "Food", date="2026-12-15")

    print(f"Trip '{trip['trip_name']}' created - invite code: {trip['invite_code']}")
    print("Log in as ishani@example.com ... neha@example.com with password", PASSWORD)


if __name__ == "__main__":
    main()
