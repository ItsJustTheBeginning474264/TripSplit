"""JWT authentication helpers and the @login_required decorator."""
import re
import uuid
from datetime import datetime, timedelta, timezone
from functools import wraps

import jwt
from flask import current_app, g, request

from db import get_db
from errors import AuthError

EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$")
DB_TIME = "%Y-%m-%d %H:%M:%S"


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)


def db_time(dt):
    return dt.strftime(DB_TIME)


def create_token(user_id):
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "jti": uuid.uuid4().hex,
        "iat": now,
        "exp": now + timedelta(hours=current_app.config["JWT_EXPIRY_HOURS"]),
    }
    return jwt.encode(payload, current_app.config["SECRET_KEY"], algorithm="HS256")


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer ") or len(header) <= 7:
            raise AuthError("Authentication required")
        token = header[7:].strip()
        try:
            payload = jwt.decode(token, current_app.config["SECRET_KEY"], algorithms=["HS256"])
            user_id = int(payload["sub"])
            jti = payload["jti"]
        except (jwt.InvalidTokenError, KeyError, ValueError):
            raise AuthError("Invalid or expired token")

        db = get_db()
        if db.query_one("SELECT jti FROM token_blacklist WHERE jti = %s", (jti,)):
            raise AuthError("Token has been logged out")
        user = db.query_one("SELECT user_id FROM users WHERE user_id = %s", (user_id,))
        if user is None:
            raise AuthError("User no longer exists")

        g.user_id = user_id
        g.jti = jti
        g.token_exp = datetime.fromtimestamp(payload["exp"], tz=timezone.utc).replace(tzinfo=None)
        return view(*args, **kwargs)

    return wrapper
