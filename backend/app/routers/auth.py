"""Router de autenticación: login y gestión de usuarios.

Endpoints:
  POST /auth/login    → Autentica al usuario y devuelve un token JWT
  POST /auth/register → Registra un nuevo usuario (genera un UUID)
  GET  /auth/me       → Devuelve los datos del usuario autenticado
"""
import uuid
from typing import Optional
from fastapi import APIRouter, HTTPException, status, Depends
from fastapi.security import HTTPBearer
from jose import jwt

from app.config import CLAVE_SECRETA, ALGORITMO
from app.database import obtener_conexion
from app.schemas import SolicitudLogin, RespuestaToken, UsuarioRespuesta, CrearUsuario, ActualizarPerfil, CompaniaRespuesta, CrearCompania
from app.auth import contexto_contrasena, crear_token_acceso, obtener_usuario_actual

# Enrutador de autenticación con prefijo /auth
enrutador = APIRouter(prefix="/auth", tags=["autenticación"])

bearer_scheme = HTTPBearer(auto_error=False)

def obtener_compania_creador(credenciales = Depends(bearer_scheme)) -> str | None:
    """Extrae el company_id del JWT si existe. Devuelve None si no hay token."""
    if not credenciales:
        return None
    try:
        payload = jwt.decode(credenciales.credentials, CLAVE_SECRETA, algorithms=[ALGORITMO])
        company = payload.get("company")
        if company and isinstance(company, dict):
            return company.get("id") or None
    except Exception:
        pass
    return None


@enrutador.post("/companies", response_model=CompaniaRespuesta, status_code=status.HTTP_201_CREATED)
def registrar_compania(cuerpo: CrearCompania):
    """Registra una nueva compañía en el sistema."""
    company_id = str(uuid.uuid4())
    with obtener_conexion() as session:
        # Verificar si ya existe una compañía con ese nombre
        existe = session.run(
            "MATCH (c:Company) WHERE toLower(c.name) = toLower($name) RETURN c",
            {"name": cuerpo.name},
        ).single()
        if existe:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Ya existe una compañía con ese nombre",
            )

        result = session.run(
            """
            CREATE (c:Company {
                id: $id,
                name: $name,
                created_at: datetime()
            })
            RETURN c.id AS id, c.name AS name
            """,
            {"id": company_id, "name": cuerpo.name},
        ).single()
        return CompaniaRespuesta(id=result["id"], name=result["name"])


@enrutador.get("/companies", response_model=list[CompaniaRespuesta])
def listar_companias():
    """Lista todas las compañías registradas (público, para el formulario de registro)."""
    with obtener_conexion() as session:
        result = session.run("MATCH (c:Company) RETURN c.id AS id, c.name AS name ORDER BY c.name")
        return [CompaniaRespuesta(id=r["id"], name=r["name"]) for r in result]


