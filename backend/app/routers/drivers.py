"""Router de repartidores: listado y gestión de ubicaciones.

Endpoints:
  GET  /drivers/              → Lista todos los repartidores con su ubicación (solo Central)
  GET  /drivers/{id}/location → Obtiene la ubicación de un repartidor concreto
  PUT  /drivers/{id}/location → Actualiza la ubicación del repartidor autenticado
"""
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import RepartidorRespuesta, ActualizarUbicacion
from app.auth import obtener_usuario_actual, requerir_central

# Enrutador de repartidores con prefijo /drivers
enrutador = APIRouter(prefix="/drivers", tags=["repartidores"])


@enrutador.get("/", response_model=list[RepartidorRespuesta])
def listar_repartidores(_: dict = Depends(requerir_central)):
    """Devuelve todos los repartidores con su última ubicación registrada.

    Solo accesible para operadores centrales.
    Si un repartidor no ha enviado ubicación aún, los campos lat/lng/heading
    aparecen como null.
    """
    conexion = obtener_conexion()
    filas = conexion.execute(
        """
        SELECT u.id, u.username, u.name,
               dl.lat, dl.lng, dl.heading,
               dl.updated_at AS location_updated_at
        FROM users u
        LEFT JOIN driver_locations dl ON dl.driver_id = u.id
        WHERE u.role = 'repartidor'
        """
    ).fetchall()
    return [dict(fila) for fila in filas]


@enrutador.get("/{id_repartidor}/location")
def obtener_ubicacion_repartidor(
    id_repartidor: str,
    _: dict = Depends(obtener_usuario_actual),
):
    """Devuelve la última ubicación conocida de un repartidor específico.

    Raises:
        HTTPException 404: Si el repartidor no tiene ubicación registrada.
    """
    conexion = obtener_conexion()
    fila = conexion.execute(
        "SELECT * FROM driver_locations WHERE driver_id = ?", (id_repartidor,)
    ).fetchone()
    if not fila:
        raise HTTPException(status_code=404, detail="Ubicación no encontrada")
    return dict(fila)


@enrutador.put("/{id_repartidor}/location")
def actualizar_ubicacion_repartidor(
    id_repartidor: str,
    cuerpo: ActualizarUbicacion,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Actualiza la posición GPS del repartidor en la base de datos.

    Solo el propio repartidor puede actualizar su ubicación.
    Si no existe una fila previa, se crea automáticamente (INSERT OR UPDATE).

    Raises:
        HTTPException 403: Si el repartidor intenta actualizar la ubicación de otro.
    """
    # Verificar que el repartidor solo actualice su propia ubicación
    if usuario_actual.get("role") != "repartidor" or usuario_actual.get("id") != id_repartidor:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo puedes actualizar tu propia ubicación",
        )

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
        (id_repartidor, cuerpo.lat, cuerpo.lng, cuerpo.heading),
    )
    conexion.commit()
    return {"success": True}
