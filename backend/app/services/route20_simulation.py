from __future__ import annotations

import asyncio
import json
import logging
import math
from typing import Any

from fastapi import HTTPException

from app.database import (
    DEMO_DRIVER_ID,
    DEMO_DRIVER_FALLBACK_USERNAME,
    DEMO_DRIVER_PASSWORD,
    DEMO_DRIVER_USERNAME,
    contexto_contrasena,
    obtener_conexion,
)
from app.services.driver_kpis import calcular_kpis_repartidor
from app.services.order_workflow import (
    persistir_metricas_ruta,
    plan_ruta_repartidor,
    registrar_evento_auditoria,
)
from app.ws_manager import gestor

logger = logging.getLogger(__name__)

SIMULATION_ID = "route-20-demo"
SIMULATION_DRIVER_ID = DEMO_DRIVER_ID
SIMULATION_TOTAL_STOPS = 20
SECONDS_PER_STOP = 2.0
UPDATES_PER_STOP = 16

ROUTE20_STOPS: list[dict[str, Any]] = [
    {"id": "sim-route20-01", "name": "Recogida Pineda Centre", "address": "Carrer Major 12, Pineda de Mar", "lat": 41.6271, "lng": 2.6882},
    {"id": "sim-route20-02", "name": "Recogida Poblenou", "address": "Avinguda Hispanitat 4, Pineda de Mar", "lat": 41.6228, "lng": 2.6819},
    {"id": "sim-route20-03", "name": "Recogida Riera", "address": "Carrer Riera 22, Pineda de Mar", "lat": 41.6254, "lng": 2.6909},
    {"id": "sim-route20-04", "name": "Recogida Passeig Maritim", "address": "Passeig Maritim 38, Pineda de Mar", "lat": 41.6222, "lng": 2.6934},
    {"id": "sim-route20-05", "name": "Recogida Santa Susanna Est", "address": "Carrer Marina 10, Santa Susanna", "lat": 41.6361, "lng": 2.7161},
    {"id": "sim-route20-06", "name": "Recogida Santa Susanna Nord", "address": "Avinguda del Mar 15, Santa Susanna", "lat": 41.6402, "lng": 2.7199},
    {"id": "sim-route20-07", "name": "Recogida Malgrat Parc", "address": "Carrer Girona 24, Malgrat de Mar", "lat": 41.6455, "lng": 2.7328},
    {"id": "sim-route20-08", "name": "Recogida Malgrat Centre", "address": "Carrer del Carme 9, Malgrat de Mar", "lat": 41.6469, "lng": 2.7408},
    {"id": "sim-route20-09", "name": "Recogida Malgrat Mar", "address": "Passeig Maritim 61, Malgrat de Mar", "lat": 41.6413, "lng": 2.7452},
    {"id": "sim-route20-10", "name": "Recogida Palafolls", "address": "Carrer Major 6, Palafolls", "lat": 41.6684, "lng": 2.7496},
    {"id": "sim-route20-11", "name": "Recogida Calella Oest", "address": "Carrer Sant Jaume 21, Calella", "lat": 41.6174, "lng": 2.6512},
    {"id": "sim-route20-12", "name": "Recogida Calella Centre", "address": "Carrer Esglesia 84, Calella", "lat": 41.6139, "lng": 2.6578},
    {"id": "sim-route20-13", "name": "Recogida Calella Mercat", "address": "Plaça del Mercat 2, Calella", "lat": 41.6158, "lng": 2.6617},
    {"id": "sim-route20-14", "name": "Recogida Calella Mar", "address": "Passeig Manuel Puigvert 18, Calella", "lat": 41.6104, "lng": 2.6601},
    {"id": "sim-route20-15", "name": "Recogida Sant Pol", "address": "Carrer Nou 11, Sant Pol de Mar", "lat": 41.6019, "lng": 2.6231},
    {"id": "sim-route20-16", "name": "Recogida Canet", "address": "Riera Buscarons 32, Canet de Mar", "lat": 41.5909, "lng": 2.5814},
    {"id": "sim-route20-17", "name": "Recogida Arenys", "address": "Riera del Bisbe Pol 45, Arenys de Mar", "lat": 41.5812, "lng": 2.5494},
    {"id": "sim-route20-18", "name": "Recogida Sant Cebria", "address": "Avinguda Maresme 5, Sant Cebria de Vallalta", "lat": 41.6208, "lng": 2.6018},
    {"id": "sim-route20-19", "name": "Recogida Tordera", "address": "Carrer Sant Ramon 19, Tordera", "lat": 41.6991, "lng": 2.7192},
    {"id": "sim-route20-20", "name": "Recogida Final Pineda", "address": "Avinguda Montserrat 31, Pineda de Mar", "lat": 41.6296, "lng": 2.6841},
]

