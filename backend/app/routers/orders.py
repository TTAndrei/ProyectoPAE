import uuid
import json
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import (
    CrearPedido, AsignarPedido, ResponderPedido,
    ActualizarEstadoPedido, PedidoRespuesta, RutaRespuesta,
)
from app.auth import obtener_usuario_actual, requerir_central
from app.config import OSRM_ACTIVO, OSRM_BASE_URL, OSRM_TIMEOUT_SEGUNDOS
from app.routing import calcular_tiempo_extra, optimizar_ruta_vial, detectar_candidatos_backhauling
from app.ws_manager import gestor

enrutador = APIRouter(prefix="/orders", tags=["pedidos"])


def _obtener_posicion_repartidor(session, id_repartidor: str) -> dict | None:
    result = session.run(
        "MATCH (u:User {id: $id}) RETURN u.lat AS lat, u.lng AS lng",
        {"id": id_repartidor},
    )
    record = result.single()
    if not record or record["lat"] is None:
        return None
    return {"lat": record["lat"], "lng": record["lng"]}


def _obtener_paradas_activas(session, id_repartidor: str) -> list[dict]:
    result = session.run(
        """
        MATCH (u:User {id: $id})-[:ASSIGNED_TO]->(o:Order)
        WHERE o.status IN $statuses
        RETURN o.id AS id, o.lat AS lat, o.lng AS lng
        """,
        {"id": id_repartidor, "statuses": ["assigned", "in_progress"]},
    )
    return [record.data() for record in result]


def _obtener_repartidores_activos_con_paradas(session) -> list[dict]:
    result = session.run("""
        MATCH (u:User {role: 'repartidor'})
        WHERE u.lat IS NOT NULL
        OPTIONAL MATCH (u)-[:ASSIGNED_TO]->(o:Order)
        WHERE o.status IN ["assigned", "in_progress"]
        RETURN u.id AS id, u.lat AS lat, u.lng AS lng,
               collect({id: o.id, lat: o.lat, lng: o.lng}) AS paradas_activas
    """)
    return [dict(r) for r in result]


def _plan_ruta_repartidor(session, id_repartidor: str) -> dict:
    paradas = _obtener_paradas_activas(session, id_repartidor)
    if not paradas:
        return {
            "order_ids": [],
            "total_minutes": 0.0,
            "total_distance_km": 0.0,
            "route_geometry": [],
            "leg_minutes": [],
        }

    posicion = _obtener_posicion_repartidor(session, id_repartidor)
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


def _persistir_metricas_ruta(session, id_repartidor: str, plan: dict) -> None:
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


@enrutador.get("/", response_model=list[PedidoRespuesta])
def listar_pedidos(usuario_actual: dict = Depends(obtener_usuario_actual)):
    with obtener_conexion() as session:
        if usuario_actual["role"] == "central":
            result = session.run(
                """
                MATCH (o:Order)
                OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
                RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o,
                       u.id AS assigned_driver_id
                ORDER BY o.created_at DESC
                """
            )
        else:
            result = session.run(
                """
                MATCH (o:Order)
                OPTIONAL MATCH (asignado_a_mi:User {id: $uid})-[:ASSIGNED_TO]->(o)
                WHERE asignado_a_mi IS NOT NULL OR o.status = 'pending'
                WITH DISTINCT o
                OPTIONAL MATCH (asignado:User)-[:ASSIGNED_TO]->(o)
                RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o,
                       asignado.id AS assigned_driver_id
                ORDER BY o.created_at DESC
                """,
                {"uid": usuario_actual["id"]},
            )

        pedidos = []
        for record in result:
            pedido_dict = dict(record["o"])
            pedido_dict["assigned_driver_id"] = record["assigned_driver_id"]
            pedidos.append(pedido_dict)
        return pedidos


