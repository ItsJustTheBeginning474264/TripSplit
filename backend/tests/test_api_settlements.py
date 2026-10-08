"""API tests: balances, settlement generation, marking payments as paid."""
from helpers import add_expense, balances, equal_split, make_trip_with_members, register


def spec_scenario(client):
    """Builds the example from the specification:
    Rahul owes 1000, Sneha owes 500, Ishani should receive 1200, Aditi should receive 300."""
    trip, (ishani, rahul, sneha, aditi) = make_trip_with_members(client, "Ishani", "Rahul", "Sneha", "Aditi")
    tid = trip["trip_id"]
    custom = lambda pairs: [{"user_id": u.id, "amount": a} for u, a in pairs]
    r1 = add_expense(client, ishani, tid, description="Hotel", amount=1500, split_type="custom",
                     splits=custom([(ishani, 300), (rahul, 1000), (sneha, 200)]))
    r2 = add_expense(client, aditi, tid, description="Fuel", amount=800, split_type="custom",
                     splits=custom([(aditi, 500), (sneha, 300)]))
    assert r1.status_code == 201 and r2.status_code == 201
    return tid, ishani, rahul, sneha, aditi


def generate(client, user, tid):
    r = client.post(f"/api/trips/{tid}/settlements/generate", headers=user.headers)
    assert r.status_code == 200, r.get_json()
    return r.get_json()


def test_balance_calculation(client):
    """TC-BAL-01 | Paid / share / balance per member | Specification scenario | Ishani +1200, Aditi +300, Rahul -1000, Sneha -500"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)
    b = balances(client, ishani, tid)
    assert (b[ishani.id]["paid"], b[ishani.id]["share"], b[ishani.id]["balance"]) == (1500, 300, 1200)
    assert b[aditi.id]["balance"] == 300
    assert b[rahul.id]["balance"] == -1000 and b[rahul.id]["paid"] == 0
    assert b[sneha.id]["balance"] == -500 and b[sneha.id]["share"] == 500


def test_balances_sum_to_zero(client):
    """TC-BAL-02 | Balances always sum to zero | Mix of equal, custom and percentage expenses with awkward amounts | Sum of balances is exactly 0.00 and total paid = total share"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul", "Sneha", "Aditi")
    tid = trip["trip_id"]
    a, b, c, d = users
    add_expense(client, a, tid, amount=100, split_type="equal", splits=equal_split([a, b, c]))
    add_expense(client, b, tid, amount=333.33, split_type="equal", splits=equal_split(users))
    add_expense(client, c, tid, amount=1000.01, split_type="percentage",
                splits=[{"user_id": a.id, "percentage": 33.33}, {"user_id": b.id, "percentage": 33.33},
                        {"user_id": d.id, "percentage": 33.34}])
    add_expense(client, d, tid, amount=77.77, split_type="custom",
                splits=[{"user_id": a.id, "amount": 70.07}, {"user_id": c.id, "amount": 7.70}])
    rows = balances(client, a, tid).values()
    assert round(sum(r["balance"] for r in rows), 2) == 0
    assert round(sum(r["paid"] for r in rows), 2) == round(sum(r["share"] for r in rows), 2)
    detail = client.get(f"/api/trips/{tid}", headers=a.headers).get_json()
    assert detail["summary"]["total_expenses"] == round(100 + 333.33 + 1000.01 + 77.77, 2)


def test_balances_require_membership(client):
    """TC-BAL-03 | Balances need membership | Outsider requests balances | 403"""
    tid, *_ = spec_scenario(client)
    out = register(client, "Outsider")
    assert client.get(f"/api/trips/{tid}/balances", headers=out.headers).status_code == 403


