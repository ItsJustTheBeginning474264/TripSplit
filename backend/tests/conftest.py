import os
import sqlite3
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))      # make backend modules importable
sys.path.insert(0, HERE)                       # make helpers importable

from app import create_app  # noqa: E402


@pytest.fixture()
def app(tmp_path):
    """A Flask app wired to a fresh SQLite database built from tests/schema_sqlite.sql."""
    db_path = str(tmp_path / "test.sqlite3")
    conn = sqlite3.connect(db_path)
    with open(os.path.join(HERE, "schema_sqlite.sql"), encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.close()
    app = create_app({"TESTING": True, "DB_BACKEND": "sqlite", "SQLITE_PATH": db_path,
                      "SECRET_KEY": "test-secret-key-that-is-at-least-32-bytes-long"})
    app.config["DB_FILE"] = db_path
    return app


@pytest.fixture()
def client(app):
    return app.test_client()
