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
            MATCH (c:Company {id: 'pae-logistics'})
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
            CREATE (u)-[:BELONGS_TO]->(c)
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
                MATCH (u:User {id: $driver_id}), (c:Company {id: 'pae-logistics'})
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
                CREATE (o)-[:BELONGS_TO]->(c)
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
            assert 0.49 <= kpis["average_load_packages"] <= 0.51
            assert kpis["load_weighted_distance"] > 0
            assert "average_insertion_detour_minutes" in kpis
            assert "packages_per_km" in kpis
            assert "insertion_acceptance_rate" in kpis
            assert kpis["meets_load_efficiency_target"] is False

            list_response = client.get("/drivers/", headers=_headers(token_central))
            assert list_response.status_code == 200
            driver = next(d for d in list_response.json() if d["id"] == driver_id)
            assert driver["load_efficiency_ratio"] == kpis["load_efficiency_ratio"]
            assert driver["average_load_packages"] == kpis["average_load_packages"]
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


def test_pedido_completado_se_atribuye_solo_al_repartidor_asignado(
    aplicacion,
    base_de_datos_prueba,
):
    suffix = uuid.uuid4().hex[:8]
    maria_id = f"test-maria-kpi-{suffix}"
    maria_username = f"maria_kpi_{suffix}"
    other_id = f"test-other-kpi-{suffix}"
    other_username = f"other_kpi_{suffix}"
    order_id = f"test-completed-owner-{suffix}"

    with obtener_conexion() as session:
        session.run(
            """
            MATCH (c:Company {id: 'pae-logistics'})
            CREATE (maria:User {
                id: $maria_id,
                username: $maria_username,
                password_hash: $password_hash,
                role: 'repartidor',
                name: 'Maria KPI',
                is_available: true,
                lat: 41.6260,
                lng: 2.6900,
                created_at: datetime()
            })
            CREATE (other:User {
                id: $other_id,
                username: $other_username,
                password_hash: $password_hash,
                role: 'repartidor',
                name: 'Other KPI',
                is_available: true,
                lat: 41.6140,
                lng: 2.6580,
                created_at: datetime()
            })
            CREATE (maria)-[:BELONGS_TO]->(c)
            CREATE (other)-[:BELONGS_TO]->(c)
            CREATE (maria)-[:HAS_ROUTE]->(:Route {
                id: randomUUID(),
                order_ids: [$order_id],
                completed_order_ids: [],
                status: 'active',
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (other)-[:HAS_ROUTE]->(:Route {
                id: randomUUID(),
                order_ids: [],
                completed_order_ids: [],
                status: 'active',
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (order:Order {
                id: $order_id,
                type: 'delivery',
                name: 'Pedido Maria KPI',
                address: 'Calle KPI Maria',
                lat: 41.6250,
                lng: 2.6890,
                status: 'in_progress',
                estimated_extra_minutes: 3.0,
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (order)-[:BELONGS_TO]->(c)
            CREATE (maria)-[:ASSIGNED_TO]->(order)
            """,
            {
                "maria_id": maria_id,
                "maria_username": maria_username,
                "other_id": other_id,
                "other_username": other_username,
                "password_hash": contexto_contrasena.hash("driver123"),
                "order_id": order_id,
            },
        )

    try:
        with TestClient(aplicacion) as client:
            token_maria = _login(client, maria_username, "driver123")
            token_other = _login(client, other_username, "driver123")

            response = client.patch(
                f"/orders/{order_id}/status",
                json={"status": "completed"},
                headers=_headers(token_maria),
            )
            assert response.status_code == 200

            maria_kpis = client.get(
                "/drivers/me/kpis",
                headers=_headers(token_maria),
            ).json()
            other_kpis = client.get(
                "/drivers/me/kpis",
                headers=_headers(token_other),
            ).json()

            assert maria_kpis["driver_id"] == maria_id
            assert maria_kpis["completed_order_count"] == 1
            assert other_kpis["driver_id"] == other_id
            assert other_kpis["completed_order_count"] == 0

            with obtener_conexion() as session:
                record = session.run(
                    """
                    MATCH (order:Order {id: $order_id})
                    OPTIONAL MATCH (maria:User {id: $maria_id})-[:HAS_ROUTE]->(r:Route {status: 'active'})
                    RETURN order.completed_by_driver_id AS completed_by_driver_id,
                           coalesce(r.completed_order_ids, []) AS completed_order_ids
                    """,
                    {"order_id": order_id, "maria_id": maria_id},
                ).single()
                assert record["completed_by_driver_id"] == maria_id
                assert order_id in record["completed_order_ids"]
    finally:
        with obtener_conexion() as session:
            session.run(
                """
                MATCH (u:User)
                WHERE u.id IN [$maria_id, $other_id]
                OPTIONAL MATCH (u)-[:HAS_ROUTE]->(route:Route)
                OPTIONAL MATCH (order:Order {id: $order_id})
                OPTIONAL MATCH (order)-[:LOGGED_EVENT]->(event:AuditEvent)
                DETACH DELETE u, route, order, event
                """,
                {
                    "maria_id": maria_id,
                    "other_id": other_id,
                    "order_id": order_id,
                },
            )
