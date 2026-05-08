"""Router WebSocket para comunicación en tiempo real.

Canal único /ws?token=<jwt> que maneja tres tipos de mensajes:

Mensajes que envía el REPARTIDOR al servidor:
  { "type": "driver:location",       "lat": ..., "lng": ..., "heading": ... }
  { "type": "driver:pickup:response","order_id": "...", "accepted": true/false }

Mensajes que envía la CENTRAL al servidor:
  { "type": "central:pickup:notify", "order_id": "...", "driver_id": "..." }

Mensajes que el servidor envía a la CENTRAL:
  { "type": "driver:location:update","driver_id": ..., "name": ..., "lat": ..., "lng": ..., "heading": ... }
  { "type": "driver:offline",        "driver_id": ... }
  { "type": "pickup:response",       "order_id": ..., "driver_id": ..., "driver_name": ..., "accepted": ... }

Mensajes que el servidor envía al REPARTIDOR:
  { "type": "pickup:notification",   "order": {...}, "extra_minutes": ... }
"""
import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, HTTPException

from app.auth import decodificar_token
from app.database import obtener_conexion
from app.routing import calcular_tiempo_extra
from app.ws_manager import gestor

# Enrutador WebSocket (sin prefijo, el endpoint se llama /ws)
enrutador = APIRouter(tags=["websocket"])