def test_dashboard_for_current_user(client):
    """TC-BAL-04 | Dashboard shows my contribution, share and balance | Specification scenario, viewed by Ishani and Sneha | Ishani 1500/300/+1200, Sneha 0/500/-500"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)
    s = client.get(f"/api/trips/{tid}", headers=ishani.headers).get_json()["summary"]
    assert (s["my_paid"], s["my_share"], s["my_balance"]) == (1500, 300, 1200)
    assert s["total_members"] == 4 and s["total_expenses"] == 2300
    s = client.get(f"/api/trips/{tid}", headers=sneha.headers).get_json()["summary"]
    assert (s["my_paid"], s["my_share"], s["my_balance"]) == (0, 500, -500)


def test_settlement_generation_matches_spec(client):
    """TC-SET-01 | Settlement for the specification example | Rahul -1000, Sneha -500, Ishani +1200, Aditi +300 | Rahul->Ishani 1000, Sneha->Ishani 200, Sneha->Aditi 300"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)
    data = generate(client, ishani, tid)
    plan = sorted((s["payer_name"], s["receiver_name"], s["amount"]) for s in data["settlements"])
    assert plan == [("Rahul", "Ishani", 1000), ("Sneha", "Aditi", 300), ("Sneha", "Ishani", 200)]
    assert all(s["status"] == "pending" and s["paid_at"] is None for s in data["settlements"])
    assert data["all_settled"] is False


def test_settlement_is_visible_to_all_members(client):
    """TC-SET-02 | Every member sees the same stored settlement | Ishani generates, Sneha fetches | Same 3 payments, needs_calculation false"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)
    r0 = client.get(f"/api/trips/{tid}/settlements", headers=sneha.headers).get_json()
    assert r0["settlements"] == [] and r0["needs_calculation"] is True
    generate(client, ishani, tid)
    r = client.get(f"/api/trips/{tid}/settlements", headers=sneha.headers).get_json()
    assert len(r["settlements"]) == 3 and r["needs_calculation"] is False


def test_settlement_is_minimal_and_complete(client):
    """TC-SET-03 | Settlement is complete and not wasteful | 6 members with mixed expenses | Applying the payments zeroes every balance; at most n-1 payments; never one payment per expense"""
    trip, users = make_trip_with_members(client, "Ishani", "Rahul", "Sneha", "Aditi", "Rohan", "Neha")
    tid = trip["trip_id"]
    for i, payer in enumerate(users * 2):
        add_expense(client, payer, tid, amount=250 + 37 * i, split_type="equal",
                    splits=equal_split(users[: 3 + (i % 4)]))
    data = generate(client, users[0], tid)
    bal = {u: b["balance"] for u, b in balances(client, users[0], tid).items()}
    for s in data["settlements"]:
        bal[s["payer_id"]] = round(bal[s["payer_id"]] + s["amount"], 2)
        bal[s["receiver_id"]] = round(bal[s["receiver_id"]] - s["amount"], 2)
    assert all(abs(v) < 0.005 for v in bal.values())
    assert len(data["settlements"]) <= 5 < 12


def test_mark_paid_updates_balances(client):
    """TC-SET-04 | Mark a settlement as paid | Rahul (payer) marks Rahul->Ishani 1000 as paid | status paid, paid_at set, Rahul's remaining balance 0, history kept"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)
    plan = generate(client, ishani, tid)["settlements"]
    mine = next(s for s in plan if s["payer_id"] == rahul.id)
    r = client.put(f"/api/settlements/{mine['settlement_id']}/pay", headers=rahul.headers)
    assert r.status_code == 200
    s = r.get_json()["settlement"]
    assert s["status"] == "paid" and s["paid_at"]
    b = balances(client, rahul, tid)
    assert b[rahul.id]["remaining"] == 0 and b[rahul.id]["balance"] == -1000   # raw balance unchanged
    assert b[ishani.id]["remaining"] == 200
    listing = client.get(f"/api/trips/{tid}/settlements", headers=aditi.headers).get_json()["settlements"]
    assert [x["status"] for x in listing] == ["pending", "pending", "paid"]   # pending first, history kept


