from __future__ import annotations

from typing import Any

from app.routing import distancia_haversine_km

LOAD_EFFICIENCY_TARGET = 0.75
LOAD_EFFICIENCY_NOTE = (
    "Ratio calculado tramo a tramo: km con al menos un paquete a bordo / km totales. "
    "Sin pares pickup-delivery, cada delivery cuenta como paquete ya cargado y cada pickup "
    "suma un paquete despues de la recogida."
)


def _round_km(value: float) -> float:
    return round(max(0.0, value), 2)


def _order_route_stops(orders: list[dict[str, Any]], route_order_ids: list[str]) -> list[dict[str, Any]]:
    by_id = {order["id"]: order for order in orders}
    ordered = [by_id[order_id] for order_id in route_order_ids if order_id in by_id]
    already_ordered = {order["id"] for order in ordered}
    ordered.extend(order for order in orders if order["id"] not in already_ordered)
    return ordered


def _package_count(_order: dict[str, Any]) -> int:
    return 1


def _route_load_metrics(driver: dict[str, Any], active_orders: list[dict[str, Any]]) -> dict[str, float]:
    if not active_orders:
        return {
            "loaded_distance_km": 0.0,
            "total_distance_km": 0.0,
            "load_weighted_distance": 0.0,
            "average_load_packages": 0.0,
        }

    current_lat = driver.get("lat")
    current_lng = driver.get("lng")
    if current_lat is None or current_lng is None:
        current_lat = active_orders[0]["lat"]
        current_lng = active_orders[0]["lng"]

    total_km = 0.0
    loaded_km = 0.0
    load_weighted_distance = 0.0
    packages_on_board = sum(
        _package_count(order)
        for order in active_orders
        if order.get("type") == "delivery"
    )

    for order in active_orders:
        leg_km = distancia_haversine_km(
            float(current_lat),
            float(current_lng),
            float(order["lat"]),
            float(order["lng"]),
        )
        total_km += leg_km
        if packages_on_board > 0:
            loaded_km += leg_km
        load_weighted_distance += leg_km * packages_on_board

        package_count = _package_count(order)
        if order.get("type") == "delivery":
            packages_on_board = max(0, packages_on_board - package_count)
        elif order.get("type") == "pickup":
            packages_on_board += package_count

        current_lat = order["lat"]
        current_lng = order["lng"]

    return {
        "loaded_distance_km": loaded_km,
        "total_distance_km": total_km,
        "load_weighted_distance": load_weighted_distance,
        "average_load_packages": (
            load_weighted_distance / total_km if total_km > 0 else 0.0
        ),
    }


def _operational_stats(session, id_repartidor: str) -> dict[str, Any]:
    record = session.run(
        """
        MATCH (u:User {id: $id, role: 'repartidor'})
        OPTIONAL MATCH (u)-[:ASSIGNED_TO]->(o:Order)
        WITH [m IN collect(o.estimated_extra_minutes) WHERE m IS NOT NULL] AS extra_minutes
        OPTIONAL MATCH (event:AuditEvent {driver_id: $id})
        WITH extra_minutes, collect(event.action) AS actions
        RETURN extra_minutes,
               size([a IN actions WHERE a = 'accept']) AS accepted_count,
               size([a IN actions WHERE a = 'reject']) AS rejected_count
        """,
        {"id": id_repartidor},
    ).single()
    if not record:
        return {
            "average_insertion_detour_minutes": 0.0,
            "accepted_insertion_count": 0,
            "rejected_insertion_count": 0,
            "insertion_acceptance_rate": 0.0,
        }

    extra_minutes = [
        float(value)
        for value in (record["extra_minutes"] or [])
        if value is not None
    ]
    accepted = int(record["accepted_count"] or 0)
    rejected = int(record["rejected_count"] or 0)
    decisions = accepted + rejected

    return {
        "average_insertion_detour_minutes": round(
            sum(extra_minutes) / len(extra_minutes), 1
        )
        if extra_minutes
        else 0.0,
        "accepted_insertion_count": accepted,
        "rejected_insertion_count": rejected,
        "insertion_acceptance_rate": round(accepted / decisions, 4)
        if decisions
        else 0.0,
    }


