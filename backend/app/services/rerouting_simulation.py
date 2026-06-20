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

SIMULATION_ID = "rerouting-demo"
SIMULATION_DRIVER_ID = DEMO_DRIVER_ID
INITIAL_STOP_COUNT = 3
SECONDS_PER_STOP = 6.0
UPDATES_PER_STOP = 48

START_POSITION = {"lat": 41.6262, "lng": 2.6880}

INITIAL_STOPS: list[dict[str, Any]] = [
    {
        "id": "sim-reroute-far-01",
        "name": "Recogida FIFO lejana Tordera",
        "address": "Carrer Sant Ramon 19, Tordera",
        "lat": 41.6991,
        "lng": 2.7192,
    },
    {
        "id": "sim-reroute-near-02",
        "name": "Recogida Pineda Centre",
        "address": "Carrer Major 12, Pineda de Mar",
        "lat": 41.6271,
        "lng": 2.6882,
    },
    {
        "id": "sim-reroute-near-03",
        "name": "Recogida Poblenou",
        "address": "Avinguda Hispanitat 4, Pineda de Mar",
        "lat": 41.6228,
        "lng": 2.6819,
    },
]

INJECTED_STOPS: list[dict[str, Any]] = [
    {
        "id": "sim-reroute-insert-04",
        "name": "Nueva recogida Riera",
        "address": "Carrer Riera 22, Pineda de Mar",
        "lat": 41.6254,
        "lng": 2.6909,
    },
    {
        "id": "sim-reroute-insert-05",
        "name": "Nueva recogida Passeig",
        "address": "Passeig Maritim 38, Pineda de Mar",
        "lat": 41.6222,
        "lng": 2.6934,
    },
    {
        "id": "sim-reroute-insert-06",
        "name": "Nueva recogida Santa Susanna",
        "address": "Avinguda del Mar 15, Santa Susanna",
        "lat": 41.6361,
        "lng": 2.7161,
    },
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


def _all_stops_by_id() -> dict[str, dict[str, Any]]:
    return {stop["id"]: stop for stop in [*INITIAL_STOPS, *INJECTED_STOPS]}


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
        {"driver_id": SIMULATION_DRIVER_ID, "simulation_id": SIMULATION_ID},
    ).single()
    return _order_projection(record["o"]) if record else None


def _get_driver_position(session) -> dict[str, float]:
    record = session.run(
        "MATCH (u:User {id: $driver_id}) RETURN u.lat AS lat, u.lng AS lng",
        {"driver_id": SIMULATION_DRIVER_ID},
    ).single()
    if not record or record["lat"] is None or record["lng"] is None:
        return dict(START_POSITION)
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
        {"id": SIMULATION_DRIVER_ID, **START_POSITION, "simulation_id": SIMULATION_ID},
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
        "MATCH (r:Route {simulation_id: $simulation_id}) DETACH DELETE r",
        {"simulation_id": SIMULATION_ID},
    )
    session.run(
        "MATCH (j:Jornada {simulation_id: $simulation_id}) DETACH DELETE j",
        {"simulation_id": SIMULATION_ID},
    )


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


def _create_run(session, status: str) -> None:
    initial_ids = [stop["id"] for stop in INITIAL_STOPS]
    session.run(
        """
        MERGE (run:SimulationRun {id: $simulation_id})
        SET run.status = $status,
            run.current_index = 0,
            run.driver_id = $driver_id,
            run.started_at = datetime(),
            run.finished_at = null,
            run.error = null,
            run.total_stops = $total_stops,
            run.fifo_order_ids = $fifo_order_ids,
            run.injected_count = 0,
            run.dynamic_traveled_km = 0.0,
            run.events_json = '[]'
        """,
        {
            "simulation_id": SIMULATION_ID,
            "status": status,
            "driver_id": SIMULATION_DRIVER_ID,
            "total_stops": INITIAL_STOP_COUNT,
            "fifo_order_ids": initial_ids,
        },
    )


