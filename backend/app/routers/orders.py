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
from app.routing import calcular_tiempo_extra

# Enrutador de pedidos con prefijo /orders
enrutador = APIRouter(prefix="/orders", tags=["pedidos"])


def _fila_a_pedido(fila) -> dict:
    """Convierte una fila SQLite en un diccionario Python."""
    return dict(fila)


@enrutador.get("/", response_model=list[PedidoRespuesta])
def listar_pedidos(usuario_actual: dict = Depends(obtener_usuario_actual)):
    """Devuelve la lista de pedidos según el rol del usuario.

    - Central: ve TODOS los pedidos del sistema.
    - Repartidor: ve solo sus pedidos asignados + las recogidas pendientes de asignación.
    """
    conexion = obtener_conexion()
    if usuario_actual["role"] == "central":
        # Central: vista completa del sistema
        filas = conexion.execute(
            "SELECT * FROM orders ORDER BY created_at DESC"
        ).fetchall()
    else:
        # Repartidor: sus pedidos asignados + recogidas pendientes disponibles
        filas = conexion.execute(
            """
            SELECT * FROM orders
            WHERE assigned_driver_id = ? OR status = 'pending'
            ORDER BY created_at DESC
            """,
            (usuario_actual["id"],),
        ).fetchall()
    return [_fila_a_pedido(fila) for fila in filas]


@enrutador.post("/", response_model=PedidoRespuesta, status_code=status.HTTP_201_CREATED)
def crear_pedido(cuerpo: CrearPedido, _: dict = Depends(requerir_central)):
    """Crea un nuevo pedido o recogida con estado 'pending' (pendiente).

    Solo accesible para operadores centrales.
    El ID se genera automáticamente como UUID v4.
    """
    id_pedido = str(uuid.uuid4())
    conexion = obtener_conexion()
    conexion.execute(
        "INSERT INTO orders (id, type, address, lat, lng, status) VALUES (?,?,?,?,?,?)",
        (id_pedido, cuerpo.type, cuerpo.address, cuerpo.lat, cuerpo.lng, "pending"),
    )
    conexion.commit()
    fila = conexion.execute("SELECT * FROM orders WHERE id = ?", (id_pedido,)).fetchone()
    return _fila_a_pedido(fila)


@enrutador.post("/{id_pedido}/assign")
def asignar_pedido(
    id_pedido: str,
    cuerpo: AsignarPedido,
    _: dict = Depends(requerir_central),
):
    """Asigna un pedido pendiente a un repartidor y calcula el tiempo extra.

    Proceso:
      1. Obtiene la posición actual del repartidor
      2. Obtiene las paradas pendientes de la ruta activa del repartidor
      3. Calcula el tiempo extra usando el algoritmo de inserción óptima
      4. Actualiza el estado del pedido a 'assigned' con el tiempo estimado

    Returns:
        Pedido actualizado + tiempo extra estimado en minutos.
    """
    conexion = obtener_conexion()
    pedido = conexion.execute(
        "SELECT * FROM orders WHERE id = ?", (id_pedido,)
    ).fetchone()
    if not pedido:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")

    # Obtener posición actual del repartidor
    ubicacion_repartidor = conexion.execute(
        "SELECT * FROM driver_locations WHERE driver_id = ?", (cuerpo.driver_id,)
    ).fetchone()

    # Obtener la ruta activa del repartidor
    ruta_activa = conexion.execute(
        "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
        (cuerpo.driver_id,),
    ).fetchone()

    # Calcular el tiempo extra de desvío si hay ubicación y ruta disponibles
    minutos_extra = 0.0
    if ubicacion_repartidor and ruta_activa:
        ids_pedidos = json.loads(ruta_activa["order_ids"])
        paradas: list[dict] = []
        if ids_pedidos:
            marcadores = ",".join("?" * len(ids_pedidos))
            paradas = [
                dict(fila)
                for fila in conexion.execute(
                    f"SELECT lat, lng FROM orders "
                    f"WHERE id IN ({marcadores}) "
                    f"AND status NOT IN ('completed','rejected')",
                    ids_pedidos,
                ).fetchall()
            ]
        resultado = calcular_tiempo_extra(
            paradas,
            {"lat": ubicacion_repartidor["lat"], "lng": ubicacion_repartidor["lng"]},
            {"lat": pedido["lat"], "lng": pedido["lng"]},
        )
        minutos_extra = resultado["extra_minutos"]

    # Actualizar el pedido con el repartidor asignado y el tiempo estimado
    conexion.execute(
        """
        UPDATE orders
        SET assigned_driver_id = ?, status = 'assigned',
            estimated_extra_minutes = ?, updated_at = datetime('now')
        WHERE id = ?
        """,
        (cuerpo.driver_id, minutos_extra, id_pedido),
    )
    conexion.commit()

    actualizado = conexion.execute("SELECT * FROM orders WHERE id = ?", (id_pedido,)).fetchone()
    return {"order": _fila_a_pedido(actualizado), "extra_minutes": minutos_extra}


