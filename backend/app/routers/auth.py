"""Router de autenticación: login y consulta del usuario actual.

Endpoints:
  POST /auth/login  → Autentica al usuario y devuelve un token JWT
  GET  /auth/yo     → Devuelve los datos del usuario autenticado
"""
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import obtener_conexion
from app.schemas import SolicitudLogin, RespuestaToken, UsuarioRespuesta
from app.auth import contexto_contrasena, crear_token_acceso, obtener_usuario_actual

# Enrutador de autenticación con prefijo /auth
enrutador = APIRouter(prefix="/auth", tags=["autenticación"])


@enrutador.post("/login", response_model=RespuestaToken)
def iniciar_sesion(cuerpo: SolicitudLogin):
    """Verifica las credenciales del usuario y devuelve un token JWT.

    El token debe incluirse en todas las peticiones posteriores en el
    encabezado HTTP: Authorization: Bearer <token>

    Raises:
        HTTPException 401: Si el usuario no existe o la contraseña es incorrecta.
    """
    conexion = obtener_conexion()
    fila = conexion.execute(
        "SELECT * FROM users WHERE username = ?", (cuerpo.username,)
    ).fetchone()

    # Verificar existencia del usuario y correctitud de la contraseña (bcrypt)
    if not fila or not contexto_contrasena.verify(cuerpo.password, fila["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
        )

    # Construir los datos que se almacenarán en el token JWT
    datos_usuario = {
        "id": fila["id"],
        "username": fila["username"],
        "role": fila["role"],
        "name": fila["name"],
    }
    token = crear_token_acceso(datos_usuario)
    return RespuestaToken(token=token, user=UsuarioRespuesta(**datos_usuario))


@enrutador.get("/me", response_model=UsuarioRespuesta)
def obtener_yo(usuario_actual: dict = Depends(obtener_usuario_actual)):
    """Devuelve los datos del usuario cuyo token se proporciona en la petición."""
    return UsuarioRespuesta(
        id=usuario_actual["id"],
        username=usuario_actual["username"],
        role=usuario_actual["role"],
        name=usuario_actual["name"],
    )
