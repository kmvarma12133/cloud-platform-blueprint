from fastapi.testclient import TestClient

from orders_api.main import app

client = TestClient(app)


def test_health_and_ready():
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").status_code == 200


def test_create_and_fetch_order():
    created = client.post("/orders", json={"sku": "ABC-1", "quantity": 2})
    assert created.status_code == 201
    body = created.json()
    assert body["sku"] == "ABC-1" and body["quantity"] == 2

    fetched = client.get(f"/orders/{body['id']}")
    assert fetched.status_code == 200
    assert fetched.json() == body


def test_validation_rejects_bad_quantity():
    assert client.post("/orders", json={"sku": "ABC-1", "quantity": 0}).status_code == 422


def test_missing_order_is_404():
    assert client.get("/orders/does-not-exist").status_code == 404


def test_metrics_use_route_template_not_raw_path():
    client.get("/orders/some-random-id")
    text = client.get("/metrics").text
    assert 'route="/orders/{order_id}"' in text
    assert "some-random-id" not in text
