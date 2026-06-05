import uuid

from fastapi.testclient import TestClient

from app.database import obtener_conexion


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _ensure_driver_ready(session, driver_id: str) -> None:
    session.run(
        """
        MATCH (u:User {id: $id})
        SET u.lat = coalesce(u.lat, 41.6260),
            u.lng = coalesce(u.lng, 2.6900),
            u.is_available = true,
            u.location_updated_at = datetime()
        WITH u
        OPTIONAL MATCH (u)-[:HAS_ROUTE]->(r:Route {status: 'active'})
        WITH u, count(r) AS active_routes
        WHERE active_routes = 0
        CREATE (u)-[:HAS_ROUTE]->(:Route {
            id: randomUUID(),
            order_ids: [],
            status: 'active',
            created_at: datetime(),
            updated_at: datetime()
        })
        """,
        {"id": driver_id},
    )


def _create_order(session, order_id: str, driver_id: str | None = None) -> None:
    session.run(
        "MATCH (o:Order {id: $id}) DETACH DELETE o",
        {"id": order_id},
    )
    session.run(
        """
        CREATE (o:Order {
            id: $id,
            type: 'pickup',
            name: 'Pedido test',
            address: 'Calle Test 1',
            lat: 41.6262,
            lng: 2.6908,
            status: $status,
            created_at: datetime(),
            updated_at: datetime()
        })
        """,
        {"id": order_id, "status": "assigned" if driver_id else "pending"},
    )
    if driver_id:
        session.run(
            """
            MATCH (u:User {id: $driver_id}), (o:Order {id: $order_id})
            MERGE (u)-[:ASSIGNED_TO]->(o)
            SET o.estimated_extra_minutes = 0.0
            """,
            {"driver_id": driver_id, "order_id": order_id},
        )


def _assigned_driver_ids(session, order_id: str) -> list[str]:
    result = session.run(
        """
        MATCH (u:User)-[:ASSIGNED_TO]->(:Order {id: $id})
        RETURN u.id AS id
        ORDER BY id
        """,
        {"id": order_id},
    )
    return [record["id"] for record in result]


def _route_order_ids(session, driver_id: str) -> list[str]:
    record = session.run(
        """
        MATCH (:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'})
        RETURN r.order_ids AS order_ids
        """,
        {"id": driver_id},
    ).single()
    return list(record["order_ids"] or []) if record else []


def test_reasignar_pedido_elimina_asignacion_anterior_y_recalcula_rutas(
    aplicacion,
    base_de_datos_prueba,
):
    order_id = f"test-reassign-{uuid.uuid4()}"
    with obtener_conexion() as session:
        _ensure_driver_ready(session, "driver-1")
        _ensure_driver_ready(session, "driver-2")
        _create_order(session, order_id, "driver-1")

    with TestClient(aplicacion) as client:
        token_central = _login(client, "central", "central123")
        response = client.post(
            f"/orders/{order_id}/assign",
            json={"driver_id": "driver-2"},
            headers=_headers(token_central),
        )

    assert response.status_code == 200
    assert response.json()["order"]["assigned_driver_id"] == "driver-2"

    with obtener_conexion() as session:
        assert _assigned_driver_ids(session, order_id) == ["driver-2"]
        assert order_id not in _route_order_ids(session, "driver-1")
        assert order_id in _route_order_ids(session, "driver-2")
        session.run("MATCH (o:Order {id: $id}) DETACH DELETE o", {"id": order_id})


def test_rechazo_rest_reasigna_al_siguiente_y_mantiene_unica_asignacion(
    aplicacion,
    base_de_datos_prueba,
):
    order_id = f"test-rest-reject-{uuid.uuid4()}"
    with obtener_conexion() as session:
        _ensure_driver_ready(session, "driver-1")
        _ensure_driver_ready(session, "driver-2")
        _create_order(session, order_id, "driver-1")

    with TestClient(aplicacion) as client:
        token_driver = _login(client, "driver1", "driver123")
        response = client.post(
            f"/orders/{order_id}/respond",
            json={"accepted": False},
            headers=_headers(token_driver),
        )

    assert response.status_code == 200
    data = response.json()
    assert data["order"]["status"] in ("assigned", "pending")

    with obtener_conexion() as session:
        assigned = _assigned_driver_ids(session, order_id)
        assert len(assigned) <= 1
        assert "driver-1" not in assigned
        if assigned:
            assert assigned == ["driver-2"]
            assert order_id in _route_order_ids(session, "driver-2")
        assert order_id not in _route_order_ids(session, "driver-1")
        session.run("MATCH (o:Order {id: $id}) DETACH DELETE o", {"id": order_id})


def test_websocket_rechazo_usa_mismo_flujo_que_rest(aplicacion, base_de_datos_prueba):
    order_id = f"test-ws-reject-{uuid.uuid4()}"
    with obtener_conexion() as session:
        _ensure_driver_ready(session, "driver-1")
        _ensure_driver_ready(session, "driver-2")
        _create_order(session, order_id, "driver-1")

    with TestClient(aplicacion) as client:
        token_central = _login(client, "central", "central123")
        token_driver = _login(client, "driver1", "driver123")
        with client.websocket_connect(f"/ws?token={token_central}") as central_ws:
            with client.websocket_connect(f"/ws?token={token_driver}") as driver_ws:
                driver_ws.send_json(
                    {
                        "type": "driver:pickup:response",
                        "order_id": order_id,
                        "accepted": False,
                    }
                )
                first_message = central_ws.receive_json()
                assert first_message["type"] == "pickup:response"
                assert first_message["accepted"] is False

    with obtener_conexion() as session:
        assigned = _assigned_driver_ids(session, order_id)
        assert len(assigned) <= 1
        assert "driver-1" not in assigned
        assert order_id not in _route_order_ids(session, "driver-1")
        session.run("MATCH (o:Order {id: $id}) DETACH DELETE o", {"id": order_id})


def test_websocket_aceptacion_pasa_a_en_progreso(aplicacion, base_de_datos_prueba):
    order_id = f"test-ws-accept-{uuid.uuid4()}"
    with obtener_conexion() as session:
        _ensure_driver_ready(session, "driver-1")
        _create_order(session, order_id, "driver-1")

    with TestClient(aplicacion) as client:
        token_central = _login(client, "central", "central123")
        token_driver = _login(client, "driver1", "driver123")
        with client.websocket_connect(f"/ws?token={token_central}") as central_ws:
            with client.websocket_connect(f"/ws?token={token_driver}") as driver_ws:
                driver_ws.send_json(
                    {
                        "type": "driver:pickup:response",
                        "order_id": order_id,
                        "accepted": True,
                    }
                )
                message = central_ws.receive_json()
                assert message["type"] == "pickup:response"
                assert message["accepted"] is True

    with obtener_conexion() as session:
        record = session.run(
            "MATCH (o:Order {id: $id}) RETURN o.status AS status",
            {"id": order_id},
        ).single()
        assert record["status"] == "in_progress"
        assert _assigned_driver_ids(session, order_id) == ["driver-1"]
        assert order_id in _route_order_ids(session, "driver-1")
        session.run("MATCH (o:Order {id: $id}) DETACH DELETE o", {"id": order_id})
