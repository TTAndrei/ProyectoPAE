from __future__ import annotations

from typing import Any

from app.routing import distancia_haversine_km

LOAD_EFFICIENCY_TARGET = 0.75
LOAD_EFFICIENCY_NOTE = (
    "Ratio calculado como km hacia pedidos delivery / km totales de la ruta activa. "
    "El modelo actual no guarda pares pickup-delivery ni capacidad de vehiculo."
)


def _round_km(value: float) -> float:
    return round(max(0.0, value), 2)


def _order_route_stops(orders: list[dict[str, Any]], route_order_ids: list[str]) -> list[dict[str, Any]]:
    by_id = {order["id"]: order for order in orders}
    ordered = [by_id[order_id] for order_id in route_order_ids if order_id in by_id]
    already_ordered = {order["id"] for order in ordered}
    ordered.extend(order for order in orders if order["id"] not in already_ordered)
    return ordered


def _route_distances(driver: dict[str, Any], active_orders: list[dict[str, Any]]) -> tuple[float, float]:
    if not active_orders:
        return 0.0, 0.0

    current_lat = driver.get("lat")
    current_lng = driver.get("lng")
    if current_lat is None or current_lng is None:
        current_lat = active_orders[0]["lat"]
        current_lng = active_orders[0]["lng"]

    total_km = 0.0
    loaded_km = 0.0
    for order in active_orders:
        leg_km = distancia_haversine_km(
            float(current_lat),
            float(current_lng),
            float(order["lat"]),
            float(order["lng"]),
        )
        total_km += leg_km
        if order.get("type") == "delivery":
            loaded_km += leg_km
        current_lat = order["lat"]
        current_lng = order["lng"]

    return loaded_km, total_km


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
        OPTIONAL MATCH (u)-[:ASSIGNED_TO]->(completed:Order {status: 'completed'})
        RETURN u.id AS driver_id,
               u.lat AS lat,
               u.lng AS lng,
               coalesce(r.order_ids, []) AS route_order_ids,
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
    loaded_km, total_km = _route_distances(dict(record), active_orders)
    ratio = loaded_km / total_km if total_km > 0 else 0.0
    pending_count = sum(1 for order in active_orders if order.get("status") == "assigned")

    return {
        "driver_id": record["driver_id"],
        "load_efficiency_ratio": round(ratio, 4),
        "load_efficiency_percent": round(ratio * 100, 1),
        "loaded_distance_km": _round_km(loaded_km),
        "total_distance_km": _round_km(total_km),
        "active_order_count": len(active_orders),
        "pending_confirmation_count": pending_count,
        "completed_order_count": int(record["completed_order_count"] or 0),
        "target_load_efficiency_ratio": LOAD_EFFICIENCY_TARGET,
        "meets_load_efficiency_target": ratio >= LOAD_EFFICIENCY_TARGET,
        "measurement_note": LOAD_EFFICIENCY_NOTE,
    }


def listar_kpis_repartidores(session) -> dict[str, dict[str, Any]]:
    result = session.run("MATCH (u:User {role: 'repartidor'}) RETURN u.id AS id")
    kpis = {}
    for record in result:
        driver_kpis = calcular_kpis_repartidor(session, record["id"])
        if driver_kpis:
            kpis[record["id"]] = driver_kpis
    return kpis
