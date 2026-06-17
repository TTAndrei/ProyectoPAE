import uuid
from fastapi.testclient import TestClient

from app.database import contexto_contrasena, obtener_conexion


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_analytics_and_route_history(aplicacion, base_de_datos_prueba):
    suffix = uuid.uuid4().hex[:8]
    driver_id = f"test-driver-analiticas-{suffix}"
    username = f"driver_analiticas_{suffix}"
    order_id = f"test-order-analiticas-{suffix}"

    # Setup database with driver, active route, and order linked to company
    with obtener_conexion() as session:
        session.run(
            """
            MATCH (c:Company {id: 'pae-logistics'})
            CREATE (u:User {
                id: $driver_id,
                username: $username,
                password_hash: $password_hash,
                role: 'repartidor',
                name: 'Analytics Driver',
                is_available: true,
                lat: 41.6260,
                lng: 2.6900,
                created_at: datetime()
            })
            CREATE (u)-[:BELONGS_TO]->(c)
            CREATE (u)-[:HAS_ROUTE]->(r:Route {
                id: randomUUID(),
                order_ids: [$order_id],
                completed_order_ids: [],
                status: 'active',
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (o:Order {
                id: $order_id,
                type: 'delivery',
                name: 'Pedido Analiticas',
                address: 'Calle Analiticas',
                lat: 41.6250,
                lng: 2.6890,
                status: 'assigned',
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (o)-[:BELONGS_TO]->(c)
            CREATE (u)-[:ASSIGNED_TO]->(o)
            """,
            {
                "driver_id": driver_id,
                "username": username,
                "password_hash": contexto_contrasena.hash("driver123"),
                "order_id": order_id,
            },
        )

    try:
        with TestClient(aplicacion) as client:
            token_central = _login(client, "central", "central123")
            token_driver = _login(client, username, "driver123")

            # 1. Start Jornada (Workday) for the driver
            start_resp = client.post("/drivers/me/jornada/start", headers=_headers(token_driver))
            assert start_resp.status_code == 201

            # 2. Driver accepts the order (transitions to in_progress)
            respond_resp = client.post(
                f"/orders/{order_id}/respond",
                json={"accepted": True},
                headers=_headers(token_driver),
            )
            assert respond_resp.status_code == 200

            # 3. Driver marks the order as completed
            status_resp = client.patch(
                f"/orders/{order_id}/status",
                json={"status": "completed"},
                headers=_headers(token_driver),
            )
            assert status_resp.status_code == 200

            # Verify that completed_order_ids contains the order_id
            with obtener_conexion() as session:
                record = session.run(
                    """
                    MATCH (u:User {id: $did})-[:HAS_ROUTE]->(r:Route {status: 'active'})
                    RETURN r.completed_order_ids AS completed_ids
                    """,
                    {"did": driver_id},
                ).single()
                assert record is not None
                assert order_id in record["completed_ids"]

            # 4. Driver closes Jornada (this archives the active route and opens a new active one)
            end_resp = client.post("/drivers/me/jornada/end", headers=_headers(token_driver))
            assert end_resp.status_code == 200

            # Verify route is now completed and linked to Jornada
            with obtener_conexion() as session:
                jornada_record = session.run(
                    """
                    MATCH (u:User {id: $did})-[:HAS_JORNADA]->(j:Jornada {status: 'closed'})-[:HAD_ROUTE]->(r:Route {status: 'completed'})
                    RETURN count(r) AS completed_routes_count
                    """,
                    {"did": driver_id},
                ).single()
                assert jornada_record["completed_routes_count"] == 1

                # Verify a new active route exists for the user
                active_record = session.run(
                    """
                    MATCH (u:User {id: $did})-[:HAS_ROUTE]->(r:Route {status: 'active'})
                    RETURN count(r) AS active_routes_count
                    """,
                    {"did": driver_id},
                ).single()
                assert active_record["active_routes_count"] == 1

            # 5. Check Audit Logs via API
            audit_resp = client.get(
                f"/analytics/audit-logs/{order_id}",
                headers=_headers(token_central),
            )
            assert audit_resp.status_code == 200
            audit_data = audit_resp.json()
            # We expect to see events (assign, accept, start_delivery, complete)
            actions = [item["action"] for item in audit_data]
            assert "accept" in actions or "start_delivery" in actions or "complete" in actions

            # 6. Check Fleet Summary Endpoint
            summary_resp = client.get(
                "/analytics/fleet-summary",
                headers=_headers(token_central),
            )
            assert summary_resp.status_code == 200
            summary_data = summary_resp.json()
            assert "total_distance_km" in summary_data
            assert "average_load_efficiency_percent" in summary_data
            assert "average_load_packages" in summary_data
            assert "average_insertion_detour_minutes" in summary_data
            assert "packages_per_km" in summary_data
            assert "insertion_acceptance_rate" in summary_data

            # 7. Check Driver Performance Ranking Endpoint
            perf_resp = client.get(
                "/analytics/driver-performance",
                headers=_headers(token_central),
            )
            assert perf_resp.status_code == 200
            perf_data = perf_resp.json()
            # Find our driver in the performance ranking list
            driver_perf = next((d for d in perf_data if d["driver_id"] == driver_id), None)
            assert driver_perf is not None
            assert driver_perf["completed_order_count"] >= 1
            assert "average_load_packages" in driver_perf
            assert "average_insertion_detour_minutes" in driver_perf
            assert "packages_per_km" in driver_perf
            assert "insertion_acceptance_rate" in driver_perf

            # 8. Check Routes History Endpoint
            history_resp = client.get(
                "/analytics/routes-history",
                headers=_headers(token_central),
            )
            assert history_resp.status_code == 200
            history_data = history_resp.json()
            # Ensure the completed route is listed
            driver_history = [r for r in history_data if r["driver_id"] == driver_id]
            assert len(driver_history) >= 1
            assert driver_history[0]["status"] == "completed"
            assert order_id in driver_history[0]["completed_order_ids"]

    finally:
        # Cleanup test driver and associated nodes
        with obtener_conexion() as session:
            session.run(
                """
                MATCH (u:User {id: $driver_id})
                OPTIONAL MATCH (u)-[:HAS_JORNADA]->(j:Jornada)
                OPTIONAL MATCH (j)-[:HAD_ROUTE]->(r1:Route)
                OPTIONAL MATCH (u)-[:HAS_ROUTE]->(r2:Route)
                OPTIONAL MATCH (o:Order {id: $order_id})
                OPTIONAL MATCH (o)-[:LOGGED_EVENT]->(ae:AuditEvent)
                DETACH DELETE u, j, r1, r2, o, ae
                """,
                {"driver_id": driver_id, "order_id": order_id},
            )