@enrutador.websocket("/ws")
async def punto_websocket(websocket: WebSocket, token: str = Query(...)):
    """Endpoint WebSocket principal de la aplicación PAE."""
    # ── Autenticación ──────────────────────────────────────────────────────────
    try:
        usuario = decodificar_token(token)
    except HTTPException:
        # Token inválido → cerrar con código 1008 (Policy Violation)
        await websocket.close(code=1008)
        return

    id_usuario: str = usuario["id"]
    rol: str = usuario["role"]
    nombre: str = usuario["name"]

    # ── Registro de la conexión según rol ──────────────────────────────────────
    if rol == "repartidor":
        await gestor.conectar_repartidor(id_usuario, websocket)
    else:
        await gestor.conectar_central(websocket)

    try:
        # Bucle principal: espera mensajes del cliente
        while True:
            texto_raw = await websocket.receive_text()
            try:
                mensaje = json.loads(texto_raw)
            except json.JSONDecodeError:
                # Mensaje malformado → ignorar y continuar
                continue

            tipo_mensaje = mensaje.get("type")

            # ── Repartidor envía actualización de ubicación ────────────────────
            if tipo_mensaje == "driver:location" and rol == "repartidor":
                lat = mensaje.get("lat")
                lng = mensaje.get("lng")
                direccion = mensaje.get("heading", 0)

                # Validar que lat y lng sean números
                if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                    continue

                # Guardar la nueva posición en la base de datos (Neo4j)
                with obtener_conexion() as session:
                    session.run("""
                        MATCH (u:User {id: $id})
                        SET u.lat = $lat, u.lng = $lng, u.heading = $heading,
                            u.location_updated_at = datetime()
                    """, {"id": id_usuario, "lat": lat, "lng": lng, "heading": direccion})

                # Notificar a todos los operadores centrales la nueva posición
                await gestor.difundir_a_central({
                    "type": "driver:location:update",
                    "driver_id": id_usuario,
                    "name": nombre,
                    "lat": lat,
                    "lng": lng,
                    "heading": direccion,
                })

            # ── Central asigna una recogida a un repartidor ────────────────────
            elif tipo_mensaje == "central:pickup:notify" and rol == "central":
                id_pedido = mensaje.get("order_id")
                id_repartidor = mensaje.get("driver_id")
                if not id_pedido or not id_repartidor:
                    continue

                with obtener_conexion() as session:
                    res_pedido = session.run("MATCH (o:Order {id: $id}) RETURN o {.*, created_at: toString(o.created_at), updated_at: toString(o.updated_at)} AS o", {"id": id_pedido}).single()
                    if not res_pedido:
                        continue
                    fila_pedido = dict(res_pedido["o"])

                    # Obtener posición y ruta activa
                    res_rep = session.run("MATCH (u:User {id: $id}) RETURN u", {"id": id_repartidor}).single()
                    ubicacion_rep = res_rep["u"] if res_rep else None
                    
                    res_ruta = session.run(
                        "MATCH (u:User {id: $id})-[:HAS_ROUTE]->(r:Route {status: 'active'}) RETURN r {.*, created_at: toString(r.created_at), updated_at: toString(r.updated_at)} AS r",
                        {"id": id_repartidor}
                    ).single()
                    ruta_activa = res_ruta["r"] if res_ruta else None

                    # Calcular el tiempo extra del desvío
                    minutos_extra = 0.0
                    if ubicacion_rep and ubicacion_rep["lat"] is not None and ruta_activa:
                        ids_pedidos = ruta_activa["order_ids"]
                        paradas: list[dict] = []
                        if ids_pedidos:
                            for pid in ids_pedidos:
                                p_res = session.run(
                                    "MATCH (o:Order {id: $id}) WHERE NOT o.status IN ['completed','rejected'] RETURN o.lat AS lat, o.lng AS lng",
                                    {"id": pid}
                                ).single()
                                if p_res:
                                    paradas.append(dict(p_res))
                        
                        resultado = calcular_tiempo_extra(
                            paradas,
                            {"lat": ubicacion_rep["lat"], "lng": ubicacion_rep["lng"]},
                            {"lat": fila_pedido["lat"], "lng": fila_pedido["lng"]},
                        )
                        minutos_extra = resultado["extra_minutos"]

                    # Actualizar el pedido en Neo4j
                    session.run(
                        """
                        MATCH (o:Order {id: $oid}), (u:User {id: $uid})
                        SET o.status = 'assigned', 
                            o.estimated_extra_minutes = $minutos,
                            o.updated_at = datetime()
                        MERGE (u)-[:ASSIGNED_TO]->(o)
                        """,
                        {"oid": id_pedido, "uid": id_repartidor, "minutos": minutos_extra},
                    )

                    # Enviar la notificación al repartidor
                    fila_pedido["assigned_driver_id"] = id_repartidor
                    await gestor.enviar_a_repartidor(id_repartidor, {
                        "type": "pickup:notification",
                        "order": fila_pedido,
                        "extra_minutes": minutos_extra,
                    })

            # ── Repartidor responde a una notificación de recogida ─────────────
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
                        {"oid": id_pedido}
                    ).single()
                    
                    if not res_pedido or res_pedido["driver_id"] != id_usuario:
                        continue

                    # Actualizar estado
                    nuevo_estado = "in_progress" if aceptado else "rejected"
                    session.run(
                        "MATCH (o:Order {id: $oid}) SET o.status = $status, o.updated_at = datetime()",
                        {"oid": id_pedido, "status": nuevo_estado}
                    )

                    # Si aceptó, añadir a la ruta
                    if aceptado:
                        session.run(
                            """
                            MATCH (u:User {id: $uid})-[:HAS_ROUTE]->(r:Route {status: 'active'})
                            WHERE NOT $oid IN r.order_ids
                            SET r.order_ids = r.order_ids + $oid, r.updated_at = datetime()
                            """,
                            {"uid": id_usuario, "oid": id_pedido}
                        )

                # Informar a la central
                await gestor.difundir_a_central({
                    "type": "pickup:response",
                    "order_id": id_pedido,
                    "driver_id": id_usuario,
                    "driver_name": nombre,
                    "accepted": aceptado,
                })

    except WebSocketDisconnect:
        # ── Limpieza al desconectarse ──────────────────────────────────────────
        if rol == "repartidor":
            gestor.desconectar_repartidor(id_usuario)
            await gestor.difundir_a_central({
                "type": "driver:offline",
                "driver_id": id_usuario,
            })
        else:
            gestor.desconectar_central(websocket)