@enrutador.post("/{id_pedido}/respond")
def responder_pedido(
    id_pedido: str,
    cuerpo: ResponderPedido,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """El repartidor acepta o rechaza una notificación de recogida.

    - Si acepta (accepted=True): el pedido pasa a 'in_progress' y se añade a su ruta.
    - Si rechaza (accepted=False): el pedido pasa a 'rejected' y no modifica la ruta.

    Raises:
        HTTPException 403: Si el pedido no está asignado al repartidor autenticado.
        HTTPException 404: Si el pedido no existe.
    """
    if usuario_actual["role"] != "repartidor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo los repartidores pueden responder a pedidos",
        )

    conexion = obtener_conexion()
    pedido = conexion.execute("SELECT * FROM orders WHERE id = ?", (id_pedido,)).fetchone()
    if not pedido:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    if pedido["assigned_driver_id"] != usuario_actual["id"]:
        raise HTTPException(status_code=403, detail="Este pedido no está asignado a ti")

    # Determinar el nuevo estado según la respuesta del repartidor
    nuevo_estado = "in_progress" if cuerpo.accepted else "rejected"
    conexion.execute(
        "UPDATE orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
        (nuevo_estado, id_pedido),
    )

    # Si aceptó, añadir el pedido a su ruta activa
    if cuerpo.accepted:
        ruta_activa = conexion.execute(
            "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
            (usuario_actual["id"],),
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
    actualizado = conexion.execute("SELECT * FROM orders WHERE id = ?", (id_pedido,)).fetchone()
    return {"order": _fila_a_pedido(actualizado)}


@enrutador.patch("/{id_pedido}/status")
def actualizar_estado_pedido(
    id_pedido: str,
    cuerpo: ActualizarEstadoPedido,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Actualiza el estado de un pedido a 'in_progress' o 'completed'.

    Los repartidores solo pueden actualizar sus propios pedidos.
    Los operadores centrales pueden actualizar cualquier pedido.

    Raises:
        HTTPException 403: Si el repartidor intenta modificar el pedido de otro.
        HTTPException 404: Si el pedido no existe.
    """
    conexion = obtener_conexion()
    pedido = conexion.execute("SELECT * FROM orders WHERE id = ?", (id_pedido,)).fetchone()
    if not pedido:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    if (
        usuario_actual["role"] == "repartidor"
        and pedido["assigned_driver_id"] != usuario_actual["id"]
    ):
        raise HTTPException(status_code=403, detail="Este pedido no está asignado a ti")

    conexion.execute(
        "UPDATE orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
        (cuerpo.status, id_pedido),
    )
    conexion.commit()
    actualizado = conexion.execute("SELECT * FROM orders WHERE id = ?", (id_pedido,)).fetchone()
    return {"order": _fila_a_pedido(actualizado)}


@enrutador.get("/route/{id_repartidor}", response_model=RutaRespuesta)
def obtener_ruta_repartidor(
    id_repartidor: str,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Devuelve la ruta activa de un repartidor con todos los datos de sus paradas.

    Acceso:
    - Central: puede ver la ruta de cualquier repartidor.
    - Repartidor: solo puede ver su propia ruta.

    Returns:
        Objeto con la ruta y la lista completa de pedidos en orden.

    Raises:
        HTTPException 403: Si no tiene permiso para ver la ruta.
        HTTPException 404: Si el repartidor no tiene ruta activa.
    """
    # Control de acceso: central puede ver cualquiera, repartidor solo la suya
    if usuario_actual["role"] != "central" and (
        usuario_actual["role"] != "repartidor" or usuario_actual["id"] != id_repartidor
    ):
        raise HTTPException(status_code=403, detail="Acceso denegado")

    conexion = obtener_conexion()
    ruta = conexion.execute(
        "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
        (id_repartidor,),
    ).fetchone()
    if not ruta:
        raise HTTPException(status_code=404, detail="No se encontró ruta activa")

    # Obtener los objetos completos de cada pedido en el orden de la ruta
    ids_pedidos = json.loads(ruta["order_ids"])
    pedidos: list[dict] = []
    if ids_pedidos:
        marcadores = ",".join("?" * len(ids_pedidos))
        pedidos = [
            _fila_a_pedido(fila)
            for fila in conexion.execute(
                f"SELECT * FROM orders WHERE id IN ({marcadores})", ids_pedidos
            ).fetchall()
        ]

    return {**dict(ruta), "orders": pedidos}