@enrutador.post("/", response_model=PedidoRespuesta, status_code=status.HTTP_201_CREATED)
async def crear_pedido(cuerpo: CrearPedido, _: dict = Depends(requerir_central)):
    id_pedido = str(uuid.uuid4())
    with obtener_conexion() as session:
        session.run(
            """
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
            """,
            {"id": id_pedido, "type": cuerpo.type, "name": cuerpo.name, "address": cuerpo.address, "lat": cuerpo.lat, "lng": cuerpo.lng},
        )
        record = session.run(
            "MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o",
            {"id": id_pedido},
        ).single()
        resp = dict(record["o"])
        resp["assigned_driver_id"] = None

        candidatos = []
        if cuerpo.type == "pickup":
            repartidores = _obtener_repartidores_activos_con_paradas(session)
            candidatos = detectar_candidatos_backhauling(
                {"lat": cuerpo.lat, "lng": cuerpo.lng},
                repartidores,
                osrm_base_url=OSRM_BASE_URL if OSRM_ACTIVO else None,
                timeout_seconds=OSRM_TIMEOUT_SEGUNDOS,
            )
        resp["backhauling_candidates"] = candidatos

    # Push WS fuera del bloque DB para no mantener la sesión abierta
    if candidatos:
        for c in candidatos:
            await gestor.enviar_a_repartidor(c["driver_id"], {
                "type": "pickup:suggestion",
                "order_id": id_pedido,
                "order": resp,
                "extra_minutes": c["extra_minutos"],
                "indice_insercion": c["indice_insercion"],
            })
        await gestor.difundir_a_central({
            "type": "backhauling:candidates",
            "order_id": id_pedido,
            "candidates": candidatos,
        })

    return resp


@enrutador.post("/{id_pedido}/assign")
def asignar_pedido(
    id_pedido: str,
    cuerpo: AsignarPedido,
    _: dict = Depends(requerir_central),
):
    with obtener_conexion() as session:
        record = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": id_pedido}).single()
        if not record:
            raise HTTPException(status_code=404, detail="Pedido no encontrado")
        pedido = record["o"]

        posicion_repartidor = _obtener_posicion_repartidor(session, cuerpo.driver_id)
        paradas_activas = _obtener_paradas_activas(session, cuerpo.driver_id)

        if not posicion_repartidor:
            if paradas_activas:
                posicion_repartidor = {
                    "lat": paradas_activas[0]["lat"],
                    "lng": paradas_activas[0]["lng"],
                }
            else:
                posicion_repartidor = {"lat": 40.4168, "lng": -3.7038}

        resultado = calcular_tiempo_extra(
            paradas_activas,
            posicion_repartidor,
            {"id": id_pedido, "lat": pedido["lat"], "lng": pedido["lng"]},
            osrm_base_url=OSRM_BASE_URL if OSRM_ACTIVO else None,
            timeout_seconds=OSRM_TIMEOUT_SEGUNDOS,
        )
        minutos_extra = resultado["extra_minutos"]

        # Actualizar el pedido y crear relación de asignación
        session.run(
            """
            MATCH (o:Order {id: $oid}), (u:User {id: $uid})
            SET o.status = 'assigned', 
                o.estimated_extra_minutes = $minutos,
                o.updated_at = datetime()
            MERGE (u)-[:ASSIGNED_TO]->(o)
            """,
            {"oid": id_pedido, "uid": cuerpo.driver_id, "minutos": minutos_extra},
        )
        
        plan = _plan_ruta_repartidor(session, cuerpo.driver_id)
        _persistir_metricas_ruta(session, cuerpo.driver_id, plan)

        actualizado_record = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": id_pedido}).single()
        actualizado_dict = actualizado_record["o"]
        actualizado_dict["assigned_driver_id"] = cuerpo.driver_id

        return {
            "order": actualizado_dict,
            "extra_minutes": minutos_extra,
            "total_minutes": plan["total_minutes"],
            "total_distance_km": plan["total_distance_km"],
            "route_order_ids": plan["order_ids"],
            "route_geometry": plan["route_geometry"],
            "leg_minutes": plan["leg_minutes"],
        }


