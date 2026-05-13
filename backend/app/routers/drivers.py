import uuid
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import RepartidorRespuesta, ActualizarUbicacion, JornadaRespuesta
from app.auth import obtener_usuario_actual, requerir_central, requerir_repartidor

enrutador = APIRouter(prefix="/drivers", tags=["repartidores"])


@enrutador.get("/", response_model=list[RepartidorRespuesta])
def listar_repartidores(_: dict = Depends(requerir_central)):
    with obtener_conexion() as session:
        result = session.run("""
            MATCH (u:User {role: 'repartidor'})
            RETURN u.id AS id, u.username AS username, u.name AS name,
                   u.lat AS lat, u.lng AS lng, u.heading AS heading,
                   toString(u.location_updated_at) AS location_updated_at
        """)
        return [record.data() for record in result]


@enrutador.get("/{id_repartidor}/location")
def obtener_ubicacion_repartidor(
    id_repartidor: str,
    _: dict = Depends(obtener_usuario_actual),
):
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
            "heading": cuerpo.heading,
        })
    return {"success": True}


@enrutador.post("/me/jornada/start", response_model=JornadaRespuesta, status_code=status.HTTP_201_CREATED)
def iniciar_jornada(usuario_actual: dict = Depends(requerir_repartidor)):
    id_jornada = str(uuid.uuid4())
    with obtener_conexion() as session:
        activa = session.run(
            "MATCH (u:User {id: $id})-[:HAS_JORNADA]->(j:Jornada {status: 'active'}) RETURN j",
            {"id": usuario_actual["id"]},
        ).single()
        if activa:
            raise HTTPException(status_code=409, detail="Ya hay una jornada activa")
        result = session.run(
            """
            MATCH (u:User {id: $uid})
            CREATE (u)-[:HAS_JORNADA]->(j:Jornada {
                id: $id, status: 'active', start_time: datetime()
            })
            RETURN j {.*, start_time: toString(j.start_time)} AS j
            """,
            {"uid": usuario_actual["id"], "id": id_jornada},
        ).single()
        r = dict(result["j"])
        r["driver_id"] = usuario_actual["id"]
        return r


@enrutador.post("/me/jornada/end", response_model=JornadaRespuesta)
def cerrar_jornada(usuario_actual: dict = Depends(requerir_repartidor)):
    with obtener_conexion() as session:
        result = session.run(
            """
            MATCH (u:User {id: $uid})-[:HAS_JORNADA]->(j:Jornada {status: 'active'})
            SET j.status = 'closed', j.end_time = datetime()
            RETURN j {.*, start_time: toString(j.start_time), end_time: toString(j.end_time)} AS j
            """,
            {"uid": usuario_actual["id"]},
        ).single()
        if not result:
            raise HTTPException(status_code=404, detail="No hay jornada activa")
        r = dict(result["j"])
        r["driver_id"] = usuario_actual["id"]
        return r
