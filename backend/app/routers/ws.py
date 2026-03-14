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
    """Endpoint WebSocket principal de la aplicación PAE.

    El cliente debe autenticarse enviando su token JWT como parámetro de consulta:
      ws://localhost:8000/ws?token=<jwt>

    Una vez conectado, el servidor gestiona el ciclo de vida automáticamente:
    - Los repartidores se registran en el gestor y emiten su ubicación
    - Los operadores centrales reciben actualizaciones de todos los repartidores
    - Al desconectarse, se notifica a la central
    """
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

                # Guardar la nueva posición en la base de datos
                conexion = obtener_conexion()
                conexion.execute(
                    """
                    INSERT INTO driver_locations (driver_id, lat, lng, heading, updated_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                    ON CONFLICT(driver_id) DO UPDATE SET
                        lat = excluded.lat,
                        lng = excluded.lng,
                        heading = excluded.heading,
                        updated_at = excluded.updated_at
                    """,
                    (id_usuario, lat, lng, direccion),
                )
                conexion.commit()

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

                conexion = obtener_conexion()
                fila_pedido = conexion.execute(
                    "SELECT * FROM orders WHERE id = ?", (id_pedido,)
                ).fetchone()
                if not fila_pedido:
                    continue

                # Obtener posición actual y ruta activa del repartidor
                ubicacion_rep = conexion.execute(
                    "SELECT * FROM driver_locations WHERE driver_id = ?", (id_repartidor,)
                ).fetchone()
                ruta_activa = conexion.execute(
                    "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
                    (id_repartidor,),
                ).fetchone()

                # Calcular el tiempo extra del desvío
                minutos_extra = 0.0
                if ubicacion_rep and ruta_activa:
                    ids_pedidos = json.loads(ruta_activa["order_ids"])
                    paradas: list[dict] = []
                    if ids_pedidos:
                        marcadores = ",".join("?" * len(ids_pedidos))
                        paradas = [
                            {"lat": fila["lat"], "lng": fila["lng"]}
                            for fila in conexion.execute(
                                f"SELECT lat, lng FROM orders "
                                f"WHERE id IN ({marcadores}) "
                                f"AND status NOT IN ('completed','rejected')",
                                ids_pedidos,
                            ).fetchall()
                        ]
                    resultado = calcular_tiempo_extra(
                        paradas,
                        {"lat": ubicacion_rep["lat"], "lng": ubicacion_rep["lng"]},
                        {"lat": fila_pedido["lat"], "lng": fila_pedido["lng"]},
                    )
                    minutos_extra = resultado["extra_minutos"]

                # Actualizar el pedido en la BD con el repartidor y el tiempo estimado
                conexion.execute(
                    """
                    UPDATE orders
                    SET assigned_driver_id = ?, estimated_extra_minutes = ?,
                        status = 'assigned', updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (id_repartidor, minutos_extra, id_pedido),
                )
                conexion.commit()

                # Enviar la notificación de recogida al repartidor seleccionado
                await gestor.enviar_a_repartidor(id_repartidor, {
                    "type": "pickup:notification",
                    "order": dict(fila_pedido),
                    "extra_minutes": minutos_extra,
                })

            # ── Repartidor responde a una notificación de recogida ─────────────
            elif tipo_mensaje == "driver:pickup:response" and rol == "repartidor":
                id_pedido = mensaje.get("order_id")
                aceptado = mensaje.get("accepted")
                if not id_pedido or aceptado is None:
                    continue

                conexion = obtener_conexion()
                fila_pedido = conexion.execute(
                    "SELECT * FROM orders WHERE id = ?", (id_pedido,)
                ).fetchone()
                # Solo procesar si el pedido existe y está asignado a este repartidor
                if not fila_pedido or fila_pedido["assigned_driver_id"] != id_usuario:
                    continue

                # Actualizar el estado del pedido según la respuesta
                nuevo_estado = "in_progress" if aceptado else "rejected"
                conexion.execute(
                    "UPDATE orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
                    (nuevo_estado, id_pedido),
                )

                # Si aceptó, añadir la recogida a su ruta activa
                if aceptado:
                    ruta_activa = conexion.execute(
                        "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
                        (id_usuario,),
                    ).fetchone()
                    if ruta_activa:
                        ids = json.loads(ruta_activa["order_ids"])
                        if id_pedido not in ids:
                            ids.append(id_pedido)
                            conexion.execute(
                                "UPDATE routes SET order_ids = ?, updated_at = datetime('now') WHERE id = ?",
                                (json.dumps(ids), ruta_activa["id"]),
                            )

                conexion.commit()

                # Informar a la central del resultado de la notificación
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
            # Notificar a la central que el repartidor se desconectó
            await gestor.difundir_a_central({
                "type": "driver:offline",
                "driver_id": id_usuario,
            })
        else:
            gestor.desconectar_central(websocket)