@enrutador.post("/{id_pedido}/respond")
def responder_pedido(
    id_pedido: str,
    cuerpo: ResponderPedido,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    if usuario_actual["role"] != "repartidor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo los repartidores pueden responder a pedidos",
        )

    with obtener_conexion() as session:
        result = session.run(
            """
            MATCH (o:Order {id: $oid})
            OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
            RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o, u.id AS assigned_driver_id
            """,
            {"oid": id_pedido}
        ).single()
        
        if not result:
            raise HTTPException(status_code=404, detail="Pedido no encontrado")
        
        pedido = result["o"]
        if result["assigned_driver_id"] != usuario_actual["id"]:
            raise HTTPException(status_code=403, detail="Este pedido no está asignado a ti")

        minutos_extra = float(pedido.get("estimated_extra_minutes") or 0.0) if cuerpo.accepted else 0.0
        nuevo_status = "in_progress" if cuerpo.accepted else "rejected"

        session.run(
            "MATCH (o:Order {id: $oid}) SET o.status = $status, o.updated_at = datetime()",
            {"oid": id_pedido, "status": nuevo_status}
        )

        plan = _plan_ruta_repartidor(session, usuario_actual["id"])
        _persistir_metricas_ruta(session, usuario_actual["id"], plan)

        actualizado = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": id_pedido}).single()["o"]
        actualizado["assigned_driver_id"] = usuario_actual["id"]
        
        return {
            "order": actualizado,
            "extra_minutes": round(minutos_extra, 1),
            "total_minutes": plan["total_minutes"],
            "total_distance_km": plan["total_distance_km"],
            "route_order_ids": plan["order_ids"],
            "route_geometry": plan["route_geometry"],
            "leg_minutes": plan["leg_minutes"],
        }


@enrutador.patch("/{id_pedido}/status")
def actualizar_estado_pedido(
    id_pedido: str,
    cuerpo: ActualizarEstadoPedido,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Actualiza el estado de un pedido."""
    with obtener_conexion() as session:
        result = session.run(
            """
            MATCH (o:Order {id: $oid})
            OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
            RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o, u.id AS assigned_driver_id
            """,
            {"oid": id_pedido}
        ).single()

        if not result:
            raise HTTPException(status_code=404, detail="Pedido no encontrado")
        
        pedido = result["o"]
        driver_id = result["assigned_driver_id"]

        if usuario_actual["role"] == "repartidor" and driver_id != usuario_actual["id"]:
            raise HTTPException(status_code=403, detail="Este pedido no está asignado a ti")

        session.run(
            "MATCH (o:Order {id: $oid}) SET o.status = $status, o.updated_at = datetime()",
            {"oid": id_pedido, "status": cuerpo.status}
        )

        plan_data = {
            "total_minutes": 0.0,
            "total_distance_km": 0.0,
            "order_ids": [],
            "route_geometry": [],
            "leg_minutes": [],
        }
        if driver_id:
            plan = _plan_ruta_repartidor(session, driver_id)
            _persistir_metricas_ruta(session, driver_id, plan)
            plan_data = plan

        actualizado = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": id_pedido}).single()["o"]
        actualizado["assigned_driver_id"] = driver_id

        return {
            "order": actualizado,
            **plan_data,
            "route_order_ids": plan_data["order_ids"]
        }


@enrutador.get("/route/{id_repartidor}", response_model=RutaRespuesta)
def obtener_ruta_repartidor(
    id_repartidor: str,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    if usuario_actual["role"] != "central" and (
        usuario_actual["role"] != "repartidor" or usuario_actual["id"] != id_repartidor
    ):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    with obtener_conexion() as session:
        ruta_record = session.run(
            "MATCH (u:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'}) RETURN r {.*, created_at: toString(r.created_at), updated_at: toString(r.updated_at)} AS r",
            {"id": id_repartidor},
        ).single()

        if not ruta_record:
            raise HTTPException(status_code=404, detail="No se encontró ruta activa")

        ruta = dict(ruta_record["r"])

        # Usar métricas cacheadas; solo recalcular si faltan (primera vez o datos obsoletos)
        if not ruta.get("route_geometry"):
            plan = _plan_ruta_repartidor(session, id_repartidor)
            _persistir_metricas_ruta(session, id_repartidor, plan)
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
                o_dict = dict(o_record["o"])
                o_dict["assigned_driver_id"] = id_repartidor
                pedidos.append(o_dict)

        return {
            **ruta,
            "driver_id": id_repartidor,
            "order_ids": ids_pedidos,
            "orders": pedidos,
            "total_minutes": ruta.get("total_minutes", 0.0),
            "total_distance_km": ruta.get("total_distance_km", 0.0),
            "route_geometry": json.loads(ruta["route_geometry"]) if isinstance(ruta.get("route_geometry"), str) else ruta.get("route_geometry", []),
            "leg_minutes": ruta.get("leg_minutes", []),
        }
