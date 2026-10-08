"""API tests: registration, login, logout, profile, unauthenticated access."""
from helpers import register, raw_query


def test_register_valid(client):
    """TC-REG-01 | Register with valid details | name, unique email, password 'secret123' | 201, user + token returned, password not echoed"""
    r = client.post("/api/register", json={"name": "Ishani", "email": "Ishani@Example.com",
                                           "password": "secret123"})
    assert r.status_code == 201
    body = r.get_json()
    assert body["token"]
    assert body["user"]["email"] == "ishani@example.com"      # normalised to lower case
    assert "password" not in str(body).lower().replace("password_hash", "")
    assert "password_hash" not in body["user"]


def test_register_password_is_hashed(client, app):
    """TC-REG-02 | Password is never stored in plain text | Register with password 'secret123' | Stored value differs and is a salted hash"""
    register(client, "Rahul", password="secret123")
    stored = raw_query(app, "SELECT password_hash FROM users")[0][0]
    assert stored != "secret123" and "secret123" not in stored
    assert stored.startswith(("scrypt:", "pbkdf2:"))


def test_register_duplicate_email(client):
    """TC-REG-03 | Duplicate email | Register the same email twice (different case) | 409 conflict"""
    register(client, "Sneha", "sneha@example.com")
    r = client.post("/api/register", json={"name": "Other", "email": "SNEHA@example.com",
                                           "password": "secret123"})
    assert r.status_code == 409


def test_register_invalid_email(client):
    """TC-REG-04 | Invalid email format | 'not-an-email', 'a@b', 'a b@c.com' | 400 each"""
    for bad in ("not-an-email", "a@b", "a b@c.com", ""):
        r = client.post("/api/register", json={"name": "X", "email": bad, "password": "secret123"})
        assert r.status_code == 400, bad


def test_register_empty_fields(client):
    """TC-REG-05 | Empty / missing fields | blank name, missing password, empty body | 400 each"""
    assert client.post("/api/register", json={"name": "  ", "email": "a@b.com",
                                              "password": "secret123"}).status_code == 400
    assert client.post("/api/register", json={"name": "A", "email": "a@b.com"}).status_code == 400
    assert client.post("/api/register", json={}).status_code == 400
    assert client.post("/api/register", data="not json").status_code == 400


def test_register_short_password(client):
    """TC-REG-06 | Password too short | 'abc' | 400"""
    r = client.post("/api/register", json={"name": "A", "email": "a@b.com", "password": "abc"})
    assert r.status_code == 400


def test_login_valid(client):
    """TC-LOG-01 | Login with correct credentials | registered email + password | 200 and a token"""
    register(client, "Aditi", "aditi@example.com", "secret123")
    r = client.post("/api/login", json={"email": "ADITI@example.com", "password": "secret123"})
    assert r.status_code == 200 and r.get_json()["token"]


def test_login_wrong_password(client):
    """TC-LOG-02 | Login with wrong password | correct email, wrong password | 401, generic message"""
    register(client, "Aditi", "aditi@example.com", "secret123")
    r = client.post("/api/login", json={"email": "aditi@example.com", "password": "wrong-pass"})
    assert r.status_code == 401


def test_login_unknown_email(client):
    """TC-LOG-03 | Login with unknown email | never-registered email | 401 (same message as wrong password)"""
    r = client.post("/api/login", json={"email": "ghost@example.com", "password": "secret123"})
    assert r.status_code == 401
    register(client, "Real", "real@example.com")
    r2 = client.post("/api/login", json={"email": "real@example.com", "password": "nope-nope"})
    assert r.get_json()["error"] == r2.get_json()["error"]


def test_login_empty_fields(client):
    """TC-LOG-04 | Login with empty fields | empty email / empty password | 400"""
    assert client.post("/api/login", json={"email": "", "password": "x"}).status_code == 400
    assert client.post("/api/login", json={"email": "a@b.com", "password": ""}).status_code == 400


def test_logout_revokes_token(client):
    """TC-LOG-05 | Logout invalidates the token | POST /logout then reuse the token | 200, then 401"""
    u = register(client, "Neha")
    assert client.get("/api/profile", headers=u.headers).status_code == 200
    assert client.post("/api/logout", headers=u.headers).status_code == 200
    assert client.get("/api/profile", headers=u.headers).status_code == 401


def test_protected_endpoint_without_token(client):
    """TC-LOG-06 | Protected endpoints need a token | GET /api/trips with no Authorization header | 401"""
    assert client.get("/api/trips").status_code == 401
    assert client.get("/api/profile").status_code == 401


def test_invalid_token(client):
    """TC-LOG-07 | Garbage / tampered token | 'Bearer abc.def.ghi' | 401"""
    r = client.get("/api/trips", headers={"Authorization": "Bearer abc.def.ghi"})
    assert r.status_code == 401
    u = register(client, "Rohan")
    tampered = u.token[:-3] + ("AAA" if not u.token.endswith("AAA") else "BBB")
    assert client.get("/api/trips", headers={"Authorization": f"Bearer {tampered}"}).status_code == 401


def test_profile_update(client):
    """TC-PRO-01 | View and edit profile | PUT name 'Ishani M' | 200 and the new name is returned on the next GET"""
    u = register(client, "Ishani")
    r = client.put("/api/profile", headers=u.headers, json={"name": "Ishani M"})
    assert r.status_code == 200
    assert client.get("/api/profile", headers=u.headers).get_json()["user"]["name"] == "Ishani M"
    assert client.put("/api/profile", headers=u.headers, json={"name": ""}).status_code == 400


def test_profile_password_change(client):
    """TC-PRO-02 | Change password | wrong current password, then correct one | 401, then 200 and the new password logs in"""
    u = register(client, "Ishani", "ishani@example.com", "secret123")
    bad = client.put("/api/profile", headers=u.headers,
                     json={"current_password": "wrong", "new_password": "newsecret1"})
    assert bad.status_code == 401
    ok = client.put("/api/profile", headers=u.headers,
                    json={"current_password": "secret123", "new_password": "newsecret1"})
    assert ok.status_code == 200
    assert client.post("/api/login", json={"email": "ishani@example.com",
                                           "password": "newsecret1"}).status_code == 200
    assert client.post("/api/login", json={"email": "ishani@example.com",
                                           "password": "secret123"}).status_code == 401
