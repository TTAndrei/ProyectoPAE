import uuid

from fastapi.testclient import TestClient

from app.database import contexto_contrasena, obtener_conexion


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_ratio_eficiencia_carga_visible_para_central_y_repartidor(
    aplicacion,
    base_de_datos_prueba,
):
    suffix = uuid.uuid4().hex[:8]
    driver_id = f"test-driver-kpi-{suffix}"
    username = f"kpi_driver_{suffix}"
    delivery_id = f"test-kpi-delivery-{suffix}"
    pickup_id = f"test-kpi-pickup-{suffix}"

    with obtener_conexion() as session:
        session.run(
            """
            CREATE (u:User {
                id: $driver_id,
                username: $username,
                password_hash: $password_hash,
                role: 'repartidor',
                name: 'KPI Driver',
                is_available: true,
                lat: 0.0,
                lng: 0.0,
                created_at: datetime()
            })
            CREATE (u)-[:HAS_ROUTE]->(:Route {
                id: randomUUID(),
                order_ids: [$delivery_id, $pickup_id],
                status: 'active',
                created_at: datetime(),
                updated_at: datetime()
            })
            """,
            {
                "driver_id": driver_id,
                "username": username,
                "password_hash": contexto_contrasena.hash("driver123"),
                "delivery_id": delivery_id,
                "pickup_id": pickup_id,
            },
        )
        for order_id, order_type, lng in (
            (delivery_id, "delivery", 0.01),
            (pickup_id, "pickup", 0.02),
        ):
            session.run(
                """
                MATCH (u:User {id: $driver_id})
                CREATE (o:Order {
                    id: $order_id,
                    type: $order_type,
                    name: 'Pedido KPI',
                    address: 'Calle KPI',
                    lat: 0.0,
                    lng: $lng,
                    status: 'in_progress',
                    created_at: datetime(),
                    updated_at: datetime()
                })
                CREATE (u)-[:ASSIGNED_TO]->(o)
                """,
                {
                    "driver_id": driver_id,
                    "order_id": order_id,
                    "order_type": order_type,
                    "lng": lng,
                },
            )

    try:
        with TestClient(aplicacion) as client:
            token_central = _login(client, "central", "central123")
            token_driver = _login(client, username, "driver123")

            own_response = client.get("/drivers/me/kpis", headers=_headers(token_driver))
            assert own_response.status_code == 200
            kpis = own_response.json()
            assert kpis["driver_id"] == driver_id
            assert 0.49 <= kpis["load_efficiency_ratio"] <= 0.51
            assert kpis["loaded_distance_km"] > 0
            assert kpis["total_distance_km"] > kpis["loaded_distance_km"]
            assert kpis["meets_load_efficiency_target"] is False

            list_response = client.get("/drivers/", headers=_headers(token_central))
            assert list_response.status_code == 200
            driver = next(d for d in list_response.json() if d["id"] == driver_id)
            assert driver["load_efficiency_ratio"] == kpis["load_efficiency_ratio"]
            assert driver["active_order_count"] == 2
    finally:
        with obtener_conexion() as session:
            session.run(
                """
                MATCH (u:User {id: $driver_id})
                OPTIONAL MATCH (u)-[:ASSIGNED_TO]->(o:Order)
                WHERE o.id IN [$delivery_id, $pickup_id]
                DETACH DELETE u, o
                """,
                {
                    "driver_id": driver_id,
                    "delivery_id": delivery_id,
                    "pickup_id": pickup_id,
                },
            )
