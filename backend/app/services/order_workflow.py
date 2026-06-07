import json
import logging
import uuid
from typing import Any

from fastapi import HTTPException

from app.config import OSRM_ACTIVO, OSRM_BASE_URL, OSRM_TIMEOUT_SEGUNDOS
from app.database import obtener_conexion
from app.routing import (
    calcular_tiempo_extra,
    detectar_candidatos_backhauling,
    optimizar_ruta_vial,
)
from app.schemas import CrearPedido
from app.ws_manager import gestor

logger = logging.getLogger(__name__)


def _plan_vacio() -> dict[str, Any]:
    return {
        "order_ids": [],
        "total_minutes": 0.0,
        "total_distance_km": 0.0,
        "route_geometry": [],
        "leg_minutes": [],
    }


def registrar_evento_auditoria(
    session,
    order_id: str,
    action: str,
    driver_id: str | None = None,
    details: str | None = None,
) -> None:
    event_id = str(uuid.uuid4())
    session.run(
        """
        MATCH (o:Order {id: $oid})
        CREATE (e:AuditEvent {
            id: $eid,
            order_id: $oid,
            action: $action,
            driver_id: $did,
            timestamp: datetime(),
            details: $details
        })
        CREATE (o)-[:LOGGED_EVENT]->(e)
        """,
        {
            "oid": order_id,
            "eid": event_id,
            "action": action,
            "did": driver_id,
            "details": details,
        },
    )


def obtener_posicion_repartidor(session, id_repartidor: str) -> dict | None:
    result = session.run(
        "MATCH (u:User {id: $id}) RETURN u.lat AS lat, u.lng AS lng",
        {"id": id_repartidor},
    )
    record = result.single()
    if not record or record["lat"] is None:
        return None
    return {"lat": record["lat"], "lng": record["lng"]}


def obtener_paradas_activas(session, id_repartidor: str) -> list[dict]:
    result = session.run(
        """
        MATCH (u:User {id: $id})-[:ASSIGNED_TO]->(o:Order)
        WHERE o.status IN $statuses
        RETURN o.id AS id, o.lat AS lat, o.lng AS lng
        """,
        {"id": id_repartidor, "statuses": ["assigned", "in_progress"]},
    )
    return [record.data() for record in result]


def obtener_repartidores_activos_con_paradas_para_pedido(
    session,
    id_pedido: str,
) -> list[dict]:
    result = session.run(
        """
        MATCH (order_comp:Order {id: $oid})-[:BELONGS_TO]->(c:Company)
        MATCH (u:User {role: 'repartidor'})-[:BELONGS_TO]->(c)
        WHERE u.lat IS NOT NULL
          AND coalesce(u.is_available, true) = true
          AND NOT (u)-[:REJECTED_BY]->(:Order {id: $oid})
        OPTIONAL MATCH (u)-[:ASSIGNED_TO]->(o:Order)
        WHERE o.status IN ["assigned", "in_progress"]
        WITH u, collect(CASE WHEN o IS NOT NULL THEN {id: o.id, lat: o.lat, lng: o.lng} END) AS paradas_raw
        RETURN u.id AS id, u.lat AS lat, u.lng AS lng,
               [p IN paradas_raw WHERE p IS NOT NULL] AS paradas_activas
        """,
        {"oid": id_pedido},
    )
    return [dict(record) for record in result]


def plan_ruta_repartidor(session, id_repartidor: str) -> dict:
    paradas = obtener_paradas_activas(session, id_repartidor)
    if not paradas:
        return _plan_vacio()

    posicion = obtener_posicion_repartidor(session, id_repartidor)
    if not posicion:
        posicion = {"lat": paradas[0]["lat"], "lng": paradas[0]["lng"]}

    optimizada = optimizar_ruta_vial(
        paradas,
        posicion,
        osrm_base_url=OSRM_BASE_URL if OSRM_ACTIVO else None,
        timeout_seconds=OSRM_TIMEOUT_SEGUNDOS,
    )
    order_ids = [parada["id"] for parada in optimizada["paradas_ordenadas"]]

    return {
        "order_ids": order_ids,
        "total_minutes": optimizada["minutos_totales"],
        "total_distance_km": optimizada["distancia_km"],
        "route_geometry": optimizada["route_geometry"],
        "leg_minutes": optimizada["leg_minutes"],
    }