@enrutador.post("/login", response_model=RespuestaToken)
def iniciar_sesion(cuerpo: SolicitudLogin):
    """Verifica las credenciales del usuario y devuelve un token JWT."""
    with obtener_conexion() as session:
        result = session.run("""
            MATCH (u:User {username: $username})
            OPTIONAL MATCH (u)-[:BELONGS_TO]->(c:Company)
            RETURN u, c.id AS company_id, c.name AS company_name
        """, {"username": cuerpo.username})
        record = result.single()

        if not record:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario o contraseña incorrectos",
            )
        
        user = record["u"]
        if not contexto_contrasena.verify(cuerpo.password, user["password_hash"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Usuario o contraseña incorrectos",
            )

        company = None
        if record["company_id"]:
            company = {
                "id": record["company_id"],
                "name": record["company_name"]
            }

        datos_usuario = {
            "id": user["id"],
            "username": user["username"],
            "role": user["role"],
            "name": user["name"],
            "company": company,
        }
        token = crear_token_acceso(datos_usuario)
        return RespuestaToken(token=token, user=UsuarioRespuesta(**datos_usuario))


@enrutador.post("/register", response_model=UsuarioRespuesta, status_code=status.HTTP_201_CREATED)
def registrar_usuario(cuerpo: CrearUsuario, compania_id_jwt: str | None = Depends(obtener_compania_creador)):
    """Registra un nuevo usuario en el sistema.
    
    La compañía se determina por prioridad:
    1. Si hay un JWT válido, se usa la compañía del token (un central registra repartidores en su empresa).
    2. Si no hay JWT y se proporciona company_name, se busca la compañía por nombre.
    3. Si no se encuentra, se devuelve un error.
    """
    id_usuario = str(uuid.uuid4())
    password_hash = contexto_contrasena.hash(cuerpo.password)

    with obtener_conexion() as session:
        # Verificar si el nombre de usuario ya existe
        existe = session.run(
            "MATCH (u:User {username: $username}) RETURN u",
            {"username": cuerpo.username}
        ).single()
        if existe:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El nombre de usuario ya está registrado",
            )

        # Determinar la compañía
        if compania_id_jwt:
            compania_id = compania_id_jwt
        elif cuerpo.company_id:
            # Buscar la compañía por ID
            company_record = session.run(
                "MATCH (c:Company {id: $id}) RETURN c.id AS id",
                {"id": cuerpo.company_id},
            ).single()
            if not company_record:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"No se encontró la compañía con ID '{cuerpo.company_id}'. Regístrala primero.",
                )
            compania_id = company_record["id"]
        else:
            compania_id = "pae-logistics"

        # Crear el usuario
        result = session.run("""
            CREATE (u:User {
                id: $id,
                username: $username,
                password_hash: $password_hash,
                role: $role,
                name: $name,
                created_at: datetime()
            })
            WITH u
            MATCH (c:Company {id: $compania_id})
            CREATE (u)-[:BELONGS_TO]->(c)
            RETURN u, c.id AS company_id, c.name AS company_name
        """, {
            "id": id_usuario,
            "username": cuerpo.username,
            "password_hash": password_hash,
            "role": cuerpo.role,
            "name": cuerpo.name,
            "compania_id": compania_id
        })
        
        record = result.single()
        company = None
        if record and record["company_id"]:
            company = {
                "id": record["company_id"],
                "name": record["company_name"]
            }

        # Si es repartidor, inicializar su ruta activa
        if cuerpo.role == "repartidor":
            id_ruta = str(uuid.uuid4())
            session.run("""
                MATCH (u:User {id: $uid})
                CREATE (u)-[:HAS_ROUTE]->(r:Route {
                    id: $rid,
                    order_ids: [],
                    status: 'active',
                    created_at: datetime(),
                    updated_at: datetime()
                })
            """, {"uid": id_usuario, "rid": id_ruta})

        return UsuarioRespuesta(
            id=id_usuario,
            username=cuerpo.username,
            role=cuerpo.role,
            name=cuerpo.name,
            company=company
        )


@enrutador.get("/me", response_model=UsuarioRespuesta)
def obtener_yo(usuario_actual: dict = Depends(obtener_usuario_actual)):
    """Devuelve los datos del usuario cuyo token se proporciona en la petición."""
    return UsuarioRespuesta(
        id=usuario_actual["id"],
        username=usuario_actual["username"],
        role=usuario_actual["role"],
        name=usuario_actual["name"],
        company=usuario_actual.get("company"),
    )


@enrutador.put("/me", response_model=UsuarioRespuesta)
def actualizar_yo(
    cuerpo: ActualizarPerfil,
    usuario_actual: dict = Depends(obtener_usuario_actual),
):
    """Actualiza la información del usuario autenticado (nombre, nombre de usuario, contraseña)."""
    with obtener_conexion() as session:
        if cuerpo.username and cuerpo.username != usuario_actual["username"]:
            # Verificar si el nuevo nombre de usuario ya está registrado
            existe = session.run(
                "MATCH (u:User {username: $username}) RETURN u",
                {"username": cuerpo.username}
            ).single()
            if existe:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="El nombre de usuario ya está registrado",
                )

        params = {"id": usuario_actual["id"]}
        updates = []
        if cuerpo.name is not None:
            updates.append("u.name = $name")
            params["name"] = cuerpo.name
        if cuerpo.username is not None:
            updates.append("u.username = $username")
            params["username"] = cuerpo.username
        if cuerpo.password is not None and cuerpo.password.strip() != "":
            updates.append("u.password_hash = $password_hash")
            params["password_hash"] = contexto_contrasena.hash(cuerpo.password)

        if updates:
            set_clause = ", ".join(updates)
            result = session.run(
                f"""
                MATCH (u:User {{id: $id}})
                SET {set_clause}
                WITH u
                OPTIONAL MATCH (u)-[:BELONGS_TO]->(c:Company)
                RETURN u, c.id AS company_id, c.name AS company_name
                """,
                params
            )
            record = result.single()
            if not record:
                raise HTTPException(status_code=404, detail="Usuario no encontrado")
            user = record["u"]
            company = None
            if record["company_id"]:
                company = {
                    "id": record["company_id"],
                    "name": record["company_name"]
                }
            return UsuarioRespuesta(
                id=user["id"],
                username=user["username"],
                role=user["role"],
                name=user["name"],
                company=company,
            )

        return UsuarioRespuesta(
            id=usuario_actual["id"],
            username=usuario_actual["username"],
            role=usuario_actual["role"],
            name=usuario_actual["name"],
            company=usuario_actual.get("company"),
        )
