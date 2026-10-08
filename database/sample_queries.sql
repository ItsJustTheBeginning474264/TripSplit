-- ============================================================================
--  TripSplit - example queries demonstrating the DBMS concepts used in the project
--  (run after schema.sql; the demo data comes from `python seed_demo.py`)
--  Replace the literal ids (1, 2 ...) with ids that exist in your database.
-- ============================================================================
USE tripsplit;

-- ---------------------------------------------------------------------------
-- 1. INSERT
-- ---------------------------------------------------------------------------
INSERT INTO users (name, email, password_hash)
VALUES ('Demo User', 'demo@example.com', 'pbkdf2:sha256:...hash-produced-by-the-API...');

INSERT INTO trips (trip_name, destination, start_date, end_date, created_by, invite_code)
VALUES ('Goa Trip 2026', 'Goa', '2026-12-10', '2026-12-15', 1, 'GOA26X');

INSERT INTO trip_members (trip_id, user_id, role) VALUES (1, 1, 'admin');

-- ---------------------------------------------------------------------------
-- 2. SELECT with JOIN : members of a trip with their role
-- ---------------------------------------------------------------------------
SELECT u.user_id, u.name, tm.role, tm.joined_at
FROM trip_members tm
JOIN users u ON u.user_id = tm.user_id
WHERE tm.trip_id = 1
ORDER BY tm.joined_at;

-- Expenses of a trip with the name of the payer (JOIN) - newest first
SELECT e.expense_id, e.description, e.amount, e.category, u.name AS paid_by_name, e.expense_date
FROM expenses e
JOIN users u ON u.user_id = e.paid_by
WHERE e.trip_id = 1
ORDER BY e.expense_date DESC;

-- ---------------------------------------------------------------------------
-- 3. UPDATE
-- ---------------------------------------------------------------------------
UPDATE expenses SET amount = 3800.00, description = 'Dinner (incl. drinks)' WHERE expense_id = 1;
UPDATE settlements SET status = 'paid', paid_at = UTC_TIMESTAMP() WHERE settlement_id = 1;

-- ---------------------------------------------------------------------------
-- 4. DELETE  (ON DELETE CASCADE removes the expense_splits rows automatically)
-- ---------------------------------------------------------------------------
DELETE FROM expenses WHERE expense_id = 1;
DELETE FROM settlements WHERE trip_id = 1 AND status = 'pending';

-- ---------------------------------------------------------------------------
-- 5. Aggregate functions + GROUP BY : spending per category
-- ---------------------------------------------------------------------------
SELECT category, COUNT(*) AS expense_count, SUM(amount) AS total, AVG(amount) AS average,
       MAX(amount) AS biggest
FROM expenses
WHERE trip_id = 1
GROUP BY category
ORDER BY total DESC;

-- ---------------------------------------------------------------------------
-- 6. GROUP BY + HAVING : members who paid more than ₹5,000 in total on a trip
-- ---------------------------------------------------------------------------
SELECT u.name, SUM(e.amount) AS total_paid
FROM expenses e
JOIN users u ON u.user_id = e.paid_by
WHERE e.trip_id = 1
GROUP BY u.user_id, u.name
HAVING SUM(e.amount) > 5000
ORDER BY total_paid DESC;

-- Categories where the trip spent more than 20% of its total money
SELECT category, SUM(amount) AS total
FROM expenses
WHERE trip_id = 1
GROUP BY category
HAVING SUM(amount) > 0.20 * (SELECT SUM(amount) FROM expenses WHERE trip_id = 1);

-- ---------------------------------------------------------------------------
-- 7. Subqueries
-- ---------------------------------------------------------------------------
-- (a) scalar subquery - expenses bigger than the trip's average expense
SELECT description, amount
FROM expenses
WHERE trip_id = 1
  AND amount > (SELECT AVG(amount) FROM expenses WHERE trip_id = 1);

-- (b) IN subquery - all trips a user belongs to
SELECT trip_id, trip_name FROM trips
WHERE trip_id IN (SELECT trip_id FROM trip_members WHERE user_id = 1);