def persistir_metricas_ruta(session, id_repartidor: str, plan: dict) -> None:
    session.run(
        """
        MATCH (u:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'})
        SET r.order_ids         = $order_ids,
            r.total_minutes     = $total_minutes,
            r.total_distance_km = $total_distance_km,
            r.route_geometry    = $route_geometry,
            r.leg_minutes       = $leg_minutes,
            r.updated_at        = datetime()
        """,
        {
            "id": id_repartidor,
            "order_ids": plan["order_ids"],
            "total_minutes": plan["total_minutes"],
            "total_distance_km": plan["total_distance_km"],
            "route_geometry": json.dumps(plan["route_geometry"]),
            "leg_minutes": plan["leg_minutes"],
        },
    )


def _pedido_con_asignado(session, id_pedido: str):
    return session.run(
        """
        MATCH (o:Order {id: $oid})
        OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
        RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o,
               u.id AS assigned_driver_id
        """,
        {"oid": id_pedido},
    ).single()


def _pedido_dict(session, id_pedido: str, assigned_driver_id: str | None = None) -> dict:
    record = session.run(
        "MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o",
        {"id": id_pedido},
    ).single()
    if not record:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    pedido = dict(record["o"])
    pedido["assigned_driver_id"] = assigned_driver_id
    return pedido


def _asignacion_actual(session, id_pedido: str) -> str | None:
    record = session.run(
        """
        MATCH (o:Order {id: $oid})
        OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
        RETURN u.id AS driver_id
        """,
        {"oid": id_pedido},
    ).single()
    return record["driver_id"] if record else None


def _nombre_repartidor(session, id_repartidor: str) -> str:
    record = session.run(
        "MATCH (u:User {id: $id}) RETURN coalesce(u.name, u.username, u.id) AS name",
        {"id": id_repartidor},
    ).single()
    return record["name"] if record else id_repartidor


def _eliminar_asignaciones(session, id_pedido: str) -> list[str]:
    result = session.run(
        """
        MATCH (u:User)-[r:ASSIGNED_TO]->(o:Order {id: $oid})
        WITH collect(DISTINCT u.id) AS drivers, collect(r) AS rels
        FOREACH (rel IN rels | DELETE rel)
        RETURN drivers
        """,
        {"oid": id_pedido},
    ).single()
    return list(result["drivers"] or []) if result else []


def _calcular_candidatos(session, id_pedido: str, pedido: dict) -> list[dict]:
    repartidores = obtener_repartidores_activos_con_paradas_para_pedido(session, id_pedido)
    if not repartidores:
        return []
    return detectar_candidatos_backhauling(
        {"id": id_pedido, "lat": pedido["lat"], "lng": pedido["lng"]},
        repartidores,
        osrm_base_url=OSRM_BASE_URL if OSRM_ACTIVO else None,
        timeout_seconds=OSRM_TIMEOUT_SEGUNDOS,
    )


def _calcular_extra_manual(session, id_pedido: str, id_repartidor: str, pedido: dict) -> float:
    posicion = obtener_posicion_repartidor(session, id_repartidor)
    paradas = obtener_paradas_activas(session, id_repartidor)

    if not posicion:
        if paradas:
            posicion = {"lat": paradas[0]["lat"], "lng": paradas[0]["lng"]}
        else:
            posicion = {"lat": 40.4168, "lng": -3.7038}

    resultado = calcular_tiempo_extra(
        paradas,
        posicion,
        {"id": id_pedido, "lat": pedido["lat"], "lng": pedido["lng"]},
        osrm_base_url=OSRM_BASE_URL if OSRM_ACTIVO else None,
        timeout_seconds=OSRM_TIMEOUT_SEGUNDOS,
    )
    return resultado["extra_minutos"]


def _asignar_en_session(
    session,
    id_pedido: str,
    id_repartidor: str,
    minutos_extra: float,
    candidate_ids: list[str],
) -> tuple[dict, dict, list[str]]:
    antiguos = _eliminar_asignaciones(session, id_pedido)
    session.run(
        """
        MATCH (o:Order {id: $oid}), (u:User {id: $uid})
        SET o.status = 'assigned',
            o.estimated_extra_minutes = $minutos,
            o.candidate_driver_ids = $candidate_ids,
            o.current_candidate_idx = 0,
            o.updated_at = datetime()
        MERGE (u)-[:ASSIGNED_TO]->(o)
        """,
        {
            "oid": id_pedido,
            "uid": id_repartidor,
            "minutos": minutos_extra,
            "candidate_ids": candidate_ids,
        },
    )

    for antiguo in antiguos:
        if antiguo != id_repartidor:
            persistir_metricas_ruta(session, antiguo, plan_ruta_repartidor(session, antiguo))

    plan = plan_ruta_repartidor(session, id_repartidor)
    persistir_metricas_ruta(session, id_repartidor, plan)
    pedido = _pedido_dict(session, id_pedido, id_repartidor)
    return pedido, plan, antiguos