def test_receiver_and_admin_can_mark_paid_but_bystander_cannot(client):
    """TC-SET-05 | Who may mark a payment | Bystander, receiver, admin | 403 for bystander, 200 for receiver and for admin"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)      # ishani is admin
    plan = generate(client, ishani, tid)["settlements"]
    sneha_to_aditi = next(s for s in plan if s["payer_id"] == sneha.id and s["receiver_id"] == aditi.id)
    url = f"/api/settlements/{sneha_to_aditi['settlement_id']}/pay"
    assert client.put(url, headers=rahul.headers).status_code == 403          # not involved, not admin
    assert client.put(url, headers=aditi.headers).status_code == 200          # receiver
    other = next(s for s in plan if s["payer_id"] == rahul.id)
    assert client.put(f"/api/settlements/{other['settlement_id']}/pay", headers=ishani.headers).status_code == 200


def test_non_member_cannot_mark_paid(client):
    """TC-SEC-03 | Outsider cannot touch settlements | Outsider marks a settlement paid, unknown id | 403 and 404"""
    tid, ishani, *_ = spec_scenario(client)
    plan = generate(client, ishani, tid)["settlements"]
    out = register(client, "Outsider")
    assert client.put(f"/api/settlements/{plan[0]['settlement_id']}/pay", headers=out.headers).status_code == 403
    assert client.put("/api/settlements/9999/pay", headers=ishani.headers).status_code == 404
    assert client.put(f"/api/settlements/{plan[0]['settlement_id']}/pay", headers=ishani.headers,
                      json={"status": "banana"}).status_code == 400


def test_revert_to_pending(client):
    """TC-SET-06 | Undo a payment (paid -> pending) | Mark paid, then PUT status pending | paid_at cleared and remaining balance restored"""
    tid, ishani, rahul, *_ = spec_scenario(client)
    plan = generate(client, ishani, tid)["settlements"]
    mine = next(s for s in plan if s["payer_id"] == rahul.id)
    url = f"/api/settlements/{mine['settlement_id']}/pay"
    client.put(url, headers=rahul.headers)
    r = client.put(url, headers=rahul.headers, json={"status": "pending"})
    assert r.get_json()["settlement"]["status"] == "pending" and r.get_json()["settlement"]["paid_at"] is None
    assert balances(client, rahul, tid)[rahul.id]["remaining"] == -1000


def test_fully_settled_trip(client):
    """TC-SET-07 | Pay everything | Mark all 3 payments paid | all_settled true, every remaining balance 0, regenerate gives no new payments"""
    tid, ishani, *_ = spec_scenario(client)
    for s in generate(client, ishani, tid)["settlements"]:
        assert client.put(f"/api/settlements/{s['settlement_id']}/pay", headers=ishani.headers).status_code == 200
    r = client.get(f"/api/trips/{tid}/settlements", headers=ishani.headers).get_json()
    assert r["all_settled"] is True and r["needs_calculation"] is False
    assert all(b["remaining"] == 0 for b in balances(client, ishani, tid).values())
    again = generate(client, ishani, tid)
    assert len(again["settlements"]) == 3 and again["all_settled"] is True     # only the paid history


def test_expense_change_recalculates_pending_but_keeps_paid(client):
    """TC-SET-08 | Expense added after some payments were made | Rahul pays 1000, then a new Rs 600 expense is added | Old pending plan dropped, paid payment kept, new plan accounts for it"""
    tid, ishani, rahul, sneha, aditi = spec_scenario(client)
    plan = generate(client, ishani, tid)["settlements"]
    rahul_pay = next(s for s in plan if s["payer_id"] == rahul.id)
    client.put(f"/api/settlements/{rahul_pay['settlement_id']}/pay", headers=rahul.headers)

    add_expense(client, aditi, tid, description="Snacks", amount=600, split_type="equal",
                splits=equal_split([ishani, rahul, sneha, aditi]))        # +450 aditi, -150 each other
    listing = client.get(f"/api/trips/{tid}/settlements", headers=ishani.headers).get_json()
    assert [s["status"] for s in listing["settlements"]] == ["paid"]       # pending plan was invalidated
    assert listing["needs_calculation"] is True

    plan2 = generate(client, ishani, tid)["settlements"]
    pending = [s for s in plan2 if s["status"] == "pending"]
    remaining = {u: b["remaining"] for u, b in balances(client, ishani, tid).items()}
    assert round(sum(remaining.values()), 2) == 0
    for s in pending:                                                        # applying the plan zeroes everything
        remaining[s["payer_id"]] = round(remaining[s["payer_id"]] + s["amount"], 2)
        remaining[s["receiver_id"]] = round(remaining[s["receiver_id"]] - s["amount"], 2)
    assert all(abs(v) < 0.005 for v in remaining.values())
    assert sum(1 for s in plan2 if s["status"] == "paid") == 1


def test_generate_on_empty_trip(client):
    """TC-SET-09 | Settlement with no expenses | Trip without expenses | Empty plan, all_settled true"""
    trip, (a, b) = make_trip_with_members(client, "Ishani", "Rahul")
    data = generate(client, a, trip["trip_id"])
    assert data["settlements"] == [] and data["all_settled"] is True
