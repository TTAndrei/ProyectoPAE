"""API integration tests."""
import pytest

pytestmark = pytest.mark.anyio


async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


# ── Auth ──────────────────────────────────────────────────────────────────────

async def test_login_central(client):
    resp = await client.post("/auth/login", json={"username": "central", "password": "central123"})
    assert resp.status_code == 200
    data = resp.json()
    assert "token" in data
    assert data["user"]["role"] == "central"


async def test_login_driver(client):
    resp = await client.post("/auth/login", json={"username": "driver1", "password": "driver123"})
    assert resp.status_code == 200
    assert resp.json()["user"]["role"] == "repartidor"


async def test_login_wrong_password(client):
    resp = await client.post("/auth/login", json={"username": "central", "password": "wrong"})
    assert resp.status_code == 401


async def test_me_no_token(client):
    resp = await client.get("/auth/me")
    assert resp.status_code == 403  # HTTPBearer returns 403 when no header


async def test_me_with_token(client, central_token):
    resp = await client.get("/auth/me", headers={"Authorization": f"Bearer {central_token}"})
    assert resp.status_code == 200
    assert resp.json()["username"] == "central"


# ── Orders ────────────────────────────────────────────────────────────────────

async def test_list_orders_central(client, central_token):
    resp = await client.get("/orders/", headers={"Authorization": f"Bearer {central_token}"})
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)
    assert len(resp.json()) > 0


async def test_create_order_central(client, central_token):
    resp = await client.post(
        "/orders/",
        json={"type": "pickup", "address": "Test St 1", "lat": 40.42, "lng": -3.7},
        headers={"Authorization": f"Bearer {central_token}"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["type"] == "pickup"
    assert data["status"] == "pending"


async def test_create_order_driver_forbidden(client, driver1_token):
    resp = await client.post(
        "/orders/",
        json={"type": "pickup", "address": "Test", "lat": 40.42, "lng": -3.7},
        headers={"Authorization": f"Bearer {driver1_token}"},
    )
    assert resp.status_code == 403


async def test_create_order_invalid_type(client, central_token):
    resp = await client.post(
        "/orders/",
        json={"type": "invalid", "address": "Test", "lat": 40.42, "lng": -3.7},
        headers={"Authorization": f"Bearer {central_token}"},
    )
    assert resp.status_code == 422


async def test_assign_order(client, central_token):
    # Create order first
    create_resp = await client.post(
        "/orders/",
        json={"type": "pickup", "address": "Assign Test", "lat": 40.42, "lng": -3.71},
        headers={"Authorization": f"Bearer {central_token}"},
    )
    order_id = create_resp.json()["id"]

    resp = await client.post(
        f"/orders/{order_id}/assign",
        json={"driver_id": "driver-1"},
        headers={"Authorization": f"Bearer {central_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["order"]["status"] == "assigned"
    assert isinstance(data["extra_minutes"], float)


async def test_respond_to_order_accept(client, central_token, driver1_token):
    create_resp = await client.post(
        "/orders/",
        json={"type": "pickup", "address": "Respond Test", "lat": 40.43, "lng": -3.69},
        headers={"Authorization": f"Bearer {central_token}"},
    )
    order_id = create_resp.json()["id"]

    await client.post(
        f"/orders/{order_id}/assign",
        json={"driver_id": "driver-1"},
        headers={"Authorization": f"Bearer {central_token}"},
    )

    resp = await client.post(
        f"/orders/{order_id}/respond",
        json={"accepted": True},
        headers={"Authorization": f"Bearer {driver1_token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["order"]["status"] == "in_progress"


async def test_respond_to_order_reject(client, central_token, driver1_token):
    create_resp = await client.post(
        "/orders/",
        json={"type": "pickup", "address": "Reject Test", "lat": 40.43, "lng": -3.69},
        headers={"Authorization": f"Bearer {central_token}"},
    )
    order_id = create_resp.json()["id"]

    await client.post(
        f"/orders/{order_id}/assign",
        json={"driver_id": "driver-1"},
        headers={"Authorization": f"Bearer {central_token}"},
    )

    resp = await client.post(
        f"/orders/{order_id}/respond",
        json={"accepted": False},
        headers={"Authorization": f"Bearer {driver1_token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["order"]["status"] == "rejected"


# ── Drivers ───────────────────────────────────────────────────────────────────

async def test_list_drivers_central(client, central_token):
    resp = await client.get("/drivers/", headers={"Authorization": f"Bearer {central_token}"})
    assert resp.status_code == 200
    drivers = resp.json()
    assert isinstance(drivers, list)
    assert len(drivers) >= 2


async def test_list_drivers_driver_forbidden(client, driver1_token):
    resp = await client.get("/drivers/", headers={"Authorization": f"Bearer {driver1_token}"})
    assert resp.status_code == 403


async def test_update_driver_location(client, driver1_token):
    resp = await client.put(
        "/drivers/driver-1/location",
        json={"lat": 40.42, "lng": -3.71, "heading": 90.0},
        headers={"Authorization": f"Bearer {driver1_token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["success"] is True


async def test_update_other_driver_location_forbidden(client, driver1_token):
    resp = await client.put(
        "/drivers/driver-2/location",
        json={"lat": 40.42, "lng": -3.71},
        headers={"Authorization": f"Bearer {driver1_token}"},
    )
    assert resp.status_code == 403


# ── Routes ────────────────────────────────────────────────────────────────────

async def test_get_route(client, driver1_token):
    resp = await client.get(
        "/orders/route/driver-1",
        headers={"Authorization": f"Bearer {driver1_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "orders" in data
    assert isinstance(data["orders"], list)
