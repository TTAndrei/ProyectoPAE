import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, HTTPException

from app.auth import decodificar_token
from app.database import obtener_conexion
from app.routing import calcular_tiempo_extra, detectar_candidatos_backhauling
from app.ws_manager import gestor
from app.routers.orders import _plan_ruta_repartidor, _persistir_metricas_ruta, _obtener_repartidores_activos_con_paradas_para_pedido

enrutador = APIRouter(tags=["websocket"])


@enrutador.websocket("/ws")
async def punto_websocket(websocket: WebSocket, token: str = Query(...)):
    try:
        usuario = decodificar_token(token)
    except HTTPException:
        await websocket.close(code=1008)
        return

    id_usuario: str = usuario["id"]
    rol: str = usuario["role"]
    nombre: str = usuario["name"]

    if rol == "repartidor":
        await gestor.conectar_repartidor(id_usuario, websocket)
    else:
        await gestor.conectar_central(websocket)

    try:
        while True:
            texto_raw = await websocket.receive_text()
            try:
                mensaje = json.loads(texto_raw)
            except json.JSONDecodeError:
                continue

            tipo_mensaje = mensaje.get("type")

            if tipo_mensaje == "driver:location" and rol == "repartidor":
                lat = mensaje.get("lat")
                lng = mensaje.get("lng")
                direccion = mensaje.get("heading", 0)

                if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                    continue

                with obtener_conexion() as session:
                    session.run("""
                        MATCH (u:User {id: $id})
                        SET u.lat = $lat, u.lng = $lng, u.heading = $heading,
                            u.location_updated_at = datetime()
                    """, {"id": id_usuario, "lat": lat, "lng": lng, "heading": direccion})

                await gestor.difundir_a_central({
                    "type": "driver:location:update",
                    "driver_id": id_usuario,
                    "name": nombre,
                    "lat": lat,
                    "lng": lng,
                    "heading": direccion,
                })

            elif tipo_mensaje == "central:pickup:notify" and rol == "central":
                id_pedido = mensaje.get("order_id")
                id_repartidor = mensaje.get("driver_id")
                if not id_pedido or not id_repartidor:
                    continue

                with obtener_conexion() as session:
                    res_pedido = session.run(
                        "MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o",
                        {"id": id_pedido},
                    ).single()
                    if not res_pedido:
                        continue
                    fila_pedido = dict(res_pedido["o"])

                    res_rep = session.run("MATCH (u:User {id: $id}) RETURN u", {"id": id_repartidor}).single()
                    ubicacion_rep = res_rep["u"] if res_rep else None

                    res_ruta = session.run(
                        "MATCH (u:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'}) RETURN r {.*, created_at: toString(r.created_at), updated_at: toString(r.updated_at)} AS r",
                        {"id": id_repartidor},
                    ).single()
                    ruta_activa = res_ruta["r"] if res_ruta else None

                    minutos_extra = 0.0
                    if ubicacion_rep and ubicacion_rep["lat"] is not None and ruta_activa:
                        ids_pedidos = ruta_activa["order_ids"]
                        paradas: list[dict] = []
                        if ids_pedidos:
                            for pid in ids_pedidos:
                                p_res = session.run(
                                    "MATCH (o:Order {id: $id}) WHERE NOT o.status IN ['completed','rejected'] RETURN o.lat AS lat, o.lng AS lng",
                                    {"id": pid},
                                ).single()
                                if p_res:
                                    paradas.append(dict(p_res))

                        resultado = calcular_tiempo_extra(
                            paradas,
                            {"lat": ubicacion_rep["lat"], "lng": ubicacion_rep["lng"]},
                            {"lat": fila_pedido["lat"], "lng": fila_pedido["lng"]},
                        )
                        minutos_extra = resultado["extra_minutos"]

                    # Calcular todos los candidatos para persistir la lista secuencial
                    repartidores = _obtener_repartidores_activos_con_paradas_para_pedido(session, id_pedido)
                    candidatos_todos = detectar_candidatos_backhauling(
                        {"lat": fila_pedido["lat"], "lng": fila_pedido["lng"]},
                        repartidores,
                    )
                    candidate_ids = [id_repartidor] + [
                        c["driver_id"] for c in candidatos_todos if c["driver_id"] != id_repartidor
                    ]

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

                    fila_pedido["assigned_driver_id"] = id_repartidor
                    await gestor.enviar_a_repartidor(id_repartidor, {
                        "type": "pickup:notification",
                        "order": fila_pedido,
                        "extra_minutes": minutos_extra,
                    })

            elif tipo_mensaje == "driver:pickup:response" and rol == "repartidor":
                id_pedido = mensaje.get("order_id")
                aceptado = mensaje.get("accepted")
                if not id_pedido or aceptado is None:
                    continue

                with obtener_conexion() as session:
                    res_pedido = session.run(
                        """
                        MATCH (o:Order {id: $oid})
                        OPTIONAL MATCH (u:User)-[:ASSIGNED_TO]->(o)
                        RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o, u.id AS driver_id
                        """,
                        {"oid": id_pedido},
                    ).single()

                    if not res_pedido or res_pedido["driver_id"] != id_usuario:
                        continue

                    nuevo_estado = "in_progress" if aceptado else "rejected"
                    session.run(
                        "MATCH (o:Order {id: $oid}) SET o.status = $status, o.updated_at = datetime()",
                        {"oid": id_pedido, "status": nuevo_estado},
                    )

                    if aceptado:
                        plan = _plan_ruta_repartidor(session, id_usuario)
                        _persistir_metricas_ruta(session, id_usuario, plan)

                await gestor.difundir_a_central({
                    "type": "pickup:response",
                    "order_id": id_pedido,
                    "driver_id": id_usuario,
                    "driver_name": nombre,
                    "accepted": aceptado,
                })

    except WebSocketDisconnect:
        if rol == "repartidor":
            gestor.desconectar_repartidor(id_usuario)
            await gestor.difundir_a_central({
                "type": "driver:offline",
                "driver_id": id_usuario,
            })
        else:
            gestor.desconectar_central(websocket)