def calcular_kpis_repartidor(session, id_repartidor: str) -> dict[str, Any] | None:
    record = session.run(
        """
        MATCH (u:User {id: $id, role: 'repartidor'})
        OPTIONAL MATCH (u)-[:HAS_ROUTE]->(r:Route {status: 'active'})
        OPTIONAL MATCH (u)-[:ASSIGNED_TO]->(active:Order)
        WHERE active.status IN ['assigned', 'in_progress']
        WITH u, r, collect(DISTINCT active {
            .id, .type, .lat, .lng, .status
        }) AS active_orders
        OPTIONAL MATCH (completed:Order {status: 'completed'})
        WHERE completed.completed_by_driver_id = u.id
           OR (
               completed.completed_by_driver_id IS NULL
               AND EXISTS {
                   MATCH (u)-[:ASSIGNED_TO]->(completed)
               }
           )
        RETURN u.id AS driver_id,
               u.lat AS lat,
               u.lng AS lng,
               coalesce(r.order_ids, []) AS route_order_ids,
               coalesce(r.simulation_traveled_km, 0.0) AS simulation_traveled_km,
               [o IN active_orders WHERE o.id IS NOT NULL] AS active_orders,
               count(DISTINCT completed) AS completed_order_count
        """,
        {"id": id_repartidor},
    ).single()
    if not record:
        return None

    active_orders = _order_route_stops(
        list(record["active_orders"] or []),
        list(record["route_order_ids"] or []),
    )
    load_metrics = _route_load_metrics(dict(record), active_orders)
    simulation_traveled_km = float(record["simulation_traveled_km"] or 0.0)
    if not active_orders and simulation_traveled_km > 0:
        load_metrics = {
            "loaded_distance_km": simulation_traveled_km,
            "total_distance_km": simulation_traveled_km,
            "load_weighted_distance": simulation_traveled_km,
            "average_load_packages": 1.0,
        }
    loaded_km = load_metrics["loaded_distance_km"]
    total_km = load_metrics["total_distance_km"]
    ratio = loaded_km / total_km if total_km > 0 else 0.0
    pending_count = sum(1 for order in active_orders if order.get("status") == "assigned")
    completed_count = int(record["completed_order_count"] or 0)
    operational_stats = _operational_stats(session, id_repartidor)

    return {
        "driver_id": record["driver_id"],
        "load_efficiency_ratio": round(ratio, 4),
        "load_efficiency_percent": round(ratio * 100, 1),
        "loaded_distance_km": _round_km(loaded_km),
        "total_distance_km": _round_km(total_km),
        "active_order_count": len(active_orders),
        "pending_confirmation_count": pending_count,
        "completed_order_count": completed_count,
        "average_load_packages": round(load_metrics["average_load_packages"], 2),
        "load_weighted_distance": _round_km(load_metrics["load_weighted_distance"]),
        "average_insertion_detour_minutes": operational_stats["average_insertion_detour_minutes"],
        "packages_per_km": round(completed_count / total_km, 2) if total_km > 0 else 0.0,
        "insertion_acceptance_rate": operational_stats["insertion_acceptance_rate"],
        "accepted_insertion_count": operational_stats["accepted_insertion_count"],
        "rejected_insertion_count": operational_stats["rejected_insertion_count"],
        "target_load_efficiency_ratio": LOAD_EFFICIENCY_TARGET,
        "meets_load_efficiency_target": ratio >= LOAD_EFFICIENCY_TARGET,
        "measurement_note": LOAD_EFFICIENCY_NOTE,
    }


def listar_kpis_repartidores(session, company_id: str) -> dict[str, dict[str, Any]]:
    result = session.run(
        """
        MATCH (u:User {role: 'repartidor'})-[:BELONGS_TO]->(:Company {id: $cid})
        RETURN u.id AS id
        """,
        {"cid": company_id},
    )
    kpis = {}
    for record in result:
        driver_kpis = calcular_kpis_repartidor(session, record["id"])
        if driver_kpis:
            kpis[record["id"]] = driver_kpis
    return kpis
