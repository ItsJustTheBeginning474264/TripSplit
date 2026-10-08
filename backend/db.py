"""Thin database layer.

The application talks to MySQL through PyMySQL using plain parameterised SQL (so the
SQL itself is visible for the DBMS project). A SQLite backend with the same interface
exists only so the automated tests can run on a machine without a MySQL server; all
queries in the application are written in the portable subset both engines accept.
"""
import sqlite3
from collections import namedtuple
from contextlib import contextmanager

import pymysql
import pymysql.cursors
from flask import current_app, g

Result = namedtuple("Result", "lastrowid rowcount")

IntegrityErrors = (pymysql.err.IntegrityError, sqlite3.IntegrityError)


class Database:
    def __init__(self, conn, backend):
        self.conn = conn
        self.backend = backend
        self._in_tx = False

    # -- helpers ---------------------------------------------------------
    def _sql(self, sql):
        return sql.replace("%s", "?") if self.backend == "sqlite" else sql

    def query(self, sql, params=()):
        cur = self.conn.cursor()
        try:
            cur.execute(self._sql(sql), tuple(params))
            return [dict(row) for row in cur.fetchall()]
        finally:
            cur.close()

    def query_one(self, sql, params=()):
        rows = self.query(sql, params)
        return rows[0] if rows else None

    def execute(self, sql, params=()):
        cur = self.conn.cursor()
        try:
            cur.execute(self._sql(sql), tuple(params))
            return Result(cur.lastrowid, cur.rowcount)
        finally:
            cur.close()

    def lock_trip(self, trip_id):
        """Serialise concurrent writers of the same trip (row lock; MySQL only)."""
        if self.backend == "mysql":
            self.query("SELECT trip_id FROM trips WHERE trip_id = %s FOR UPDATE", (trip_id,))

    # -- transactions ----------------------------------------------------
    @contextmanager
    def transaction(self):
        if self._in_tx:            # nested use joins the outer transaction
            yield self
            return
        self._begin()
        self._in_tx = True
        try:
            yield self
            self._commit()
        except BaseException:
            self._rollback()
            raise
        finally:
            self._in_tx = False

    def _begin(self):
        if self.backend == "mysql":
            self.conn.begin()
        else:
            self.conn.execute("BEGIN IMMEDIATE")

    def _commit(self):
        if self.backend == "mysql":
            self.conn.commit()
        else:
            self.conn.execute("COMMIT")

    def _rollback(self):
        if self.backend == "mysql":
            self.conn.rollback()
        else:
            self.conn.execute("ROLLBACK")


def _connect(config):
    if config["DB_BACKEND"] == "sqlite":
        conn = sqlite3.connect(config["SQLITE_PATH"], isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return Database(conn, "sqlite")
    conn = pymysql.connect(
        host=config["MYSQL_HOST"],
        port=config["MYSQL_PORT"],
        user=config["MYSQL_USER"],
        password=config["MYSQL_PASSWORD"],
        database=config["MYSQL_DB"],
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )
    return Database(conn, "mysql")


def get_db():
    if "db" not in g:
        g.db = _connect(current_app.config)
    return g.db


def close_db(_exc=None):
    db = g.pop("db", None)
    if db is not None:
        db.conn.close()