_task: asyncio.Task | None = None


def _empty_kpis() -> dict[str, Any]:
    return {
        "driver_id": SIMULATION_DRIVER_ID,
        "load_efficiency_ratio": 0.0,
        "load_efficiency_percent": 0.0,
        "loaded_distance_km": 0.0,
        "total_distance_km": 0.0,
        "active_order_count": 0,
        "pending_confirmation_count": 0,
        "completed_order_count": 0,
        "average_load_packages": 0.0,
        "load_weighted_distance": 0.0,
        "average_insertion_detour_minutes": 0.0,
        "packages_per_km": 0.0,
        "insertion_acceptance_rate": 0.0,
        "accepted_insertion_count": 0,
        "rejected_insertion_count": 0,
        "target_load_efficiency_ratio": 0.75,
        "meets_load_efficiency_target": False,
        "measurement_note": "",
    }


def _order_projection(record: dict[str, Any] | None) -> dict[str, Any] | None:
    if not record:
        return None
    order = dict(record)
    order["assigned_driver_id"] = SIMULATION_DRIVER_ID
    order.setdefault("backhauling_candidates", [])
    return order


def _get_order(session, order_id: str) -> dict[str, Any] | None:
    record = session.run(
        """
        MATCH (o:Order {id: $id})
        RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o
        """,
        {"id": order_id},
    ).single()
    return _order_projection(record["o"]) if record else None


def _get_next_active_order(session) -> dict[str, Any] | None:
    record = session.run(
        """
        MATCH (:User {id: $driver_id})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
        WITH coalesce(r.order_ids, []) AS route_order_ids
        UNWIND route_order_ids AS order_id
        MATCH (o:Order {id: order_id, simulation_id: $simulation_id})
        WHERE o.status IN ['assigned', 'in_progress']
        RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o
        LIMIT 1
        """,
        {
            "driver_id": SIMULATION_DRIVER_ID,
            "simulation_id": SIMULATION_ID,
        },
    ).single()
    return _order_projection(record["o"]) if record else None


def _get_driver_position(session) -> dict[str, float]:
    record = session.run(
        """
        MATCH (u:User {id: $driver_id})
        RETURN u.lat AS lat, u.lng AS lng
        """,
        {"driver_id": SIMULATION_DRIVER_ID},
    ).single()
    if not record or record["lat"] is None or record["lng"] is None:
        first = ROUTE20_STOPS[0]
        return {"lat": float(first["lat"]), "lng": float(first["lng"])}
    return {"lat": float(record["lat"]), "lng": float(record["lng"])}