def _pause_existing_routes(session) -> None:
    session.run(
        """
        MATCH (u:User {id: $driver_id})-[:HAS_ROUTE]->(old:Route {status: 'active'})
        WHERE coalesce(old.simulation_id, '') <> $simulation_id
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


def _create_order(session, stop: dict[str, Any], index: int) -> None:
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


def _create_orders_and_route(session) -> None:
    order_ids = [stop["id"] for stop in INITIAL_STOPS]
    _pause_existing_routes(session)
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

    for index, stop in enumerate(INITIAL_STOPS, start=1):
        _create_order(session, stop, index)

    plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
    persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)


async def start_rerouting_simulation() -> dict[str, Any]:
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
        _task = asyncio.create_task(_run_rerouting_job())

    await gestor.difundir_a_central(
        {"type": "simulation:tick", "simulation_id": SIMULATION_ID, "status": "running", "current_index": 0}
    )
    return get_rerouting_status()


def reset_rerouting_simulation() -> dict[str, Any]:
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
                run.total_stops = $total_stops,
                run.fifo_order_ids = [],
                run.injected_count = 0,
                run.dynamic_traveled_km = 0.0,
                run.events_json = '[]'
            """,
            {
                "simulation_id": SIMULATION_ID,
                "driver_id": SIMULATION_DRIVER_ID,
                "total_stops": INITIAL_STOP_COUNT,
            },
        )
        plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
        persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)

    return get_rerouting_status()


def get_rerouting_kpis() -> dict[str, Any]:
    with obtener_conexion() as session:
        return calcular_kpis_repartidor(session, SIMULATION_DRIVER_ID) or _empty_kpis()