async def crear_pedido(cuerpo: CrearPedido, company_id: str) -> dict:
    id_pedido = str(uuid.uuid4())
    with obtener_conexion() as session:
        session.run(
            """
            MATCH (c:Company {id: $company_id})
            CREATE (o:Order {
                id: $id,
                type: $type,
                name: $name,
                address: $address,
                lat: $lat,
                lng: $lng,
                status: 'pending',
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (o)-[:BELONGS_TO]->(c)
            """,
            {
                "id": id_pedido,
                "type": cuerpo.type,
                "name": cuerpo.name,
                "address": cuerpo.address,
                "lat": cuerpo.lat,
                "lng": cuerpo.lng,
                "company_id": company_id,
            },
        )
        registrar_evento_auditoria(session, id_pedido, 'create', details="Pedido creado en estado 'pending'")

        pedido_base = {"lat": cuerpo.lat, "lng": cuerpo.lng}
        candidatos = _calcular_candidatos(session, id_pedido, pedido_base)
        candidate_ids = [c["driver_id"] for c in candidatos]
        assigned_driver_id = None
        minutos_extra = 0.0

        if candidate_ids:
            assigned_driver_id = candidate_ids[0]
            minutos_extra = next(
                c["extra_minutos"] for c in candidatos if c["driver_id"] == assigned_driver_id
            )
            resp, _, _ = _asignar_en_session(
                session,
                id_pedido,
                assigned_driver_id,
                minutos_extra,
                candidate_ids,
            )
            registrar_evento_auditoria(session, id_pedido, 'assign', driver_id=assigned_driver_id, details=f"Asignado automáticamente con {minutos_extra} min extra")
        else:
            session.run(
                """
                MATCH (o:Order {id: $oid})
                SET o.status = 'pending',
                    o.candidate_driver_ids = [],
                    o.current_candidate_idx = -1,
                    o.updated_at = datetime()
                """,
                {"oid": id_pedido},
            )
            resp = _pedido_dict(session, id_pedido, None)

        resp["backhauling_candidates"] = candidatos

    if assigned_driver_id:
        await gestor.enviar_a_repartidor(
            assigned_driver_id,
            {
                "type": "pickup:notification",
                "order": resp,
                "extra_minutes": minutos_extra,
            },
        )
        await gestor.difundir_a_central(
            {
                "type": "pickup:assigned_automatically",
                "order_id": id_pedido,
                "driver_id": assigned_driver_id,
                "extra_minutes": minutos_extra,
                "candidates": candidatos,
            }
        )
    else:
        await gestor.difundir_a_central(
            {"type": "pickup:pending", "order_id": id_pedido, "order": resp}
        )

    return resp


async def asignar_pedido(id_pedido: str, id_repartidor: str) -> dict:
    with obtener_conexion() as session:
        record = _pedido_con_asignado(session, id_pedido)
        if not record:
            raise HTTPException(status_code=404, detail="Pedido no encontrado")
        pedido_base = dict(record["o"])

        minutos_extra = _calcular_extra_manual(session, id_pedido, id_repartidor, pedido_base)
        candidatos = _calcular_candidatos(session, id_pedido, pedido_base)
        candidate_ids = [id_repartidor] + [
            c["driver_id"] for c in candidatos if c["driver_id"] != id_repartidor
        ]

        pedido, plan, _ = _asignar_en_session(
            session,
            id_pedido,
            id_repartidor,
            minutos_extra,
            candidate_ids,
        )
        registrar_evento_auditoria(session, id_pedido, 'assign', driver_id=id_repartidor, details=f"Asignado manualmente con {minutos_extra} min extra")

    await gestor.enviar_a_repartidor(
        id_repartidor,
        {
            "type": "pickup:notification",
            "order": pedido,
            "extra_minutes": minutos_extra,
        },
    )

    return {
        "order": pedido,
        "extra_minutes": minutos_extra,
        "total_minutes": plan["total_minutes"],
        "total_distance_km": plan["total_distance_km"],
        "route_order_ids": plan["order_ids"],
        "route_geometry": plan["route_geometry"],
        "leg_minutes": plan["leg_minutes"],
    }