def _ensure_driver_ready(session) -> None:
    session.run(
        """
        OPTIONAL MATCH (existing_username:User {username: $username})
        WITH existing_username
        MERGE (u:User {id: $id})
        ON CREATE SET
            u.username = CASE
                WHEN existing_username IS NULL OR existing_username.id = $id THEN $username
                ELSE $fallback_username
            END,
            u.password_hash = $password_hash,
            u.role = 'repartidor',
            u.name = 'Repartidor Demo',
            u.is_available = false,
            u.created_at = datetime()
        SET u.role = 'repartidor',
            u.username = coalesce(u.username, CASE
                WHEN existing_username IS NULL OR existing_username.id = $id THEN $username
                ELSE $fallback_username
            END),
            u.password_hash = coalesce(u.password_hash, $password_hash),
            u.name = coalesce(u.name, 'Repartidor Demo')
        WITH u
        MATCH (c:Company {id: 'pae-logistics'})
        MERGE (u)-[:BELONGS_TO]->(c)
        """,
        {
            "id": SIMULATION_DRIVER_ID,
            "username": DEMO_DRIVER_USERNAME,
            "fallback_username": DEMO_DRIVER_FALLBACK_USERNAME,
            "password_hash": contexto_contrasena.hash(DEMO_DRIVER_PASSWORD),
        },
    )

    start = ROUTE20_STOPS[0]
    session.run(
        """
        MATCH (u:User {id: $id})
        SET u.is_available = true,
            u.lat = $lat,
            u.lng = $lng,
            u.heading = 0.0,
            u.location_updated_at = datetime()
        WITH u
        OPTIONAL MATCH (u)-[:HAS_JORNADA]->(active:Jornada {status: 'active'})
        WITH u, count(active) AS active_shifts
        FOREACH (_ IN CASE WHEN active_shifts = 0 THEN [1] ELSE [] END |
            CREATE (u)-[:HAS_JORNADA]->(:Jornada {
                id: randomUUID(),
                status: 'active',
                start_time: datetime(),
                simulation_id: $simulation_id
            })
        )
        """,
        {
            "id": SIMULATION_DRIVER_ID,
            "lat": start["lat"],
            "lng": start["lng"],
            "simulation_id": SIMULATION_ID,
        },
    )


def _reset_simulation_data(session) -> None:
    session.run(
        """
        MATCH (o:Order {simulation_id: $simulation_id})
        OPTIONAL MATCH (o)-[:LOGGED_EVENT]->(event:AuditEvent)
        WITH o, collect(event) AS events
        FOREACH (event IN events | DETACH DELETE event)
        DETACH DELETE o
        """,
        {"simulation_id": SIMULATION_ID},
    )
    session.run(
        """
        MATCH (r:Route {simulation_id: $simulation_id})
        DETACH DELETE r
        """,
        {"simulation_id": SIMULATION_ID},
    )
    session.run(
        """
        MATCH (j:Jornada {simulation_id: $simulation_id})
        DETACH DELETE j
        """,
        {"simulation_id": SIMULATION_ID},
    )


def _create_run(session, status: str) -> None:
    session.run(
        """
        MERGE (run:SimulationRun {id: $simulation_id})
        SET run.status = $status,
            run.current_index = 0,
            run.driver_id = $driver_id,
            run.started_at = datetime(),
            run.finished_at = null,
            run.error = null,
            run.total_stops = $total_stops
        """,
        {
            "simulation_id": SIMULATION_ID,
            "status": status,
            "driver_id": SIMULATION_DRIVER_ID,
            "total_stops": SIMULATION_TOTAL_STOPS,
        },
    )


