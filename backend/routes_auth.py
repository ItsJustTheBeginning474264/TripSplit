from flask import Blueprint, g, jsonify
from werkzeug.security import check_password_hash, generate_password_hash

from auth import EMAIL_RE, create_token, db_time, login_required, utcnow
from db import IntegrityErrors, get_db
from errors import AuthError, ConflictError, ValidationError
from services import json_body, require_text

bp = Blueprint("auth", __name__, url_prefix="/api")

MIN_PASSWORD_LEN = 6


def _public_user(row):
    return {
        "user_id": row["user_id"],
        "name": row["name"],
        "email": row["email"],
        "profile_image": row.get("profile_image"),
        "created_at": row.get("created_at"),
    }


def _clean_email(data):
    email = data.get("email")
    if not isinstance(email, str) or not email.strip():
        raise ValidationError("Email is required")
    email = email.strip().lower()
    if len(email) > 255 or not EMAIL_RE.match(email):
        raise ValidationError("Email address is not valid")
    return email


def _check_password(password, field="Password"):
    if not isinstance(password, str) or not password:
        raise ValidationError(f"{field} is required")
    if len(password) < MIN_PASSWORD_LEN:
        raise ValidationError(f"{field} must be at least {MIN_PASSWORD_LEN} characters")
    if len(password) > 128:
        raise ValidationError(f"{field} must be at most 128 characters")


@bp.post("/register")
def register():
    data = json_body()
    name = require_text(data, "name", 100, "Name")
    email = _clean_email(data)
    _check_password(data.get("password"))
    db = get_db()
    if db.query_one("SELECT user_id FROM users WHERE email = %s", (email,)):
        raise ConflictError("An account with this email already exists")
    try:
        res = db.execute(
            "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)",
            (name, email, generate_password_hash(data["password"])))
    except IntegrityErrors:
        raise ConflictError("An account with this email already exists")
    user = db.query_one("SELECT * FROM users WHERE user_id = %s", (res.lastrowid,))
    return jsonify({"user": _public_user(user), "token": create_token(user["user_id"])}), 201


@bp.post("/login")
def login():
    data = json_body()
    email = _clean_email(data)
    password = data.get("password")
    if not isinstance(password, str) or not password:
        raise ValidationError("Password is required")
    db = get_db()
    user = db.query_one("SELECT * FROM users WHERE email = %s", (email,))
    if user is None or not check_password_hash(user["password_hash"], password):
        raise AuthError("Incorrect email or password")
    return jsonify({"user": _public_user(user), "token": create_token(user["user_id"])})


@bp.post("/logout")
@login_required
def logout():
    db = get_db()
    now = utcnow()
    db.execute("DELETE FROM token_blacklist WHERE expires_at < %s", (db_time(now),))
    db.execute("INSERT INTO token_blacklist (jti, expires_at) VALUES (%s, %s)",
               (g.jti, db_time(g.token_exp)))
    return jsonify({"message": "Logged out"})


@bp.get("/profile")
@login_required
def get_profile():
    user = get_db().query_one("SELECT * FROM users WHERE user_id = %s", (g.user_id,))
    return jsonify({"user": _public_user(user)})


@bp.put("/profile")
@login_required
def update_profile():
    data = json_body()
    db = get_db()
    user = db.query_one("SELECT * FROM users WHERE user_id = %s", (g.user_id,))
    name = require_text(data, "name", 100, "Name") if "name" in data else user["name"]

    image = user.get("profile_image")
    if "profile_image" in data:
        image = data["profile_image"]
        if image is not None:
            if not isinstance(image, str) or len(image.strip()) > 255:
                raise ValidationError("profile_image must be a URL of at most 255 characters")
            image = image.strip() or None

    password_hash = user["password_hash"]
    if data.get("new_password") is not None:
        if not check_password_hash(user["password_hash"], data.get("current_password") or ""):
            raise AuthError("Current password is incorrect")
        _check_password(data["new_password"], "New password")
        password_hash = generate_password_hash(data["new_password"])

    db.execute("UPDATE users SET name = %s, profile_image = %s, password_hash = %s WHERE user_id = %s",
               (name, image, password_hash, g.user_id))
    user = db.query_one("SELECT * FROM users WHERE user_id = %s", (g.user_id,))
    return jsonify({"user": _public_user(user)})
