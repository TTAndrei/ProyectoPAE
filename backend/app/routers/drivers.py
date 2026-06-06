import uuid
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import RepartidorRespuesta, ActualizarUbicacion, JornadaRespuesta, ActualizarDisponibilidad
from app.auth import obtener_usuario_actual, requerir_central, requerir_repartidor

enrutador = APIRouter(prefix="/drivers", tags=["repartidores"])


@enrutador.get("/", response_model=list[RepartidorRespuesta])
def listar_repartidores(_: dict = Depends(requerir_central)):
    with obtener_conexion() as session:
        result = session.run("""
            MATCH (u:User {role: 'repartidor'})
            OPTIONAL MATCH (u)-[:BELONGS_TO]->(c:Company)
            RETURN u.id AS id, u.username AS username, u.name AS name,
                   u.lat AS lat, u.lng AS lng, u.heading AS heading,
                   toString(u.location_updated_at) AS location_updated_at,
                   coalesce(u.is_available, true) AS is_available,
                   c.id AS company_id, c.name AS company_name
        """)
        repartidores = []
        for record in result:
            data = record.data()
            company = None
            if data.get("company_id"):
                company = {
                    "id": data["company_id"],
                    "name": data["company_name"]
                }
            repartidores.append({
                "id": data["id"],
                "username": data["username"],
                "name": data["name"],
                "lat": data["lat"],
                "lng": data["lng"],
                "heading": data["heading"],
                "location_updated_at": data["location_updated_at"],
                "is_available": data["is_available"],
                "company": company
            })
        return repartidores


@enrutador.get("/{id_repartidor}/location")
def obtener_ubicacion_repartidor(
    id_repartidor: str,
    _: dict = Depends(obtener_usuario_actual),
):
    with obtener_conexion() as session:
        result = session.run("""
            MATCH (u:User {id: $id})
            RETURN u.lat AS lat, u.lng AS lng, u.heading AS heading, u.id AS driver_id,
                   toString(u.location_updated_at) AS updated_at,
                   coalesce(u.is_available, true) AS is_available
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
            SET u.is_available = true
            CREATE (u)-[:HAS_JORNADA]->(j:Jornada {
                id: $id, status: 'active', start_time: datetime()
            })
            RETURN j {.*, start_time: toString(j.start_time)} AS j
            """,
            {"uid": usuario_actual["id"], "id": id_jornada},
        ).single()
        print(f"[JORNADA] ✅ Repartidor '{usuario_actual['id']}' inicia jornada -> is_available=true")
        r = dict(result["j"])
        r["driver_id"] = usuario_actual["id"]
        return r


@enrutador.post("/me/jornada/end", response_model=JornadaRespuesta)
def cerrar_jornada(usuario_actual: dict = Depends(requerir_repartidor)):
    with obtener_conexion() as session:
        result = session.run(
            """
            MATCH (u:User {id: $uid})-[:HAS_JORNADA]->(j:Jornada {status: 'active'})
            SET j.status = 'closed', j.end_time = datetime(), u.is_available = false
            RETURN j {.*, start_time: toString(j.start_time), end_time: toString(j.end_time)} AS j
            """,
            {"uid": usuario_actual["id"]},
        ).single()
        if not result:
            raise HTTPException(status_code=404, detail="No hay jornada activa")
        print(f"[JORNADA] 🔴 Repartidor '{usuario_actual['id']}' cierra jornada -> is_available=false")
        r = dict(result["j"])
        r["driver_id"] = usuario_actual["id"]
        return r


@enrutador.get("/me/jornada/active", response_model=Optional[JornadaRespuesta])
def obtener_jornada_activa(usuario_actual: dict = Depends(requerir_repartidor)):
    """Obtiene la jornada activa del repartidor actual, si existe."""
    with obtener_conexion() as session:
        result = session.run(
            """
            MATCH (u:User {id: $uid})-[:HAS_JORNADA]->(j:Jornada {status: 'active'})
            RETURN j {.*, start_time: toString(j.start_time)} AS j
            """,
            {"uid": usuario_actual["id"]},
        ).single()
        if not result:
            return None
        r = dict(result["j"])
        r["driver_id"] = usuario_actual["id"]
        return r


@enrutador.put("/{id_repartidor}/availability")
def actualizar_disponibilidad(
    id_repartidor: str,
    cuerpo: ActualizarDisponibilidad,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Actualiza la disponibilidad de un repartidor (solo él mismo puede hacerlo)."""
    if usuario_actual.get("role") != "repartidor" or usuario_actual.get("id") != id_repartidor:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo puedes actualizar tu propia disponibilidad",
        )

    with obtener_conexion() as session:
        session.run(
            """
            MATCH (u:User {id: $id})
            SET u.is_available = $is_available
            """,
            {"id": id_repartidor, "is_available": cuerpo.is_available},
        )
    return {"success": True}