def _create_orders_and_route(session) -> None:
    order_ids = [stop["id"] for stop in ROUTE20_STOPS]
    session.run(
        """
        MATCH (u:User {id: $driver_id})
        OPTIONAL MATCH (u)-[:HAS_ROUTE]->(old:Route {status: 'active'})
        WHERE old.simulation_id IS NULL
        SET old.status = 'paused_for_simulation',
            old.paused_by_simulation = $simulation_id,
            old.updated_at = datetime()
        """,
        {"driver_id": SIMULATION_DRIVER_ID, "simulation_id": SIMULATION_ID},
    )
    session.run(
        """
        MATCH (u:User {id: $driver_id})-[:ASSIGNED_TO]->(o:Order)
        WHERE coalesce(o.simulation_id, '') <> $simulation_id
          AND o.status IN ['assigned', 'in_progress']
        SET o.previous_status_before_simulation = o.status,
            o.status = 'paused_for_simulation',
            o.paused_by_simulation = $simulation_id,
            o.updated_at = datetime()
        """,
        {"driver_id": SIMULATION_DRIVER_ID, "simulation_id": SIMULATION_ID},
    )
    session.run(
        """
        MATCH (u:User {id: $driver_id})
        CREATE (u)-[:HAS_ROUTE]->(:Route {
            id: $route_id,
            order_ids: $order_ids,
            completed_order_ids: [],
            simulation_traveled_km: 0.0,
            status: 'active',
            simulation_id: $simulation_id,
            created_at: datetime(),
            updated_at: datetime()
        })
        """,
        {
            "driver_id": SIMULATION_DRIVER_ID,
            "route_id": f"{SIMULATION_ID}-route",
            "order_ids": order_ids,
            "simulation_id": SIMULATION_ID,
        },
    )

    for index, stop in enumerate(ROUTE20_STOPS, start=1):
        session.run(
            """
            MATCH (u:User {id: $driver_id}), (c:Company {id: 'pae-logistics'})
            CREATE (o:Order {
                id: $id,
                type: 'pickup',
                name: $name,
                address: $address,
                lat: $lat,
                lng: $lng,
                status: 'in_progress',
                simulation_id: $simulation_id,
                simulation_index: $index,
                estimated_extra_minutes: 0.0,
                candidate_driver_ids: [$driver_id],
                current_candidate_idx: 0,
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (o)-[:BELONGS_TO]->(c)
            CREATE (u)-[:ASSIGNED_TO]->(o)
            """,
            {
                "driver_id": SIMULATION_DRIVER_ID,
                "id": stop["id"],
                "name": stop["name"],
                "address": stop["address"],
                "lat": stop["lat"],
                "lng": stop["lng"],
                "simulation_id": SIMULATION_ID,
                "index": index,
            },
        )
        registrar_evento_auditoria(
            session,
            stop["id"],
            "create",
            SIMULATION_DRIVER_ID,
            f"Pedido demo {SIMULATION_ID} creado",
        )
        registrar_evento_auditoria(
            session,
            stop["id"],
            "accept",
            SIMULATION_DRIVER_ID,
            "Aceptado automaticamente por simulacion",
        )
        registrar_evento_auditoria(
            session,
            stop["id"],
            "start_delivery",
            SIMULATION_DRIVER_ID,
            "Pedido demo en curso",
        )

    plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
    persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)


def _restore_paused_routes(session) -> None:
    session.run(
        """
        MATCH (r:Route {paused_by_simulation: $simulation_id})
        SET r.status = 'active',
            r.paused_by_simulation = null,
            r.updated_at = datetime()
        """,
        {"simulation_id": SIMULATION_ID},
    )
    session.run(
        """
        MATCH (o:Order {paused_by_simulation: $simulation_id})
        SET o.status = coalesce(o.previous_status_before_simulation, 'assigned'),
            o.updated_at = datetime()
        REMOVE o.paused_by_simulation,
               o.previous_status_before_simulation
        """,
        {"simulation_id": SIMULATION_ID},
    )


async def start_route20_simulation() -> dict[str, Any]:
    global _task

    with obtener_conexion() as session:
        run = session.run(
            "MATCH (run:SimulationRun {id: $id}) RETURN run.status AS status",
            {"id": SIMULATION_ID},
        ).single()
        if run and run["status"] == "running":
            raise HTTPException(status_code=409, detail="La simulacion ya esta en ejecucion")

        _reset_simulation_data(session)
        _restore_paused_routes(session)
        _ensure_driver_ready(session)
        _create_run(session, "running")
        _create_orders_and_route(session)

    if _task is None or _task.done():
        _task = asyncio.create_task(_run_route20_job())

    await gestor.difundir_a_central(
        {"type": "simulation:tick", "simulation_id": SIMULATION_ID, "status": "running", "current_index": 0}
    )
    return get_route20_status()


