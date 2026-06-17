import json
from typing import Any

from app.services.driver_kpis import listar_kpis_repartidores


def obtener_resumen_flota(session, company_id: str) -> dict[str, Any]:
    kpis_por_repartidor = listar_kpis_repartidores(session, company_id)

    total_dist = sum(d["total_distance_km"] for d in kpis_por_repartidor.values())
    loaded_dist = sum(d["loaded_distance_km"] for d in kpis_por_repartidor.values())
    load_weighted_distance = sum(
        d["load_weighted_distance"] for d in kpis_por_repartidor.values()
    )
    completed_orders = sum(d["completed_order_count"] for d in kpis_por_repartidor.values())
    accepted_insertions = sum(
        d["accepted_insertion_count"] for d in kpis_por_repartidor.values()
    )
    rejected_insertions = sum(
        d["rejected_insertion_count"] for d in kpis_por_repartidor.values()
    )
    insertion_decisions = accepted_insertions + rejected_insertions
    detour_values = [
        d["average_insertion_detour_minutes"]
        for d in kpis_por_repartidor.values()
        if d["average_insertion_detour_minutes"] > 0
    ]

    avg_efficiency = (loaded_dist / total_dist * 100.0) if total_dist > 0 else 0.0

    return {
        "total_distance_km": round(total_dist, 2),
        "loaded_distance_km": round(loaded_dist, 2),
        "average_load_efficiency_percent": round(avg_efficiency, 1),
        "total_active_orders": sum(d["active_order_count"] for d in kpis_por_repartidor.values()),
        "total_pending_confirmations": sum(d["pending_confirmation_count"] for d in kpis_por_repartidor.values()),
        "total_completed_orders": completed_orders,
        "average_load_packages": round(
            load_weighted_distance / total_dist, 2
        ) if total_dist > 0 else 0.0,
        "average_insertion_detour_minutes": round(
            sum(detour_values) / len(detour_values), 1
        ) if detour_values else 0.0,
        "packages_per_km": round(completed_orders / total_dist, 2) if total_dist > 0 else 0.0,
        "insertion_acceptance_rate": round(
            accepted_insertions / insertion_decisions, 4
        ) if insertion_decisions else 0.0,
    }


def obtener_ranking_repartidores(session, company_id: str) -> list[dict[str, Any]]:
    kpis_por_repartidor = listar_kpis_repartidores(session, company_id)

    result = session.run(
        """
        MATCH (u:User {role: 'repartidor'})-[:BELONGS_TO]->(:Company {id: $cid})
        RETURN u.id AS id, coalesce(u.name, u.username) AS name
        """,
        {"cid": company_id},
    )
    names_map = {record["id"]: record["name"] for record in result}

    ranking = []
    for driver_id, kpis in kpis_por_repartidor.items():
        name = names_map.get(driver_id, driver_id)
        ranking.append({
            "driver_id": driver_id,
            "name": name,
            "load_efficiency_ratio": kpis["load_efficiency_ratio"],
            "load_efficiency_percent": kpis["load_efficiency_percent"],
            "loaded_distance_km": kpis["loaded_distance_km"],
            "total_distance_km": kpis["total_distance_km"],
            "active_order_count": kpis["active_order_count"],
            "pending_confirmation_count": kpis["pending_confirmation_count"],
            "completed_order_count": kpis["completed_order_count"],
            "average_load_packages": kpis["average_load_packages"],
            "average_insertion_detour_minutes": kpis["average_insertion_detour_minutes"],
            "packages_per_km": kpis["packages_per_km"],
            "insertion_acceptance_rate": kpis["insertion_acceptance_rate"],
            "meets_load_efficiency_target": kpis["meets_load_efficiency_target"],
        })

    ranking.sort(key=lambda x: x["load_efficiency_percent"], reverse=True)
    return ranking


def obtener_historial_rutas(session, company_id: str) -> list[dict[str, Any]]:
    result = session.run(
        """
        MATCH (r:Route {status: 'completed'})
        MATCH (j:Jornada)-[:HAD_ROUTE]->(r)
        MATCH (u:User)-[:HAS_JORNADA]->(j)
        MATCH (u)-[:BELONGS_TO]->(:Company {id: $cid})
        RETURN r.id AS id,
               u.id AS driver_id,
               coalesce(r.order_ids, []) AS order_ids,
               coalesce(r.completed_order_ids, []) AS completed_order_ids,
               r.status AS status,
               toString(r.created_at) AS created_at,
               toString(r.updated_at) AS updated_at,
               coalesce(r.total_minutes, 0.0) AS total_minutes,
               coalesce(r.total_distance_km, 0.0) AS total_distance_km,
               r.route_geometry AS route_geometry_str,
               coalesce(r.leg_minutes, []) AS leg_minutes
        ORDER BY r.updated_at DESC
        """,
        {"cid": company_id},
    )
    rutas = []
    for record in result:
        data = record.data()
        geom_str = data.pop("route_geometry_str", None)
        geom = []
        if geom_str:
            try:
                geom = json.loads(geom_str)
            except Exception:
                pass
        data["route_geometry"] = geom
        rutas.append(data)
    return rutas


def obtener_linea_tiempo_pedido(session, order_id: str, company_id: str) -> list[dict[str, Any]]:
    result = session.run(
        """
        MATCH (o:Order {id: $oid})-[:BELONGS_TO]->(:Company {id: $cid})
        MATCH (o)-[:LOGGED_EVENT]->(e:AuditEvent)
        RETURN e.id AS id,
               e.order_id AS order_id,
               e.action AS action,
               e.driver_id AS driver_id,
               toString(e.timestamp) AS timestamp,
               e.details AS details
        ORDER BY e.timestamp ASC
        """,
        {"oid": order_id, "cid": company_id},
    )
    return [record.data() for record in result]
