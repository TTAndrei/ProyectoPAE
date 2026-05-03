"""Router de autenticación: login y gestión de usuarios.

Endpoints:
  POST /auth/login    → Autentica al usuario y devuelve un token JWT
  POST /auth/register → Registra un nuevo usuario (genera un UUID)
  GET  /auth/me       → Devuelve los datos del usuario autenticado
"""
import uuid
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import SolicitudLogin, RespuestaToken, UsuarioRespuesta, CrearUsuario
from app.auth import contexto_contrasena, crear_token_acceso, obtener_usuario_actual

# Enrutador de autenticación con prefijo /auth
enrutador = APIRouter(prefix="/auth", tags=["autenticación"])


@enrutador.post("/login", response_model=RespuestaToken)
def iniciar_sesion(cuerpo: SolicitudLogin):
    """Verifica las credenciales del usuario y devuelve un token JWT."""
    with obtener_conexion() as session:
        result = session.run(
            "MATCH (u:User {username: $username}) RETURN u", 
            {"username": cuerpo.username}
        )
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

        datos_usuario = {
            "id": user["id"],
            "username": user["username"],
            "role": user["role"],
            "name": user["name"],
        }
        token = crear_token_acceso(datos_usuario)
        return RespuestaToken(token=token, user=UsuarioRespuesta(**datos_usuario))


@enrutador.post("/register", response_model=UsuarioRespuesta, status_code=status.HTTP_201_CREATED)
def registrar_usuario(cuerpo: CrearUsuario):
    """Registra un nuevo usuario en el sistema con un ID de tipo UUID.
    
    Si el rol es 'repartidor', se le crea automáticamente una ruta activa vacía.
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

        # Crear el usuario
        session.run("""
            CREATE (u:User {
                id: $id,
                username: $username,
                password_hash: $password_hash,
                role: $role,
                name: $name,
                created_at: datetime()
            })
        """, {
            "id": id_usuario,
            "username": cuerpo.username,
            "password_hash": password_hash,
            "role": cuerpo.role,
            "name": cuerpo.name
        })

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
            name=cuerpo.name
        )


@enrutador.get("/me", response_model=UsuarioRespuesta)
def obtener_yo(usuario_actual: dict = Depends(obtener_usuario_actual)):
    """Devuelve los datos del usuario cuyo token se proporciona en la petición."""
    return UsuarioRespuesta(
        id=usuario_actual["id"],
        username=usuario_actual["username"],
        role=usuario_actual["role"],
        name=usuario_actual["name"],
    )