def reset_route20_simulation() -> dict[str, Any]:
    global _task
    if _task is not None and not _task.done():
        _task.cancel()

    with obtener_conexion() as session:
        _reset_simulation_data(session)
        _restore_paused_routes(session)
        session.run(
            """
            MERGE (run:SimulationRun {id: $simulation_id})
            SET run.status = 'idle',
                run.current_index = 0,
                run.driver_id = $driver_id,
                run.started_at = null,
                run.finished_at = null,
                run.error = null,
                run.total_stops = $total_stops
            """,
            {
                "simulation_id": SIMULATION_ID,
                "driver_id": SIMULATION_DRIVER_ID,
                "total_stops": SIMULATION_TOTAL_STOPS,
            },
        )
        plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
        persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)

    return get_route20_status()


def get_route20_kpis() -> dict[str, Any]:
    with obtener_conexion() as session:
        return calcular_kpis_repartidor(session, SIMULATION_DRIVER_ID) or _empty_kpis()


def get_route20_status() -> dict[str, Any]:
    with obtener_conexion() as session:
        record = session.run(
            """
            MATCH (run:SimulationRun {id: $id})
            RETURN run.status AS status,
                   coalesce(run.current_index, 0) AS current_index,
                   coalesce(run.total_stops, $total_stops) AS total_stops,
                   coalesce(run.driver_id, $driver_id) AS driver_id,
                   toString(run.started_at) AS started_at,
                   toString(run.finished_at) AS finished_at,
                   run.error AS error
            """,
            {
                "id": SIMULATION_ID,
                "driver_id": SIMULATION_DRIVER_ID,
                "total_stops": SIMULATION_TOTAL_STOPS,
            },
        ).single()
        if not record:
            session.run(
                """
                MERGE (run:SimulationRun {id: $id})
                SET run.status = 'idle',
                    run.current_index = 0,
                    run.driver_id = $driver_id,
                    run.total_stops = $total_stops
                """,
                {
                    "id": SIMULATION_ID,
                    "driver_id": SIMULATION_DRIVER_ID,
                    "total_stops": SIMULATION_TOTAL_STOPS,
                },
            )
            record = {
                "status": "idle",
                "current_index": 0,
                "total_stops": SIMULATION_TOTAL_STOPS,
                "driver_id": SIMULATION_DRIVER_ID,
                "started_at": None,
                "finished_at": None,
                "error": None,
            }
        else:
            record = dict(record)

        current_index = int(record["current_index"] or 0)
        current_stop = _get_next_active_order(session)
        if current_stop is None:
            if 0 <= current_index < SIMULATION_TOTAL_STOPS:
                current_stop = _get_order(session, ROUTE20_STOPS[current_index]["id"])
            elif SIMULATION_TOTAL_STOPS > 0:
                current_stop = _get_order(session, ROUTE20_STOPS[-1]["id"])

        kpis = calcular_kpis_repartidor(session, SIMULATION_DRIVER_ID) or _empty_kpis()

    return {
        "id": SIMULATION_ID,
        "status": record["status"],
        "current_index": current_index,
        "total_stops": int(record["total_stops"] or SIMULATION_TOTAL_STOPS),
        "driver_id": record["driver_id"],
        "current_stop": current_stop,
        "started_at": record["started_at"],
        "finished_at": record["finished_at"],
        "error": record["error"],
        "kpis": kpis,
    }


async def _broadcast_tick(status: dict[str, Any]) -> None:
    await gestor.difundir_a_central(
        {
            "type": "simulation:tick",
            "simulation_id": SIMULATION_ID,
            "status": status["status"],
            "current_index": status["current_index"],
            "total_stops": status["total_stops"],
            "driver_id": status["driver_id"],
            "current_stop": status["current_stop"],
            "kpis": status["kpis"],
        }
    )


