import os

import pytest

os.environ.setdefault("APP_VERSION", "test")

from app import app  # noqa: E402


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_hello_world(client):
    resp = client.get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["message"] == "Hello, World! (updated)"
    assert body["version"] == "test"


def test_healthz(client):
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_readyz_without_db(client):
    # DB_HOST is unset in the test env, so readiness should report not_ready
    # rather than crashing.
    resp = client.get("/readyz")
    assert resp.status_code == 503
    assert resp.get_json()["status"] == "not_ready"
