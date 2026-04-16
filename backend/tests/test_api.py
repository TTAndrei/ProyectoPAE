"""Pruebas de integración de la API REST de PAE.

Cubre los endpoints principales:
- Autenticación (login, /me)
- Pedidos (listar, crear, asignar, responder, actualizar estado)
- Repartidores (listar, actualizar ubicación)
- Rutas (obtener ruta activa)
"""
import pytest

# Marca todos los tests de este módulo como asíncronos con anyio
pytestmark = pytest.mark.anyio


async def test_verificar_estado(cliente):
    """El endpoint /health debe devolver status='ok'."""
    respuesta = await cliente.get("/health")
    assert respuesta.status_code == 200
    assert respuesta.json()["status"] == "ok"


# ── Autenticación ──────────────────────────────────────────────────────────────

async def test_login_central(cliente):
    """El operador central debe poder iniciar sesión y recibir un token."""
    respuesta = await cliente.post(
        "/auth/login", json={"username": "central", "password": "central123"}
    )
    assert respuesta.status_code == 200
    datos = respuesta.json()
    assert "token" in datos
    assert datos["user"]["role"] == "central"


async def test_login_repartidor(cliente):
    """Un repartidor debe poder iniciar sesión con sus credenciales."""
    respuesta = await cliente.post(
        "/auth/login", json={"username": "driver1", "password": "driver123"}
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["user"]["role"] == "repartidor"


async def test_login_contrasena_incorrecta(cliente):
    """Las credenciales incorrectas deben devolver 401 Unauthorized."""
    respuesta = await cliente.post(
        "/auth/login", json={"username": "central", "password": "incorrecta"}
    )
    assert respuesta.status_code == 401


async def test_yo_sin_token(cliente):
    """Acceder a /auth/me sin token debe devolver 403."""
    respuesta = await cliente.get("/auth/me")
    assert respuesta.status_code == 403  # HTTPBearer devuelve 403 si no hay encabezado


async def test_yo_con_token(cliente, token_central):
    """Con un token válido, /auth/me debe devolver los datos del usuario autenticado."""
    respuesta = await cliente.get(
        "/auth/me", headers={"Authorization": f"Bearer {token_central}"}
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["username"] == "central"


# ── Pedidos ────────────────────────────────────────────────────────────────────

async def test_listar_pedidos_central(cliente, token_central):
    """La central debe poder ver todos los pedidos del sistema."""
    respuesta = await cliente.get(
        "/orders/", headers={"Authorization": f"Bearer {token_central}"}
    )
    assert respuesta.status_code == 200
    assert isinstance(respuesta.json(), list)
    assert len(respuesta.json()) > 0


async def test_crear_pedido_central(cliente, token_central):
    """La central debe poder crear un nuevo pedido con estado 'pending'."""
    respuesta = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Calle Prueba 1", "lat": 40.42, "lng": -3.7},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 201
    datos = respuesta.json()
    assert datos["type"] == "pickup"
    assert datos["status"] == "pending"


async def test_crear_pedido_repartidor_prohibido(cliente, token_repartidor1):
    """Un repartidor no debe poder crear pedidos (403 Forbidden)."""
    respuesta = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Prueba", "lat": 40.42, "lng": -3.7},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 403


async def test_crear_pedido_tipo_invalido(cliente, token_central):
    """Un tipo de pedido no válido debe devolver 422 Unprocessable Entity."""
    respuesta = await cliente.post(
        "/orders/",
        json={"type": "invalido", "address": "Prueba", "lat": 40.42, "lng": -3.7},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 422


async def test_asignar_pedido(cliente, token_central):
    """La central debe poder asignar un pedido a un repartidor y recibir el tiempo extra."""
    # Primero crear un pedido pendiente
    respuesta_crear = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Asignación de prueba", "lat": 40.42, "lng": -3.71},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    id_pedido = respuesta_crear.json()["id"]

    # Asignar el pedido al repartidor
    respuesta = await cliente.post(
        f"/orders/{id_pedido}/assign",
        json={"driver_id": "driver-1"},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 200
    datos = respuesta.json()
    assert datos["order"]["status"] == "assigned"
    assert isinstance(datos["extra_minutes"], float)


async def test_responder_pedido_aceptar(cliente, token_central, token_repartidor1):
    """El repartidor debe poder aceptar una recogida asignada."""
    respuesta_crear = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Aceptar prueba", "lat": 40.43, "lng": -3.69},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    id_pedido = respuesta_crear.json()["id"]

    await cliente.post(
        f"/orders/{id_pedido}/assign",
        json={"driver_id": "driver-1"},
        headers={"Authorization": f"Bearer {token_central}"},
    )

    respuesta = await cliente.post(
        f"/orders/{id_pedido}/respond",
        json={"accepted": True},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["order"]["status"] == "in_progress"


async def test_responder_pedido_rechazar(cliente, token_central, token_repartidor1):
    """El repartidor debe poder rechazar una recogida asignada."""
    respuesta_crear = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Rechazar prueba", "lat": 40.43, "lng": -3.69},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    id_pedido = respuesta_crear.json()["id"]

    await cliente.post(
        f"/orders/{id_pedido}/assign",
        json={"driver_id": "driver-1"},
        headers={"Authorization": f"Bearer {token_central}"},
    )

    respuesta = await cliente.post(
        f"/orders/{id_pedido}/respond",
        json={"accepted": False},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["order"]["status"] == "rejected"


# ── Repartidores ───────────────────────────────────────────────────────────────

async def test_listar_repartidores_central(cliente, token_central):
    """La central debe poder ver la lista de todos los repartidores con ubicación."""
    respuesta = await cliente.get(
        "/drivers/", headers={"Authorization": f"Bearer {token_central}"}
    )
    assert respuesta.status_code == 200
    repartidores = respuesta.json()
    assert isinstance(repartidores, list)
    assert len(repartidores) >= 2


async def test_listar_repartidores_repartidor_prohibido(cliente, token_repartidor1):
    """Un repartidor no debe poder ver la lista de otros repartidores (403)."""
    respuesta = await cliente.get(
        "/drivers/", headers={"Authorization": f"Bearer {token_repartidor1}"}
    )
    assert respuesta.status_code == 403


async def test_actualizar_ubicacion_repartidor(cliente, token_repartidor1):
    """El repartidor debe poder actualizar su propia ubicación GPS."""
    respuesta = await cliente.put(
        "/drivers/driver-1/location",
        json={"lat": 40.42, "lng": -3.71, "heading": 90.0},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["success"] is True


async def test_actualizar_ubicacion_otro_repartidor_prohibido(cliente, token_repartidor1):
    """Un repartidor no debe poder actualizar la ubicación de otro (403)."""
    respuesta = await cliente.put(
        "/drivers/driver-2/location",
        json={"lat": 40.42, "lng": -3.71},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 403


# ── Rutas ─────────────────────────────────────────────────────────────────────

async def test_obtener_ruta_repartidor(cliente, token_repartidor1):
    """El repartidor debe poder obtener su ruta activa con la lista de paradas."""
    respuesta = await cliente.get(
        "/orders/route/driver-1",
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 200
    datos = respuesta.json()
    assert "orders" in datos
    assert isinstance(datos["orders"], list)
    assert "total_minutes" in datos
    assert "total_distance_km" in datos
    assert "route_geometry" in datos
    assert "leg_minutes" in datos
    assert isinstance(datos["route_geometry"], list)
    assert isinstance(datos["leg_minutes"], list)
