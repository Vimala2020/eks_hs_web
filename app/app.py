
import os
import socket

import pymysql
from flask import Flask, jsonify


app = Flask(__name__)


APP_VERSION = os.environ.get("APP_VERSION", "dev")
DB_HOST = os.environ.get("DB_HOST")
DB_PORT = os.environ.get("DB_PORT", 3306)
DB_USER = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
DB_NAME = os.environ.get("DB_NAME")


@app.route("/")
def hello_world():
    return jsonify(
        message="Hello, World! (updated)",
        version=APP_VERSION,
        served_by=socket.gethostname(),
    )


@app.route("/healthz")
def healthz():
    """Liveness: is the process alive. Kept dependency-free on purpose so a
    slow/unavailable DB doesn't cause Kubernetes to kill healthy pods."""
    return jsonify(status="ok"), 200


@app.route("/readyz")
def readyz():
    """Readiness: can this pod actually serve real traffic, i.e. can it
    reach MySQL. Used by the Service/Ingress to pull a pod out of rotation
    without restarting it."""
    if not DB_HOST:
        return jsonify(status="not_ready", reason="DB_HOST not configured"), 503
    try:
        conn = pymysql.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            connect_timeout=2,
        )
        conn.close()
        return jsonify(status="ready"), 200
    except Exception as exc:  # noqa: BLE001 - want any DB error to fail readiness
        return jsonify(status="not_ready", reason=str(exc)), 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
