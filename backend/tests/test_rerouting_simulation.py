import asyncio

from fastapi.testclient import TestClient

from app.database import obtener_conexion
from app.services import rerouting_simulation as sim


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_rerouting_simulation_start_inject_compare_and_reset(aplicacion, base_de_datos_prueba):
    with TestClient(aplicacion) as client:
        token_central = _login(client, "central", "central123")

        reset_response = client.post(
            "/simulations/rerouting/reset",
            headers=_headers(token_central),
        )
        assert reset_response.status_code == 200

        start_response = client.post(
            "/simulations/rerouting/start",
            headers=_headers(token_central),
        )
        assert start_response.status_code == 200
        data = start_response.json()
        assert data["status"] == "running"
        assert data["total_stops"] == 3
        assert data["driver_id"] == "driver-demo"
        assert data["comparison"]["fifo_distance_km"] > data["comparison"]["dynamic_distance_km"]

        with obtener_conexion() as session:
            record = session.run(
                """
                MATCH (o:Order {simulation_id: $simulation_id})
                OPTIONAL MATCH (:User {id: 'driver-demo'})-[rel:ASSIGNED_TO]->(o)
                WITH count(DISTINCT o) AS count, count(rel) AS assigned
                MATCH (:User {id: 'driver-demo'})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
                RETURN count, assigned, r.order_ids AS order_ids
                """,
                {"simulation_id": sim.SIMULATION_ID},
            ).single()
            assert record["count"] == 3
            assert record["assigned"] == 3
            previous_order_ids = list(record["order_ids"])

        asyncio.run(sim._inject_stop(1))

        with obtener_conexion() as session:
            record = session.run(
                """
                MATCH (o:Order {simulation_id: $simulation_id})
                OPTIONAL MATCH (:User {id: 'driver-demo'})-[rel:ASSIGNED_TO]->(o)
                WITH count(DISTINCT o) AS count, count(rel) AS assigned
                MATCH (:User {id: 'driver-demo'})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
                RETURN count, assigned, r.order_ids AS order_ids
                """,
                {"simulation_id": sim.SIMULATION_ID},
            ).single()
            assert record["count"] == 4
            assert record["assigned"] == 4
            assert list(record["order_ids"]) != previous_order_ids

        status_response = client.get(
            "/simulations/rerouting/status",
            headers=_headers(token_central),
        )
        assert status_response.status_code == 200
        status = status_response.json()
        assert status["events"][0]["type"] == "reroute"
        assert status["comparison"]["fifo_distance_km"] >= status["comparison"]["dynamic_distance_km"]

        reset_response = client.post(
            "/simulations/rerouting/reset",
            headers=_headers(token_central),
        )
        assert reset_response.status_code == 200
        assert reset_response.json()["status"] == "idle"


def test_rerouting_simulation_rejects_driver_role(aplicacion, base_de_datos_prueba):
    with TestClient(aplicacion) as client:
        token_driver = _login(client, "driver1", "driver123")
        response = client.get(
            "/simulations/rerouting/status",
            headers=_headers(token_driver),
        )
        assert response.status_code == 403


def test_rerouting_complete_order_records_traveled_km(base_de_datos_prueba):
    with obtener_conexion() as session:
        sim._reset_simulation_data(session)
        sim._restore_paused_routes(session)
        sim._ensure_driver_ready(session)
        sim._create_run(session, "running")
        sim._create_orders_and_route(session)

        record = session.run(
            """
            MATCH (:User {id: $driver_id})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
            RETURN r.order_ids[0] AS first_order_id
            """,
            {"driver_id": sim.SIMULATION_DRIVER_ID, "simulation_id": sim.SIMULATION_ID},
        ).single()
        order_id = record["first_order_id"]
        stop = sim._get_order(session, order_id)
        current_position = sim._get_driver_position(session)

        sim._complete_order(session, order_id, stop, current_position, 1.23)

        totals = session.run(
            """
            MATCH (:User {id: $driver_id})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
            MATCH (run:SimulationRun {id: $simulation_id})
            RETURN r.simulation_traveled_km AS route_km,
                   run.dynamic_traveled_km AS run_km,
                   r.completed_order_ids AS completed_order_ids
            """,
            {"driver_id": sim.SIMULATION_DRIVER_ID, "simulation_id": sim.SIMULATION_ID},
        ).single()

        assert totals["route_km"] == 1.23
        assert totals["run_km"] == 1.23
        assert order_id in totals["completed_order_ids"]
