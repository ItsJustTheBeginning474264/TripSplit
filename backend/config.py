import os


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-change-me-in-production")
    JWT_EXPIRY_HOURS = int(os.environ.get("JWT_EXPIRY_HOURS", "72"))

    # "mysql" for the real application; "sqlite" is used only by the automated tests.
    DB_BACKEND = os.environ.get("DB_BACKEND", "mysql")
    MYSQL_HOST = os.environ.get("MYSQL_HOST", "127.0.0.1")
    MYSQL_PORT = int(os.environ.get("MYSQL_PORT", "3306"))
    MYSQL_USER = os.environ.get("MYSQL_USER", "root")
    MYSQL_PASSWORD = os.environ.get("MYSQL_PASSWORD", "")
    MYSQL_DB = os.environ.get("MYSQL_DB", "tripsplit")
    SQLITE_PATH = os.environ.get("SQLITE_PATH", "tripsplit_test.sqlite3")

    JSON_SORT_KEYS = False
