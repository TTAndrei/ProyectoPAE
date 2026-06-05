import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, HTTPException

from app.auth import decodificar_token
from app.database import obtener_conexion
from app.ws_manager import gestor
from app.services.order_workflow import asignar_desde_ws, responder_desde_ws

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

                try:
                    await asignar_desde_ws(id_pedido, id_repartidor)
                except HTTPException:
                    continue

            elif tipo_mensaje == "driver:pickup:response" and rol == "repartidor":
                id_pedido = mensaje.get("order_id")
                aceptado = mensaje.get("accepted")
                if not id_pedido or aceptado is None:
                    continue

                try:
                    await responder_desde_ws(id_pedido, id_usuario, bool(aceptado))
                except HTTPException:
                    continue

    except WebSocketDisconnect:
        if rol == "repartidor":
            gestor.desconectar_repartidor(id_usuario)
            await gestor.difundir_a_central({
                "type": "driver:offline",
                "driver_id": id_usuario,
            })
        else:
            gestor.desconectar_central(websocket)
