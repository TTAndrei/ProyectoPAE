"""Router de pedidos/recogidas: CRUD y gestión del ciclo de vida.

Endpoints:
  GET    /orders/                    → Lista pedidos (Central: todos; Repartidor: propios + pendientes)
  POST   /orders/                    → Crea un nuevo pedido (solo Central)
  POST   /orders/{id}/assign         → Asigna un pedido a un repartidor + calcula tiempo extra
  POST   /orders/{id}/respond        → Repartidor acepta o rechaza una recogida
  PATCH  /orders/{id}/status         → Actualiza el estado de un pedido
  GET    /orders/route/{id_repartidor} → Devuelve la ruta activa de un repartidor
"""
import json
import uuid
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import (
    CrearPedido, AsignarPedido, ResponderPedido,
    ActualizarEstadoPedido, PedidoRespuesta, RutaRespuesta,
)
from app.auth import obtener_usuario_actual, requerir_central
from app.config import OSRM_ACTIVO, OSRM_BASE_URL, OSRM_TIMEOUT_SEGUNDOS
from app.routing import calcular_tiempo_extra, optimizar_ruta_vial

# Enrutador de pedidos con prefijo /orders
enrutador = APIRouter(prefix="/orders", tags=["pedidos"])


def _obtener_posicion_repartidor(session, id_repartidor: str) -> dict | None:
    """Devuelve la ubicación actual del repartidor o None si no existe."""
    result = session.run(
        "MATCH (u:User {id: $id}) RETURN u.lat AS lat, u.lng AS lng",
        {"id": id_repartidor},
    )
    record = result.single()
    if not record or record["lat"] is None:
        return None
    return {"lat": record["lat"], "lng": record["lng"]}


def _obtener_paradas_activas(session, id_repartidor: str) -> list[dict]:
    """Obtiene pedidos activos del repartidor aptos para cálculo de ruta."""
    result = session.run(
        """
        MATCH (u:User {id: $id})-[:ASSIGNED_TO]->(o:Order)
        WHERE o.status IN ('assigned','in_progress')
        RETURN o.id AS id, o.lat AS lat, o.lng AS lng
        """,
        {"id": id_repartidor},
    )
    return [record.data() for record in result]


def _plan_ruta_repartidor(session, id_repartidor: str) -> dict:
    """Calcula orden óptimo y métricas de ruta activa del repartidor."""
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
        # Fallback para no bloquear el algoritmo cuando todavía no hay GPS.
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


def _persistir_orden_ruta_activa(session, id_repartidor: str, order_ids: list[str]) -> None:
    """Guarda en el nodo Route el orden optimizado actual."""
    session.run(
        """
        MATCH (u:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'})
        SET r.order_ids = $order_ids, r.updated_at = datetime()
        """,
        {"id": id_repartidor, "order_ids": order_ids},
    )


@enrutador.get("/", response_model=list[PedidoRespuesta])
def listar_pedidos(usuario_actual: dict = Depends(obtener_usuario_actual)):
    """Devuelve la lista de pedidos según el rol del usuario."""
    with obtener_conexion() as session:
        if usuario_actual["role"] == "central":
            # Central: vista completa del sistema
            result = session.run("MATCH (o:Order) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o ORDER BY o.created_at DESC")
        else:
            # Repartidor: sus pedidos asignados + recogidas pendientes disponibles
            result = session.run(
                """
                MATCH (o:Order)
                OPTIONAL MATCH (u:User {id: $uid})-[:ASSIGNED_TO]->(o)
                WHERE u IS NOT NULL OR o.status = 'pending'
                RETURN DISTINCT o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o
                ORDER BY o.created_at DESC
                """,
                {"uid": usuario_actual["id"]},
            )
        
        pedidos = []
        for record in result:
            o = record["o"]
            pedido_dict = dict(o)
            # Neo4j no tiene claves foráneas de la misma forma, buscamos la relación
            assign_result = session.run(
                "MATCH (u:User)-[:ASSIGNED_TO]->(o:Order {id: $oid}) RETURN u.id AS uid",
                {"oid": o["id"]}
            ).single()
            pedido_dict["assigned_driver_id"] = assign_result["uid"] if assign_result else None
            pedidos.append(pedido_dict)
        return pedidos


@enrutador.post("/", response_model=PedidoRespuesta, status_code=status.HTTP_201_CREATED)
def crear_pedido(cuerpo: CrearPedido, _: dict = Depends(requerir_central)):
    """Crea un nuevo pedido o recogida."""
    id_pedido = str(uuid.uuid4())
    with obtener_conexion() as session:
        session.run(
            """
            CREATE (o:Order {
                id: $id, 
                type: $type, 
                address: $address, 
                lat: $lat, 
                lng: $lng, 
                status: 'pending',
                created_at: datetime(),
                updated_at: datetime()
            })
            """,
            {"id": id_pedido, "type": cuerpo.type, "address": cuerpo.address, "lat": cuerpo.lat, "lng": cuerpo.lng},
        )
        record = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": id_pedido}).single()
        return record["o"]


@enrutador.post("/{id_pedido}/assign")
def asignar_pedido(
    id_pedido: str,
    cuerpo: AsignarPedido,
    _: dict = Depends(requerir_central),
):
    """Asigna un pedido a un repartidor."""
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
                posicion_repartidor = {"lat": pedido["lat"], "lng": pedido["lng"]}

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
        _persistir_orden_ruta_activa(session, cuerpo.driver_id, plan["order_ids"])

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
    """El repartidor acepta o rechaza una recogida."""
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
        _persistir_orden_ruta_activa(session, usuario_actual["id"], plan["order_ids"])

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
            _persistir_orden_ruta_activa(session, driver_id, plan["order_ids"])
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
    """Devuelve la ruta activa de un repartidor."""
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
        
        ruta = ruta_record["r"]
        plan = _plan_ruta_repartidor(session, id_repartidor)
        ids_pedidos = plan["order_ids"]
        _persistir_orden_ruta_activa(session, id_repartidor, ids_pedidos)

        pedidos = []
        if ids_pedidos:
            for pid in ids_pedidos:
                o_record = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": pid}).single()
                if o_record:
                    o_dict = o_record["o"]
                    o_dict["assigned_driver_id"] = id_repartidor
                    pedidos.append(o_dict)

        return {
            **dict(ruta),
            "order_ids": json.dumps(ids_pedidos),
            "orders": pedidos,
            "total_minutes": plan["total_minutes"],
            "total_distance_km": plan["total_distance_km"],
            "route_geometry": plan["route_geometry"],
            "leg_minutes": plan["leg_minutes"],
        }