async def responder_pedido(id_pedido: str, id_repartidor: str, accepted: bool) -> dict:
    with obtener_conexion() as session:
        driver_name = _nombre_repartidor(session, id_repartidor)
        record = _pedido_con_asignado(session, id_pedido)
        if not record:
            raise HTTPException(status_code=404, detail="Pedido no encontrado")
        if record["assigned_driver_id"] != id_repartidor:
            raise HTTPException(status_code=403, detail="Este pedido no esta asignado a ti")

        pedido = dict(record["o"])
        minutos_extra = float(pedido.get("estimated_extra_minutes") or 0.0)

        if accepted:
            session.run(
                """
                MATCH (o:Order {id: $oid})
                SET o.status = 'in_progress', o.updated_at = datetime()
                """,
                {"oid": id_pedido},
            )
            registrar_evento_auditoria(session, id_pedido, 'accept', driver_id=id_repartidor, details="Pedido aceptado por el repartidor")
            registrar_evento_auditoria(session, id_pedido, 'start_delivery', driver_id=id_repartidor, details="Pedido en curso")

            plan = plan_ruta_repartidor(session, id_repartidor)
            persistir_metricas_ruta(session, id_repartidor, plan)
            actualizado = _pedido_dict(session, id_pedido, id_repartidor)
            nuevo_status = "in_progress"
            nuevo_driver_id = id_repartidor
            candidatos: list[dict] = []
        else:
            _eliminar_asignaciones(session, id_pedido)
            session.run(
                """
                MATCH (u:User {id: $uid}), (o:Order {id: $oid})
                MERGE (u)-[:REJECTED_BY]->(o)
                """,
                {"uid": id_repartidor, "oid": id_pedido},
            )
            registrar_evento_auditoria(session, id_pedido, 'reject', driver_id=id_repartidor, details="Pedido rechazado por el repartidor")

            persistir_metricas_ruta(session, id_repartidor, plan_ruta_repartidor(session, id_repartidor))

            candidatos = _calcular_candidatos(session, id_pedido, pedido)
            if candidatos:
                optimo = candidatos[0]
                nuevo_driver_id = optimo["driver_id"]
                minutos_extra = optimo["extra_minutos"]
                candidate_ids = [c["driver_id"] for c in candidatos]
                actualizado, plan, _ = _asignar_en_session(
                    session,
                    id_pedido,
                    nuevo_driver_id,
                    minutos_extra,
                    candidate_ids,
                )
                registrar_evento_auditoria(session, id_pedido, 'assign', driver_id=nuevo_driver_id, details=f"Reasignado automáticamente tras rechazo, con {minutos_extra} min extra")
                nuevo_status = "assigned"
            else:
                session.run(
                    """
                    MATCH (o:Order {id: $oid})
                    SET o.status = 'pending',
                        o.estimated_extra_minutes = null,
                        o.candidate_driver_ids = [],
                        o.current_candidate_idx = -1,
                        o.updated_at = datetime()
                    """,
                    {"oid": id_pedido},
                )
                registrar_evento_auditoria(session, id_pedido, 'revert_to_pending', details="Sin candidatos disponibles tras rechazo. Pedido vuelve a pendiente.")
                actualizado = _pedido_dict(session, id_pedido, None)
                actualizado["backhauling_candidates"] = []
                plan = _plan_vacio()
                nuevo_status = "pending"
                nuevo_driver_id = None

            actualizado["backhauling_candidates"] = candidatos

    await gestor.difundir_a_central(
        {
            "type": "pickup:response",
            "order_id": id_pedido,
            "driver_id": id_repartidor,
            "driver_name": driver_name,
            "accepted": accepted,
        }
    )

    if not accepted:
        if nuevo_status == "assigned" and nuevo_driver_id:
            await gestor.enviar_a_repartidor(
                nuevo_driver_id,
                {
                    "type": "pickup:notification",
                    "order": actualizado,
                    "extra_minutes": minutos_extra,
                },
            )
            await gestor.difundir_a_central(
                {
                    "type": "pickup:assigned_automatically",
                    "order_id": id_pedido,
                    "driver_id": nuevo_driver_id,
                    "extra_minutes": minutos_extra,
                    "candidates": candidatos,
                }
            )
        elif nuevo_status == "pending":
            await gestor.difundir_a_central(
                {"type": "pickup:pending", "order_id": id_pedido, "order": actualizado}
            )

    return {
        "order": actualizado,
        "extra_minutes": round(minutos_extra, 1),
        "total_minutes": plan["total_minutes"],
        "total_distance_km": plan["total_distance_km"],
        "route_order_ids": plan["order_ids"],
        "route_geometry": plan["route_geometry"],
        "leg_minutes": plan["leg_minutes"],
    }