async def _run_route20_job() -> None:
    try:
        completed_count = 0
        while completed_count < SIMULATION_TOTAL_STOPS:
            with obtener_conexion() as session:
                plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
                persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)
                if not plan["order_ids"]:
                    break

                order_id = plan["order_ids"][0]
                stop = _get_order(session, order_id)
                if stop is None:
                    break

                current_position = _get_driver_position(session)
                route_geometry = _normalize_route_geometry(plan.get("route_geometry"))

            traveled_km = await _move_along_route_geometry(current_position, stop, route_geometry)

            with obtener_conexion() as session:
                session.run(
                    """
                    MATCH (u:User {id: $driver_id})
                    SET u.lat = $lat,
                        u.lng = $lng,
                        u.heading = $heading,
                        u.location_updated_at = datetime()
                    WITH u
                    MATCH (o:Order {id: $order_id, simulation_id: $simulation_id})
                    SET o.status = 'completed',
                        o.completed_by_driver_id = $driver_id,
                        o.completed_at = datetime(),
                        o.updated_at = datetime()
                    WITH u, o
                    MATCH (u)-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
                    WITH r, coalesce(r.completed_order_ids, []) AS completed_ids
                    SET r.completed_order_ids = CASE
                        WHEN $order_id IN completed_ids THEN completed_ids
                        ELSE completed_ids + [$order_id]
                    END,
                        r.simulation_traveled_km = coalesce(r.simulation_traveled_km, 0.0) + $traveled_km
                    """,
                    {
                        "driver_id": SIMULATION_DRIVER_ID,
                        "lat": stop["lat"],
                        "lng": stop["lng"],
                        "heading": _heading(current_position, stop),
                        "order_id": order_id,
                        "simulation_id": SIMULATION_ID,
                        "traveled_km": traveled_km,
                    },
                )
                registrar_evento_auditoria(
                    session,
                    order_id,
                    "complete",
                    SIMULATION_DRIVER_ID,
                    "Pedido demo completado por simulacion",
                )
                completed_count += 1
                plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
                persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)
                session.run(
                    """
                    MATCH (run:SimulationRun {id: $simulation_id})
                    SET run.current_index = $index,
                        run.status = CASE WHEN $index >= $total THEN 'completed' ELSE 'running' END,
                        run.finished_at = CASE WHEN $index >= $total THEN datetime() ELSE run.finished_at END
                    """,
                    {
                        "simulation_id": SIMULATION_ID,
                        "index": completed_count,
                        "total": SIMULATION_TOTAL_STOPS,
                    },
                )

            status = get_route20_status()
            await _broadcast_tick(status)
            if completed_count >= SIMULATION_TOTAL_STOPS:
                await gestor.difundir_a_central(
                    {"type": "simulation:completed", "simulation_id": SIMULATION_ID, "status": status}
                )
    except asyncio.CancelledError:
        logger.info("Route 20 simulation cancelled")
    except Exception as exc:
        logger.exception("Route 20 simulation failed")
        with obtener_conexion() as session:
            session.run(
                """
                MATCH (run:SimulationRun {id: $simulation_id})
                SET run.status = 'failed',
                    run.error = $error,
                    run.finished_at = datetime()
                """,
                {"simulation_id": SIMULATION_ID, "error": str(exc)},
            )
        await gestor.difundir_a_central(
            {"type": "simulation:tick", "simulation_id": SIMULATION_ID, "status": "failed", "error": str(exc)}
        )


async def _move_along_route_geometry(
    current_position: dict[str, Any],
    stop: dict[str, Any],
    route_geometry: list[dict[str, float]],
) -> float:
    segment = _segment_until_stop(current_position, stop, route_geometry)
    updates = _resample_polyline(segment, UPDATES_PER_STOP)
    sleep_seconds = SECONDS_PER_STOP / max(1, len(updates))
    previous = current_position
    traveled_km = 0.0

    for point in updates:
        traveled_km += _distance_km(previous, point)
        with obtener_conexion() as session:
            session.run(
                """
                MATCH (u:User {id: $driver_id})
                SET u.lat = $lat,
                    u.lng = $lng,
                    u.heading = $heading,
                    u.location_updated_at = datetime()
                """,
                {
                    "driver_id": SIMULATION_DRIVER_ID,
                    "lat": point["lat"],
                    "lng": point["lng"],
                    "heading": _heading(previous, point),
                },
            )
        await gestor.difundir_a_central(
            {
                "type": "driver:location:update",
                "driver_id": SIMULATION_DRIVER_ID,
                "lat": point["lat"],
                "lng": point["lng"],
                "heading": _heading(previous, point),
                "updated_at": None,
            }
        )
        previous = point
        await asyncio.sleep(sleep_seconds)
    return traveled_km


