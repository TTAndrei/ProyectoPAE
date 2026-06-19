from fastapi.testclient import TestClient

from app.database import obtener_conexion
from app.services.route20_simulation import SIMULATION_ID


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post("/auth/login", json={"username": username, "password": password})
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_route20_simulation_start_status_kpis_and_reset(aplicacion, base_de_datos_prueba):
    with TestClient(aplicacion) as client:
        token_central = _login(client, "central", "central123")

        reset_response = client.post(
            "/simulations/route-20/reset",
            headers=_headers(token_central),
        )
        assert reset_response.status_code == 200

        start_response = client.post(
            "/simulations/route-20/start",
            headers=_headers(token_central),
        )
        assert start_response.status_code == 200
        data = start_response.json()
        assert data["status"] == "running"
        assert data["total_stops"] == 20
        assert data["driver_id"] == "driver-demo"
        assert data["kpis"]["driver_id"] == "driver-demo"

        with obtener_conexion() as session:
            record = session.run(
                """
                MATCH (o:Order {simulation_id: $simulation_id})
                OPTIONAL MATCH (:User {id: 'driver-demo'})-[rel:ASSIGNED_TO]->(o)
                RETURN count(DISTINCT o) AS count,
                       count(rel) AS assigned
                """,
                {"simulation_id": SIMULATION_ID},
            ).single()
            assert record["count"] == 20
            assert record["assigned"] == 20

        status_response = client.get(
            "/simulations/route-20/status",
            headers=_headers(token_central),
        )
        assert status_response.status_code == 200
        assert status_response.json()["kpis"]["driver_id"] == "driver-demo"

        kpis_response = client.get(
            "/simulations/route-20/kpis",
            headers=_headers(token_central),
        )
        assert kpis_response.status_code == 200
        assert "load_efficiency_ratio" in kpis_response.json()

        reset_response = client.post(
            "/simulations/route-20/reset",
            headers=_headers(token_central),
        )
        assert reset_response.status_code == 200
        assert reset_response.json()["status"] == "idle"

        with obtener_conexion() as session:
            record = session.run(
                "MATCH (o:Order {simulation_id: $simulation_id}) RETURN count(o) AS count",
                {"simulation_id": SIMULATION_ID},
            ).single()
            assert record["count"] == 0


def test_route20_simulation_rejects_driver_role(aplicacion, base_de_datos_prueba):
    with TestClient(aplicacion) as client:
        token_driver = _login(client, "driver1", "driver123")
        response = client.get(
            "/simulations/route-20/status",
            headers=_headers(token_driver),
        )
        assert response.status_code == 403