def get_rerouting_status() -> dict[str, Any]:
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
                   run.error AS error,
                   coalesce(run.fifo_order_ids, []) AS fifo_order_ids,
                   coalesce(run.dynamic_traveled_km, 0.0) AS dynamic_traveled_km,
                   coalesce(run.events_json, '[]') AS events_json
            """,
            {"id": SIMULATION_ID, "driver_id": SIMULATION_DRIVER_ID, "total_stops": INITIAL_STOP_COUNT},
        ).single()
        if not record:
            session.run(
                """
                MERGE (run:SimulationRun {id: $id})
                SET run.status = 'idle',
                    run.current_index = 0,
                    run.driver_id = $driver_id,
                    run.total_stops = $total_stops,
                    run.fifo_order_ids = [],
                    run.dynamic_traveled_km = 0.0,
                    run.events_json = '[]'
                """,
                {"id": SIMULATION_ID, "driver_id": SIMULATION_DRIVER_ID, "total_stops": INITIAL_STOP_COUNT},
            )
            record = {
                "status": "idle",
                "current_index": 0,
                "total_stops": INITIAL_STOP_COUNT,
                "driver_id": SIMULATION_DRIVER_ID,
                "started_at": None,
                "finished_at": None,
                "error": None,
                "fifo_order_ids": [],
                "dynamic_traveled_km": 0.0,
                "events_json": "[]",
            }
        else:
            record = dict(record)

        current_stop = _get_next_active_order(session)
        kpis = calcular_kpis_repartidor(session, SIMULATION_DRIVER_ID) or _empty_kpis()
        comparison = _build_comparison(session, record)
        events = _decode_events(record.get("events_json"))

    return {
        "id": SIMULATION_ID,
        "status": record["status"],
        "current_index": int(record["current_index"] or 0),
        "total_stops": int(record["total_stops"] or INITIAL_STOP_COUNT),
        "driver_id": record["driver_id"],
        "current_stop": current_stop,
        "started_at": record["started_at"],
        "finished_at": record["finished_at"],
        "error": record["error"],
        "comparison": comparison,
        "events": events,
        "kpis": kpis,
    }


def _decode_events(raw: Any) -> list[dict[str, Any]]:
    if not raw:
        return []
    if isinstance(raw, list):
        return [event for event in raw if isinstance(event, dict)]
    try:
        decoded = json.loads(str(raw))
    except json.JSONDecodeError:
        return []
    return decoded if isinstance(decoded, list) else []


def _build_comparison(session, run: dict[str, Any]) -> dict[str, Any]:
    dynamic_traveled = float(run.get("dynamic_traveled_km") or 0.0)
    route = session.run(
        """
        MATCH (:User {id: $driver_id})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
        RETURN coalesce(r.order_ids, []) AS order_ids,
               coalesce(r.total_distance_km, 0.0) AS total_distance_km
        """,
        {"driver_id": SIMULATION_DRIVER_ID, "simulation_id": SIMULATION_ID},
    ).single()
    dynamic_order_ids = list(route["order_ids"] or []) if route else []

    active_ids = _active_order_ids(session)
    current_position = _get_driver_position(session)
    dynamic_remaining = _distance_for_order_ids(session, current_position, dynamic_order_ids)
    fifo_order_ids = [
        order_id for order_id in list(run.get("fifo_order_ids") or []) if order_id in active_ids
    ]
    fifo_remaining = _distance_for_order_ids(session, current_position, fifo_order_ids)

    dynamic_distance = round(dynamic_traveled + dynamic_remaining, 2)
    fifo_distance = round(dynamic_traveled + fifo_remaining, 2)
    savings = round(max(0.0, fifo_distance - dynamic_distance), 2)
    savings_percent = round((savings / fifo_distance) * 100.0, 1) if fifo_distance > 0 else 0.0

    completed = int(run.get("current_index") or 0)
    return {
        "dynamic_distance_km": dynamic_distance,
        "fifo_distance_km": fifo_distance,
        "savings_km": savings,
        "savings_percent": savings_percent,
        "dynamic_order_ids": dynamic_order_ids,
        "fifo_order_ids": fifo_order_ids,
        "completed_order_count": completed,
        "active_order_count": len(active_ids),
    }


def _active_order_ids(session) -> set[str]:
    result = session.run(
        """
        MATCH (o:Order {simulation_id: $simulation_id})
        WHERE o.status IN ['assigned', 'in_progress']
        RETURN o.id AS id
        """,
        {"simulation_id": SIMULATION_ID},
    )
    return {record["id"] for record in result}


def _distance_for_order_ids(session, origin: dict[str, float], order_ids: list[str]) -> float:
    total = 0.0
    current = dict(origin)
    for order_id in order_ids:
        order = _get_order(session, order_id)
        if not order:
            continue
        total += _distance_km(current, order)
        current = {"lat": float(order["lat"]), "lng": float(order["lng"])}
    return total


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
            "comparison": status["comparison"],
            "events": status["events"],
            "kpis": status["kpis"],
        }
    )


async def _run_rerouting_job() -> None:
    try:
        completed_count = 0
        injected_count = 0
        while True:
            should_complete = False
            with obtener_conexion() as session:
                plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
                persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)
                if not plan["order_ids"]:
                    _mark_completed(session, completed_count)
                    should_complete = True
                    order_id = ""
                    stop = None
                    current_position = {}
                    route_geometry = []
                else:
                    order_id = plan["order_ids"][0]
                    stop = _get_order(session, order_id)
                    if stop is None:
                        break
                    current_position = _get_driver_position(session)
                    route_geometry = _normalize_route_geometry(plan.get("route_geometry"))

            if should_complete:
                status = get_rerouting_status()
                await gestor.difundir_a_central(
                    {"type": "simulation:completed", "simulation_id": SIMULATION_ID, "status": status}
                )
                break

            traveled = await _move_along_route_geometry(current_position, stop, route_geometry)

            with obtener_conexion() as session:
                _complete_order(session, order_id, stop, current_position, traveled)
                completed_count += 1
                _set_run_progress(session, completed_count, None)

            if injected_count < len(INJECTED_STOPS):
                injected_count += 1
                await _inject_stop(injected_count)

            status = get_rerouting_status()
            await _broadcast_tick(status)
    except asyncio.CancelledError:
        logger.info("Rerouting simulation cancelled")
    except Exception as exc:
        logger.exception("Rerouting simulation failed")
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


def _complete_order(
    session,
    order_id: str,
    stop: dict[str, Any],
    previous_position: dict[str, Any],
    traveled_km: float,
) -> None:
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
            "heading": _heading(previous_position, stop),
            "order_id": order_id,
            "simulation_id": SIMULATION_ID,
            "traveled_km": traveled_km,
        },
    )
    session.run(
        """
        MATCH (run:SimulationRun {id: $simulation_id})
        SET run.dynamic_traveled_km = coalesce(run.dynamic_traveled_km, 0.0) + $traveled_km
        """,
        {"simulation_id": SIMULATION_ID, "traveled_km": traveled_km},
    )
    registrar_evento_auditoria(
        session,
        order_id,
        "complete",
        SIMULATION_DRIVER_ID,
        "Pedido demo completado por simulacion rerouting",
    )
    plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
    persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)


def _set_run_progress(session, completed_count: int, status: str | None) -> None:
    session.run(
        """
        MATCH (run:SimulationRun {id: $simulation_id})
        SET run.current_index = $index,
            run.status = coalesce($status, run.status)
        """,
        {"simulation_id": SIMULATION_ID, "index": completed_count, "status": status},
    )


def _mark_completed(session, completed_count: int) -> None:
    session.run(
        """
        MATCH (run:SimulationRun {id: $simulation_id})
        SET run.current_index = $index,
            run.status = 'completed',
            run.finished_at = datetime()
        """,
        {"simulation_id": SIMULATION_ID, "index": completed_count},
    )


async def _inject_stop(injected_count: int) -> None:
    stop = INJECTED_STOPS[injected_count - 1]
    with obtener_conexion() as session:
        previous_order_ids = _active_route_order_ids(session)
        _create_order(session, stop, INITIAL_STOP_COUNT + injected_count)
        run_record = session.run(
            """
            MATCH (run:SimulationRun {id: $simulation_id})
            SET run.injected_count = $injected_count,
                run.total_stops = $total_stops,
                run.fifo_order_ids = coalesce(run.fifo_order_ids, []) + [$order_id]
            RETURN coalesce(run.events_json, '[]') AS events_json
            """,
            {
                "simulation_id": SIMULATION_ID,
                "injected_count": injected_count,
                "total_stops": INITIAL_STOP_COUNT + injected_count,
                "order_id": stop["id"],
            },
        ).single()
        plan = plan_ruta_repartidor(session, SIMULATION_DRIVER_ID)
        persistir_metricas_ruta(session, SIMULATION_DRIVER_ID, plan)
        new_order_ids = list(plan["order_ids"])
        event = {
            "type": "reroute",
            "order_id": stop["id"],
            "message": f"{stop['name']} insertada y ruta reoptimizada",
            "previous_order_ids": previous_order_ids,
            "new_order_ids": new_order_ids,
        }
        events = _decode_events(run_record["events_json"] if run_record else "[]")
        events.append(event)
        session.run(
            """
            MATCH (run:SimulationRun {id: $simulation_id})
            SET run.events_json = $events_json
            """,
            {"simulation_id": SIMULATION_ID, "events_json": json.dumps(events)},
        )

    await gestor.difundir_a_central(
        {
            "type": "simulation:reroute",
            "simulation_id": SIMULATION_ID,
            "inserted_order_id": stop["id"],
            "previous_order_ids": previous_order_ids,
            "new_order_ids": new_order_ids,
        }
    )


def _active_route_order_ids(session) -> list[str]:
    record = session.run(
        """
        MATCH (:User {id: $driver_id})-[:HAS_ROUTE]->(r:Route {status: 'active', simulation_id: $simulation_id})
        RETURN coalesce(r.order_ids, []) AS order_ids
        """,
        {"driver_id": SIMULATION_DRIVER_ID, "simulation_id": SIMULATION_ID},
    ).single()
    return list(record["order_ids"] or []) if record else []


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
        heading = _heading(previous, point)
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
                    "heading": heading,
                },
            )
        await gestor.difundir_a_central(
            {
                "type": "driver:location:update",
                "driver_id": SIMULATION_DRIVER_ID,
                "lat": point["lat"],
                "lng": point["lng"],
                "heading": heading,
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
    target_candidates = range(current_index, len(route_geometry))
    target_index = min(
        target_candidates,
        key=lambda idx: _distance_km(route_geometry[idx], target),
    )
    segment = route_geometry[current_index : target_index + 1]
    if not segment or _distance_km(segment[0], current) > 0.005:
        segment.insert(0, current)
    if _distance_km(segment[-1], target) > 0.005:
        segment.append(target)
    return segment


def _resample_polyline(points: list[dict[str, float]], sample_count: int) -> list[dict[str, float]]:
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
