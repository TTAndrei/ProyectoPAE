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
    crear = await cliente.post(
        "/orders/",
        json={
            "type": "pickup",
            "address": "Pedido listado prueba",
            "lat": 41.6262,
            "lng": 2.6908,
        },
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert crear.status_code == 201
    id_pedido = crear.json()["id"]

    respuesta = await cliente.get(
        "/orders/", headers={"Authorization": f"Bearer {token_central}"}
    )
    assert respuesta.status_code == 200
    datos = respuesta.json()
    assert isinstance(datos, list)
    assert any(pedido["id"] == id_pedido for pedido in datos)


async def test_crear_pedido_central(cliente, token_central):
    """La central debe poder crear un nuevo pedido con estado 'pending'."""
    respuesta = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Calle Prueba 1", "lat": 41.6262, "lng": 2.6908},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 201
    datos = respuesta.json()
    assert datos["type"] == "pickup"
    assert datos["status"] in ["pending", "assigned"]


async def test_crear_pedido_respeta_repartidor_elegido(cliente, token_central):
    """Si central elige un repartidor al crear, no debe autoasignar otro."""
    respuesta = await cliente.post(
        "/orders/",
        json={
            "type": "pickup",
            "address": "Asignacion manual de prueba",
            "lat": 41.6262,
            "lng": 2.6908,
            "driver_id": "driver-2",
        },
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 201
    datos = respuesta.json()
    assert datos["status"] == "assigned"
    assert datos["assigned_driver_id"] == "driver-2"


async def test_crear_pedido_repartidor_prohibido(cliente, token_repartidor1):
    """Un repartidor no debe poder crear pedidos (403 Forbidden)."""
    respuesta = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Prueba", "lat": 41.6262, "lng": 2.6908},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 403


async def test_crear_pedido_tipo_invalido(cliente, token_central):
    """Un tipo de pedido no válido debe devolver 422 Unprocessable Entity."""
    respuesta = await cliente.post(
        "/orders/",
        json={"type": "invalido", "address": "Prueba", "lat": 41.6262, "lng": 2.6908},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 422


async def test_asignar_pedido(cliente, token_central):
    """La central debe poder asignar un pedido a un repartidor y recibir el tiempo extra."""
    # Primero crear un pedido pendiente
    respuesta_crear = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Asignación de prueba", "lat": 41.6262, "lng": 2.6882},
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
    assert datos["order"]["status"] == "in_progress"
    assert isinstance(datos["extra_minutes"], float)


async def test_responder_pedido_aceptar(cliente, token_central, token_repartidor1):
    """El repartidor debe poder aceptar una recogida asignada."""
    respuesta_crear = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Aceptar prueba", "lat": 41.6271, "lng": 2.6819},
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
    print("STATUS CODE IS:", respuesta.status_code)
    print("RESPONSE JSON IS:", respuesta.json())
    assert respuesta.status_code == 200
    assert respuesta.json()["order"]["status"] == "in_progress"


async def test_responder_pedido_rechazar(cliente, token_central, token_repartidor1):
    """El repartidor debe poder rechazar una recogida asignada."""
    respuesta_crear = await cliente.post(
        "/orders/",
        json={"type": "pickup", "address": "Rechazar prueba", "lat": 41.6271, "lng": 2.6819},
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
    datos = respuesta.json()
    assert respuesta.status_code == 200
    assert datos["order"]["status"] in ("assigned", "pending")
    assert datos["order"]["assigned_driver_id"] != "driver-1"


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
        json={"lat": 41.6262, "lng": 2.6882, "heading": 90.0},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["success"] is True


async def test_central_puede_actualizar_ubicacion_repartidor(cliente, token_central):
    """La central puede corregir manualmente la ubicación de un repartidor."""
    respuesta = await cliente.put(
        "/drivers/driver-1/location",
        json={"lat": 41.6262, "lng": 2.6882, "heading": 45.0},
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["success"] is True

    ubicacion = await cliente.get(
        "/drivers/driver-1/location",
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert ubicacion.status_code == 200
    assert ubicacion.json()["lat"] == 41.6262
    assert ubicacion.json()["lng"] == 2.6882


async def test_actualizar_ubicacion_otro_repartidor_prohibido(cliente, token_repartidor1):
    """Un repartidor no debe poder actualizar la ubicación de otro (403)."""
    respuesta = await cliente.put(
        "/drivers/driver-2/location",
        json={"lat": 41.6262, "lng": 2.6882},
        headers={"Authorization": f"Bearer {token_repartidor1}"},
    )
    assert respuesta.status_code == 403


async def test_central_puede_eliminar_repartidor(cliente, token_central):
    """La central puede eliminar un repartidor y sus pedidos vuelven a pendientes."""
    username = "driver-delete-test"
    create = await cliente.post(
        "/auth/register",
        json={
            "username": username,
            "password": "driver123",
            "role": "repartidor",
            "name": "Driver Delete Test",
        },
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert create.status_code == 201
    driver_id = create.json()["id"]

    order = await cliente.post(
        "/orders/",
        json={
            "type": "pickup",
            "address": "Prueba eliminación Pineda",
            "lat": 41.6262,
            "lng": 2.6908,
            "driver_id": driver_id,
        },
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert order.status_code == 201
    order_id = order.json()["id"]

    delete = await cliente.delete(
        f"/drivers/{driver_id}",
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert delete.status_code == 200
    assert delete.json()["success"] is True

    drivers = await cliente.get(
        "/drivers/",
        headers={"Authorization": f"Bearer {token_central}"},
    )
    assert all(driver["id"] != driver_id for driver in drivers.json())

    orders = await cliente.get(
        "/orders/",
        headers={"Authorization": f"Bearer {token_central}"},
    )
    released = next(item for item in orders.json() if item["id"] == order_id)
    assert released["status"] == "pending"
    assert released["assigned_driver_id"] is None


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


# ── Registro de Conductores ───────────────────────────────────────────────────

async def test_registrar_repartidor_con_compania(cliente, token_central):
    """La central debe poder registrar un nuevo conductor y este debe asociarse a su compañía."""
    import uuid
    username_nuevo = f"driver_test_new_{uuid.uuid4().hex[:8]}"
    respuesta = await cliente.post(
        "/auth/register",
        json={
            "username": username_nuevo,
            "password": "driver123password",
            "role": "repartidor",
            "name": "Driver Test Registrado"
        },
        headers={"Authorization": f"Bearer {token_central}"}
    )
    assert respuesta.status_code == 201
    datos = respuesta.json()
    assert datos["username"] == username_nuevo
    assert datos["name"] == "Driver Test Registrado"
    assert datos["company"] is not None
    assert datos["company"]["id"] == "pae-logistics"


# ── Registro de Compañías y Registro Público de Usuarios ───────────────────────

async def test_registrar_y_listar_companias(cliente):
    """Prueba que se pueda crear una compañía y luego listarla."""
    import uuid
    nombre_compania = f"Test Company {uuid.uuid4().hex[:6]}"
    
    # Crear compañía
    res_crear = await cliente.post(
        "/auth/companies",
        json={"name": nombre_compania}
    )
    assert res_crear.status_code == 201
    datos_crear = res_crear.json()
    assert datos_crear["name"] == nombre_compania
    assert "id" in datos_crear

    # Listar compañías
    res_listar = await cliente.get("/auth/companies")
    assert res_listar.status_code == 200
    companias = res_listar.json()
    assert any(c["name"] == nombre_compania for c in companias)


async def test_registrar_usuario_con_id_compania(cliente):
    """Prueba que un usuario pueda registrarse asociándose a una compañía existente usando su ID."""
    import uuid
    nombre_compania = f"Company Test Public {uuid.uuid4().hex[:6]}"
    username_nuevo = f"user_test_public_{uuid.uuid4().hex[:6]}"

    # 1. Crear la compañía
    res_comp = await cliente.post(
        "/auth/companies",
        json={"name": nombre_compania}
    )
    assert res_comp.status_code == 201
    compania_id = res_comp.json()["id"]

    # 2. Registrar el usuario sin JWT pero con company_id
    res_reg = await cliente.post(
        "/auth/register",
        json={
            "username": username_nuevo,
            "password": "user123password",
            "role": "central",
            "name": "Usuario Test Público",
            "company_id": compania_id
        }
    )
    assert res_reg.status_code == 201
    datos_reg = res_reg.json()
    assert datos_reg["username"] == username_nuevo
    assert datos_reg["company"] is not None
    assert datos_reg["company"]["id"] == compania_id
    assert datos_reg["company"]["name"] == nombre_compania
