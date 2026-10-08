-- ============================================================================
--  TripSplit - MySQL schema (MySQL 8.0.16+ so that CHECK constraints are enforced)
--  Run with:   mysql -u root -p < database/schema.sql
-- ============================================================================

CREATE DATABASE IF NOT EXISTS tripsplit
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE tripsplit;

-- Drop in reverse dependency order so the script can be re-run during development.
DROP VIEW  IF EXISTS v_trip_totals;
DROP VIEW  IF EXISTS v_member_balances;
DROP TABLE IF EXISTS token_blacklist;
DROP TABLE IF EXISTS settlements;
DROP TABLE IF EXISTS expense_splits;
DROP TABLE IF EXISTS expenses;
DROP TABLE IF EXISTS trip_members;
DROP TABLE IF EXISTS trips;
DROP TABLE IF EXISTS users;

-- ----------------------------------------------------------------------------
--  users
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    name           VARCHAR(100)  NOT NULL,
    email          VARCHAR(255)  NOT NULL,
    password_hash  VARCHAR(255)  NOT NULL,
    profile_image  VARCHAR(255)  NULL,
    created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_users_email (email),
    CONSTRAINT chk_users_name_not_blank CHECK (CHAR_LENGTH(TRIM(name)) > 0)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
--  trips
-- ----------------------------------------------------------------------------
CREATE TABLE trips (
    trip_id      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    trip_name    VARCHAR(100)  NOT NULL,
    destination  VARCHAR(100)  NOT NULL,
    start_date   DATE          NOT NULL,
    end_date     DATE          NOT NULL,
    created_by   INT UNSIGNED  NOT NULL,
    invite_code  CHAR(6)       NOT NULL,
    status       ENUM('active','completed') NOT NULL DEFAULT 'active',
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (trip_id),
    UNIQUE KEY uq_trips_invite_code (invite_code),
    KEY idx_trips_created_by (created_by),
    CONSTRAINT fk_trips_creator FOREIGN KEY (created_by)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_trips_dates CHECK (end_date >= start_date)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
--  trip_members : resolves the many-to-many relationship users <-> trips
-- ----------------------------------------------------------------------------
CREATE TABLE trip_members (
    trip_member_id  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    trip_id         INT UNSIGNED NOT NULL,
    user_id         INT UNSIGNED NOT NULL,
    role            ENUM('admin','member') NOT NULL DEFAULT 'member',
    joined_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (trip_member_id),
    UNIQUE KEY uq_trip_members_trip_user (trip_id, user_id),   -- no duplicate membership
    KEY idx_trip_members_user (user_id),
    CONSTRAINT fk_tm_trip FOREIGN KEY (trip_id)
        REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_tm_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
--  expenses
-- ----------------------------------------------------------------------------
CREATE TABLE expenses (
    expense_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    trip_id       INT UNSIGNED  NOT NULL,
    paid_by       INT UNSIGNED  NOT NULL,
    created_by    INT UNSIGNED  NOT NULL,
    description   VARCHAR(255)  NOT NULL,
    amount        DECIMAL(12,2) NOT NULL,
    category      ENUM('Food','Hotel','Transportation','Activities',
                       'Shopping','Tickets','Fuel','Other') NOT NULL DEFAULT 'Other',
    split_type    ENUM('equal','custom','percentage') NOT NULL,
    expense_date  DATETIME      NOT NULL,
    created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (expense_id),
    KEY idx_expenses_trip_date (trip_id, expense_date),
    KEY idx_expenses_paid_by (paid_by),
    KEY idx_expenses_created_by (created_by),
    CONSTRAINT fk_exp_trip FOREIGN KEY (trip_id)
        REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_exp_paid_by FOREIGN KEY (paid_by)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_exp_created_by FOREIGN KEY (created_by)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_expenses_amount_positive CHECK (amount > 0),
    CONSTRAINT chk_expenses_desc_not_blank CHECK (CHAR_LENGTH(TRIM(description)) > 0)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
--  expense_splits : one row per participant of an expense
-- ----------------------------------------------------------------------------
CREATE TABLE expense_splits (
    split_id    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    expense_id  INT UNSIGNED  NOT NULL,
    user_id     INT UNSIGNED  NOT NULL,
    amount      DECIMAL(12,2) NOT NULL,
    percentage  DECIMAL(5,2)  NULL,
    PRIMARY KEY (split_id),
    UNIQUE KEY uq_splits_expense_user (expense_id, user_id),
    KEY idx_splits_user (user_id),
    CONSTRAINT fk_split_expense FOREIGN KEY (expense_id)
        REFERENCES expenses (expense_id) ON DELETE CASCADE,
    CONSTRAINT fk_split_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_splits_amount CHECK (amount >= 0),
    CONSTRAINT chk_splits_percentage CHECK (percentage IS NULL OR (percentage > 0 AND percentage <= 100))
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
--  settlements : suggested / completed payments between two members
-- ----------------------------------------------------------------------------
CREATE TABLE settlements (
    settlement_id  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    trip_id        INT UNSIGNED  NOT NULL,
    payer_id       INT UNSIGNED  NOT NULL,
    receiver_id    INT UNSIGNED  NOT NULL,
    amount         DECIMAL(12,2) NOT NULL,
    status         ENUM('pending','paid') NOT NULL DEFAULT 'pending',
    created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at        DATETIME      NULL,
    PRIMARY KEY (settlement_id),
    KEY idx_settlements_trip_status (trip_id, status),
    KEY idx_settlements_payer (payer_id),
    KEY idx_settlements_receiver (receiver_id),
    CONSTRAINT fk_set_trip FOREIGN KEY (trip_id)
        REFERENCES trips (trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_set_payer FOREIGN KEY (payer_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_set_receiver FOREIGN KEY (receiver_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_settlements_amount CHECK (amount > 0),
    CONSTRAINT chk_settlements_distinct CHECK (payer_id <> receiver_id),
    CONSTRAINT chk_settlements_paid_at CHECK (
        (status = 'paid' AND paid_at IS NOT NULL) OR (status = 'pending' AND paid_at IS NULL))
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
--  token_blacklist : JWTs revoked by logout (purged once they expire)
-- ----------------------------------------------------------------------------
CREATE TABLE token_blacklist (
    jti         VARCHAR(64) NOT NULL,
    expires_at  DATETIME    NOT NULL,
    PRIMARY KEY (jti),
    KEY idx_blacklist_expires (expires_at)
) ENGINE=InnoDB;

-- ============================================================================
--  VIEWS
-- ============================================================================

-- Per-member money position inside a trip.
--   total_paid   = what the member actually paid out of pocket
--   total_share  = what the member should have contributed (sum of their splits)
--   settled_out  = settlement payments the member has already made   (status = 'paid')
--   settled_in   = settlement payments the member has already received (status = 'paid')
CREATE OR REPLACE VIEW v_member_balances AS
SELECT
    tm.trip_id,
    tm.user_id,
    u.name,
    COALESCE((SELECT SUM(e.amount)
                FROM expenses e
               WHERE e.trip_id = tm.trip_id AND e.paid_by = tm.user_id), 0) AS total_paid,
    COALESCE((SELECT SUM(es.amount)
                FROM expense_splits es
                JOIN expenses e ON e.expense_id = es.expense_id
               WHERE e.trip_id = tm.trip_id AND es.user_id = tm.user_id), 0) AS total_share,
    COALESCE((SELECT SUM(s.amount)
                FROM settlements s
               WHERE s.trip_id = tm.trip_id AND s.payer_id = tm.user_id
                 AND s.status = 'paid'), 0) AS settled_out,
    COALESCE((SELECT SUM(s.amount)
                FROM settlements s
               WHERE s.trip_id = tm.trip_id AND s.receiver_id = tm.user_id
                 AND s.status = 'paid'), 0) AS settled_in
FROM trip_members tm
JOIN users u ON u.user_id = tm.user_id;

CREATE OR REPLACE VIEW v_trip_totals AS
SELECT
    t.trip_id,
    (SELECT COUNT(*) FROM trip_members tm WHERE tm.trip_id = t.trip_id)         AS member_count,
    (SELECT COUNT(*) FROM expenses e WHERE e.trip_id = t.trip_id)               AS expense_count,
    COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.trip_id = t.trip_id), 0) AS total_expenses
FROM trips t;