-- (c) EXISTS - authorization check: is user 2 a member of trip 1?
SELECT EXISTS (SELECT 1 FROM trip_members WHERE trip_id = 1 AND user_id = 2) AS is_member;

-- (d) correlated subquery - each member's total share of the trip
SELECT u.name,
       (SELECT COALESCE(SUM(es.amount), 0)
          FROM expense_splits es
          JOIN expenses e ON e.expense_id = es.expense_id
         WHERE e.trip_id = tm.trip_id AND es.user_id = tm.user_id) AS total_share
FROM trip_members tm
JOIN users u ON u.user_id = tm.user_id
WHERE tm.trip_id = 1;

-- ---------------------------------------------------------------------------
-- 8. VIEWS : balances computed once, reused by the API
-- ---------------------------------------------------------------------------
-- positive balance => should receive money, negative => owes money
SELECT user_id, name, total_paid, total_share,
       total_paid - total_share                                  AS balance,
       total_paid - total_share + settled_out - settled_in       AS remaining_balance
FROM v_member_balances
WHERE trip_id = 1
ORDER BY balance DESC;

-- creditors and debtors (input of the settlement algorithm)
SELECT name, total_paid - total_share + settled_out - settled_in AS remaining_balance
FROM v_member_balances
WHERE trip_id = 1
HAVING remaining_balance <> 0;

SELECT * FROM v_trip_totals WHERE trip_id = 1;

-- ---------------------------------------------------------------------------
-- 9. TRANSACTION : an expense and all of its splits are stored atomically
-- ---------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, category, split_type, expense_date)
VALUES (1, 2, 2, 'Dinner', 3600.00, 'Food', 'equal', '2026-12-11 20:30:00');
SET @new_expense = LAST_INSERT_ID();

INSERT INTO expense_splits (expense_id, user_id, amount) VALUES
    (@new_expense, 1, 1200.00),
    (@new_expense, 2, 1200.00),
    (@new_expense, 3, 1200.00);

-- the old suggested payments are now out-of-date
DELETE FROM settlements WHERE trip_id = 1 AND status = 'pending';

COMMIT;            -- use ROLLBACK; instead to undo everything

-- ---------------------------------------------------------------------------
-- 10. CONSTRAINTS in action (each statement below is REJECTED by the database)
-- ---------------------------------------------------------------------------
-- duplicate e-mail            -> UNIQUE   uq_users_email
-- INSERT INTO users (name, email, password_hash) VALUES ('X', 'demo@example.com', 'h');
-- duplicate membership        -> UNIQUE   uq_trip_members_trip_user
-- INSERT INTO trip_members (trip_id, user_id) VALUES (1, 1);
-- zero / negative amount      -> CHECK    chk_expenses_amount_positive
-- INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, split_type, expense_date)
--   VALUES (1, 1, 1, 'Bad', -50, 'equal', NOW());
-- unknown trip                -> FOREIGN KEY fk_exp_trip
-- INSERT INTO expenses (trip_id, paid_by, created_by, description, amount, split_type, expense_date)
--   VALUES (9999, 1, 1, 'Bad', 50, 'equal', NOW());
-- end date before start date  -> CHECK    chk_trips_dates
-- INSERT INTO trips (trip_name, destination, start_date, end_date, created_by, invite_code)
--   VALUES ('Bad', 'Nowhere', '2026-12-15', '2026-12-10', 1, 'BAD123');

-- ---------------------------------------------------------------------------
-- 11. Integrity check : every expense's splits must add up to the expense amount
--     (this query must return zero rows)
-- ---------------------------------------------------------------------------
SELECT e.expense_id, e.amount, SUM(es.amount) AS split_total
FROM expenses e
JOIN expense_splits es ON es.expense_id = e.expense_id
GROUP BY e.expense_id, e.amount
HAVING e.amount <> SUM(es.amount);

-- Whole-trip sanity check : total paid must equal total shared (so balances sum to 0)
SELECT SUM(total_paid) AS paid, SUM(total_share) AS shared,
       SUM(total_paid - total_share) AS net_should_be_zero
FROM v_member_balances
WHERE trip_id = 1;
