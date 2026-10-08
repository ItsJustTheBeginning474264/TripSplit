# TripSplit

Group trip expense manager: members join a trip with an invite code, record expenses (equal / custom / percentage splits), see everyone's paid / share / balance, and get a **minimal set of payments** that settles the trip.

**Stack:** Flutter (client) · Flask REST API · MySQL · pytest (automated tests)

```
tripsplit/
├── backend/            Flask API (app.py, routes_*.py, splits.py, settlement.py, db.py ...)
│   └── tests/          91 automated tests (pytest)
├── database/
│   ├── schema.sql          MySQL schema: tables, constraints, indexes, views
│   └── sample_queries.sql  INSERT/SELECT/JOIN/GROUP BY/HAVING/subquery/transaction examples
├── frontend/           Flutter app (14 screens)
└── docs/
    ├── DOCUMENTATION.md    SDLC report (requirements, design, implementation, testing, deployment, maintenance)
    ├── TEST_PLAN.md        Test cases with actual results (generated from a real pytest run)
    └── build_test_plan.py  Regenerates TEST_PLAN.md
```

## Quick start

### 1. Database (MySQL 8.0.16+ — needed so CHECK constraints are enforced)
```bash
mysql -u root -p < database/schema.sql
```

### 2. Backend
```bash
cd backend
python -m venv venv && source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt

# configure (defaults shown); on Windows use `set` instead of `export`
export MYSQL_HOST=127.0.0.1 MYSQL_USER=root MYSQL_PASSWORD=yourpassword MYSQL_DB=tripsplit
export SECRET_KEY="a-long-random-string-of-at-least-32-characters"

python seed_demo.py     # optional: creates the Goa Trip 2026 demo (users ishani@example.com ... / password demo123)
python app.py           # API on http://0.0.0.0:5000  (check: http://127.0.0.1:5000/api/health)
```

### 3. Flutter app
```bash
cd frontend
flutter create .        # one-time: generates android/ ios/ folders next to the provided lib/ and pubspec.yaml
flutter pub get
flutter run                                            # Android emulator (uses http://10.0.2.2:5000)
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000   # real phone: your PC's LAN IP
```
On Android, plain-HTTP to a LAN address needs `android:usesCleartextTraffic="true"` on the `<application>` tag in `android/app/src/main/AndroidManifest.xml` (development only), and the `INTERNET` permission (added by default for debug builds).

### 4. Run the automated tests
```bash
cd backend && python -m pytest -q          # 91 tests, no MySQL needed (see docs/TEST_PLAN.md)
cd ../docs && python build_test_plan.py    # regenerate docs/TEST_PLAN.md from a fresh run
```

Full details, diagrams and the API reference are in [`docs/DOCUMENTATION.md`](docs/DOCUMENTATION.md).
