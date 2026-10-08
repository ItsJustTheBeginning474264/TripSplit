-- SQLite twin of database/schema.sql. Used ONLY by the automated test-suite so the
-- API tests can run without a MySQL server. The table/column/view names and the
-- constraints mirror the MySQL schema.
PRAGMA foreign_keys = ON;

CREATE TABLE users (
    user_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    name           TEXT NOT NULL CHECK (length(trim(name)) > 0),
    email          TEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    profile_image  TEXT,
    created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trips (
    trip_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_name    TEXT NOT NULL,
    destination  TEXT NOT NULL,
    start_date   TEXT NOT NULL,
    end_date     TEXT NOT NULL,
    created_by   INTEGER NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    invite_code  TEXT NOT NULL UNIQUE,
    status       TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed')),
    created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_date >= start_date)
);

CREATE TABLE trip_members (
    trip_member_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id         INTEGER NOT NULL REFERENCES trips (trip_id) ON DELETE CASCADE,
    user_id         INTEGER NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin','member')),
    joined_at       TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (trip_id, user_id)
);

CREATE TABLE expenses (
    expense_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id       INTEGER NOT NULL REFERENCES trips (trip_id) ON DELETE CASCADE,
    paid_by       INTEGER NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    created_by    INTEGER NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    description   TEXT NOT NULL CHECK (length(trim(description)) > 0),
    amount        NUMERIC NOT NULL CHECK (amount > 0),
    category      TEXT NOT NULL DEFAULT 'Other' CHECK (category IN
                    ('Food','Hotel','Transportation','Activities','Shopping','Tickets','Fuel','Other')),
    split_type    TEXT NOT NULL CHECK (split_type IN ('equal','custom','percentage')),
    expense_date  TEXT NOT NULL,
    created_at    TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_expenses_trip_date ON expenses (trip_id, expense_date);

CREATE TABLE expense_splits (
    split_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    expense_id  INTEGER NOT NULL REFERENCES expenses (expense_id) ON DELETE CASCADE,
    user_id     INTEGER NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    amount      NUMERIC NOT NULL CHECK (amount >= 0),
    percentage  NUMERIC CHECK (percentage IS NULL OR (percentage > 0 AND percentage <= 100)),
    UNIQUE (expense_id, user_id)
);

CREATE TABLE settlements (
    settlement_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    trip_id        INTEGER NOT NULL REFERENCES trips (trip_id) ON DELETE CASCADE,
    payer_id       INTEGER NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    receiver_id    INTEGER NOT NULL REFERENCES users (user_id) ON DELETE RESTRICT,
    amount         NUMERIC NOT NULL CHECK (amount > 0),
    status         TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid')),
    created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at        TEXT,
    CHECK (payer_id <> receiver_id),
    CHECK ((status = 'paid' AND paid_at IS NOT NULL) OR (status = 'pending' AND paid_at IS NULL))
);

CREATE TABLE token_blacklist (
    jti         TEXT PRIMARY KEY,
    expires_at  TEXT NOT NULL
);

CREATE VIEW v_member_balances AS
SELECT
    tm.trip_id,
    tm.user_id,
    u.name,
    COALESCE((SELECT SUM(e.amount) FROM expenses e
               WHERE e.trip_id = tm.trip_id AND e.paid_by = tm.user_id), 0) AS total_paid,
    COALESCE((SELECT SUM(es.amount) FROM expense_splits es
                JOIN expenses e ON e.expense_id = es.expense_id
               WHERE e.trip_id = tm.trip_id AND es.user_id = tm.user_id), 0) AS total_share,
    COALESCE((SELECT SUM(s.amount) FROM settlements s
               WHERE s.trip_id = tm.trip_id AND s.payer_id = tm.user_id
                 AND s.status = 'paid'), 0) AS settled_out,
    COALESCE((SELECT SUM(s.amount) FROM settlements s
               WHERE s.trip_id = tm.trip_id AND s.receiver_id = tm.user_id
                 AND s.status = 'paid'), 0) AS settled_in
FROM trip_members tm
JOIN users u ON u.user_id = tm.user_id;

CREATE VIEW v_trip_totals AS
SELECT
    t.trip_id,
    (SELECT COUNT(*) FROM trip_members tm WHERE tm.trip_id = t.trip_id) AS member_count,
    (SELECT COUNT(*) FROM expenses e WHERE e.trip_id = t.trip_id)       AS expense_count,
    COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.trip_id = t.trip_id), 0) AS total_expenses
FROM trips t;