def actualizar_estado_pedido(id_pedido: str, status: str, usuario_actual: dict) -> dict:
    with obtener_conexion() as session:
        result = _pedido_con_asignado(session, id_pedido)
        if not result:
            raise HTTPException(status_code=404, detail="Pedido no encontrado")

        driver_id = result["assigned_driver_id"]
        if usuario_actual["role"] == "repartidor" and driver_id != usuario_actual["id"]:
            raise HTTPException(status_code=403, detail="Este pedido no esta asignado a ti")

        session.run(
            "MATCH (o:Order {id: $oid}) SET o.status = $status, o.updated_at = datetime()",
            {"oid": id_pedido, "status": status},
        )

        if status == "completed" and driver_id:
            session.run(
                """
                MATCH (u:User {id: $uid})-[:HAS_ROUTE]->(r:Route {status: 'active'})
                SET r.completed_order_ids = coalesce(r.completed_order_ids, []) + [$oid]
                """,
                {"uid": driver_id, "oid": id_pedido}
            )

        action_name = "start_delivery" if status == "in_progress" else "complete"
        details_text = "Pedido marcado en curso" if status == "in_progress" else "Pedido completado con éxito"
        registrar_evento_auditoria(session, id_pedido, action_name, driver_id, details_text)

        plan = _plan_vacio()
        if driver_id:
            plan = plan_ruta_repartidor(session, driver_id)
            persistir_metricas_ruta(session, driver_id, plan)

        actualizado = _pedido_dict(session, id_pedido, driver_id)
        return {
            "order": actualizado,
            **plan,
            "route_order_ids": plan["order_ids"],
        }


def obtener_ruta_repartidor(id_repartidor: str) -> dict:
    with obtener_conexion() as session:
        ruta_record = session.run(
            "MATCH (u:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'}) RETURN r {.*, created_at: toString(r.created_at), updated_at: toString(r.updated_at)} AS r",
            {"id": id_repartidor},
        ).single()

        if not ruta_record:
            raise HTTPException(status_code=404, detail="No se encontro ruta activa")

        ruta = dict(ruta_record["r"])
        if not ruta.get("route_geometry"):
            plan = plan_ruta_repartidor(session, id_repartidor)
            persistir_metricas_ruta(session, id_repartidor, plan)
            ruta.update(plan)
        else:
            ruta.setdefault("order_ids", [])
            ruta.setdefault("total_minutes", 0.0)
            ruta.setdefault("total_distance_km", 0.0)
            ruta.setdefault("leg_minutes", [])

        ids_pedidos = ruta.get("order_ids") or []
        pedidos = []
        for pid in ids_pedidos:
            o_record = session.run(
                "MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o",
                {"id": pid},
            ).single()
            if o_record:
                pedido = dict(o_record["o"])
                pedido["assigned_driver_id"] = id_repartidor
                pedidos.append(pedido)

        geometry = ruta.get("route_geometry", [])
        if isinstance(geometry, str):
            geometry = json.loads(geometry)

        return {
            **ruta,
            "driver_id": id_repartidor,
            "order_ids": ids_pedidos,
            "orders": pedidos,
            "total_minutes": ruta.get("total_minutes", 0.0),
            "total_distance_km": ruta.get("total_distance_km", 0.0),
            "route_geometry": geometry,
            "leg_minutes": ruta.get("leg_minutes", []),
        }


async def asignar_desde_ws(id_pedido: str, id_repartidor: str) -> dict:
    return await asignar_pedido(id_pedido, id_repartidor)


async def responder_desde_ws(id_pedido: str, id_repartidor: str, accepted: bool) -> dict:
    return await responder_pedido(id_pedido, id_repartidor, accepted)


def contar_asignaciones_pedido(id_pedido: str) -> int:
    with obtener_conexion() as session:
        record = session.run(
            """
            MATCH (:User)-[r:ASSIGNED_TO]->(:Order {id: $oid})
            RETURN count(r) AS count
            """,
            {"oid": id_pedido},
        ).single()
        return int(record["count"] if record else 0)