def _normalize_route_geometry(raw_geometry: Any) -> list[dict[str, float]]:
    if isinstance(raw_geometry, str):
        try:
            raw_geometry = json.loads(raw_geometry)
        except json.JSONDecodeError:
            raw_geometry = []
    if not isinstance(raw_geometry, list):
        return []

    points: list[dict[str, float]] = []
    for point in raw_geometry:
        if not isinstance(point, dict):
            continue
        try:
            points.append({"lat": float(point["lat"]), "lng": float(point["lng"])})
        except (KeyError, TypeError, ValueError):
            continue
    return points


def _segment_until_stop(
    current_position: dict[str, Any],
    stop: dict[str, Any],
    route_geometry: list[dict[str, float]],
) -> list[dict[str, float]]:
    current = {"lat": float(current_position["lat"]), "lng": float(current_position["lng"])}
    target = {"lat": float(stop["lat"]), "lng": float(stop["lng"])}
    if len(route_geometry) < 2:
        return [current, target]

    current_index = min(
        range(len(route_geometry)),
        key=lambda idx: _distance_km(route_geometry[idx], current),
    )
    target_index = min(
        range(current_index, len(route_geometry)),
        key=lambda idx: _distance_km(route_geometry[idx], target),
    )
    segment = route_geometry[current_index : target_index + 1]
    if not segment or _distance_km(segment[0], current) > 0.02:
        segment.insert(0, current)
    if _distance_km(segment[-1], target) > 0.02:
        segment.append(target)
    return segment


def _resample_polyline(
    points: list[dict[str, float]],
    sample_count: int,
) -> list[dict[str, float]]:
    if len(points) <= 1:
        return points

    distances = [0.0]
    total = 0.0
    for index in range(1, len(points)):
        total += _distance_km(points[index - 1], points[index])
        distances.append(total)

    if total <= 0:
        return [points[-1]]

    samples: list[dict[str, float]] = []
    segment_index = 1
    for sample_index in range(1, sample_count + 1):
        target_distance = total * sample_index / sample_count
        while segment_index < len(distances) - 1 and distances[segment_index] < target_distance:
            segment_index += 1

        previous_distance = distances[segment_index - 1]
        next_distance = distances[segment_index]
        ratio = (
            (target_distance - previous_distance) / (next_distance - previous_distance)
            if next_distance > previous_distance
            else 1.0
        )
        previous = points[segment_index - 1]
        next_point = points[segment_index]
        samples.append(
            {
                "lat": previous["lat"] + (next_point["lat"] - previous["lat"]) * ratio,
                "lng": previous["lng"] + (next_point["lng"] - previous["lng"]) * ratio,
            }
        )
    return samples


def _distance_km(origin: dict[str, Any], destination: dict[str, Any]) -> float:
    lat1 = math.radians(float(origin["lat"]))
    lat2 = math.radians(float(destination["lat"]))
    delta_lat = lat2 - lat1
    delta_lng = math.radians(float(destination["lng"]) - float(origin["lng"]))
    central = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lng / 2) ** 2
    )
    return 6371.0 * 2 * math.atan2(math.sqrt(central), math.sqrt(1 - central))


def _heading(previous: dict[str, Any], stop: dict[str, Any]) -> float:
    lat_delta = float(stop["lat"]) - float(previous["lat"])
    lng_delta = float(stop["lng"]) - float(previous["lng"])
    if abs(lat_delta) < 1e-9 and abs(lng_delta) < 1e-9:
        return 0.0
    return float((math.degrees(math.atan2(lng_delta, lat_delta)) + 360.0) % 360.0)
