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
    with obtener_conexion() as session:
        result = session.run("""
            MATCH (u:User {role: 'repartidor'})
            RETURN u.id AS id, u.username AS username, u.name AS name,
                   u.lat AS lat, u.lng AS lng, u.heading AS heading,
                   toString(u.location_updated_at) AS location_updated_at
        """)
        # Convertir registros a diccionarios
        return [record.data() for record in result]


@enrutador.get("/{id_repartidor}/location")
def obtener_ubicacion_repartidor(
    id_repartidor: str,
    _: dict = Depends(obtener_usuario_actual),
):
    """Devuelve la última ubicación conocida de un repartidor específico.

    Raises:
        HTTPException 404: Si el repartidor no tiene ubicación registrada.
    """
    with obtener_conexion() as session:
        result = session.run("""
            MATCH (u:User {id: $id})
            RETURN u.lat AS lat, u.lng AS lng, u.heading AS heading, u.id AS driver_id,
                   toString(u.location_updated_at) AS updated_at
        """, {"id": id_repartidor})
        record = result.single()
        if not record or record["lat"] is None:
            raise HTTPException(status_code=404, detail="Ubicación no encontrada")
        return record.data()


@enrutador.put("/{id_repartidor}/location")
def actualizar_ubicacion_repartidor(
    id_repartidor: str,
    cuerpo: ActualizarUbicacion,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Actualiza la posición GPS del repartidor en la base de datos.

    Solo el propio repartidor puede actualizar su ubicación.
    En Neo4j, esto es un SET sobre el nodo User.

    Raises:
        HTTPException 403: Si el repartidor intenta actualizar la ubicación de otro.
    """
    # Verificar que el repartidor solo actualice su propia ubicación
    if usuario_actual.get("role") != "repartidor" or usuario_actual.get("id") != id_repartidor:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo puedes actualizar tu propia ubicación",
        )

    with obtener_conexion() as session:
        session.run("""
            MATCH (u:User {id: $id})
            SET u.lat = $lat, u.lng = $lng, u.heading = $heading,
                u.location_updated_at = datetime()
        """, {
            "id": id_repartidor,
            "lat": cuerpo.lat,
            "lng": cuerpo.lng,
            "heading": cuerpo.heading
        })
    return {"success": True}
