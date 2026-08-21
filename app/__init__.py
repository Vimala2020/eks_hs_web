import os
import socket

import pymysql
from flask import Flask, jsonify
from prometheus_client import CollectorRegistry
from prometheus_flask_exporter import PrometheusMetrics


def create_app(test_config=None):
    app = Flask(__name__)

    app.config.from_mapping(
        APP_VERSION=os.environ.get("APP_VERSION", "dev"),
        DB_HOST=os.environ.get("DB_HOST"),
        DB_PORT=int(os.environ.get("DB_PORT", 3306)),
        DB_USER=os.environ.get("DB_USER"),
        DB_PASSWORD=os.environ.get("DB_PASSWORD"),
        DB_NAME=os.environ.get("DB_NAME"),
    )

    if test_config:
        app.config.update(test_config)

    metrics = PrometheusMetrics(app, registry=CollectorRegistry(auto_describe=True))
    metrics.info("app_info", "Application info", version=app.config["APP_VERSION"])

    @app.get("/")
    def hello_world():
        return jsonify(
            message="Hello, World! (updated)",
            version=app.config["APP_VERSION"],
            served_by=socket.gethostname(),
        )

    @app.get("/healthz")
    def healthz():
        """Liveness: is the process alive. Kept dependency-free on purpose so a
        slow/unavailable DB doesn't cause Kubernetes to kill healthy pods."""
        return jsonify(status="ok"), 200

    @app.get("/readyz")
    def readyz():
        """Readiness: can this pod actually serve real traffic, i.e. can it
        reach MySQL. Used by the Service/Ingress to pull a pod out of rotation
        without restarting it."""
        db_host = app.config.get("DB_HOST")
        if not db_host:
            return jsonify(status="not_ready", reason="DB_HOST not configured"), 503

        try:
            conn = pymysql.connect(
                host=db_host,
                port=app.config.get("DB_PORT", 3306),
                user=app.config.get("DB_USER"),
                password=app.config.get("DB_PASSWORD"),
                database=app.config.get("DB_NAME"),
                connect_timeout=2,
            )
            conn.close()
            return jsonify(status="ready"), 200
        except Exception as exc:  # noqa: BLE001 - want any DB error to fail readiness
            return jsonify(status="not_ready", reason=str(exc)), 503

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
