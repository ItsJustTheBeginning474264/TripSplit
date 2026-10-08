"""TripSplit - Flask application factory.

Run (development):   python app.py
"""
from datetime import date, datetime
from decimal import Decimal

from flask import Flask, jsonify
from flask.json.provider import DefaultJSONProvider
from flask_cors import CORS
from werkzeug.exceptions import HTTPException

from config import Config
from db import IntegrityErrors, close_db
from errors import ApiError


class TripSplitJSONProvider(DefaultJSONProvider):
    """Money as JSON numbers, dates/times as ISO-8601 strings."""
    sort_keys = False

    @staticmethod
    def default(o):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, (datetime, date)):
            return o.isoformat()
        return DefaultJSONProvider.default(o)


def create_app(overrides=None):
    app = Flask(__name__)
    app.config.from_object(Config)
    if overrides:
        app.config.update(overrides)
    app.json = TripSplitJSONProvider(app)
    CORS(app)

    from routes_auth import bp as auth_bp
    from routes_expenses import bp as expenses_bp
    from routes_settlements import bp as settlements_bp
    from routes_trips import bp as trips_bp
    for bp in (auth_bp, trips_bp, expenses_bp, settlements_bp):
        app.register_blueprint(bp)

    app.teardown_appcontext(close_db)

    @app.get("/api/health")
    def health():
        return jsonify({"status": "ok"})

    @app.errorhandler(ApiError)
    def handle_api_error(err):
        return jsonify(err.to_dict()), err.status_code

    def handle_integrity(_err):
        return jsonify({"error": "The request conflicts with existing data"}), 409

    for exc_type in IntegrityErrors:
        app.register_error_handler(exc_type, handle_integrity)

    @app.errorhandler(HTTPException)
    def handle_http(err):
        return jsonify({"error": err.description}), err.code

    @app.errorhandler(Exception)
    def handle_unexpected(err):
        app.logger.exception("Unhandled error: %s", err)
        return jsonify({"error": "Internal server error"}), 500

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=5000, debug=True)
