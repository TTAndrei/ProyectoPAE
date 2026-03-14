"""Utilidades de autenticación JWT para la aplicación PAE.

Flujo de autenticación:
  1. El cliente envía usuario + contraseña a POST /auth/login
  2. El servidor verifica las credenciales y devuelve un token JWT
  3. El cliente incluye el token en cada petición: Authorization: Bearer <token>
  4. Las dependencias requerir_central / requerir_repartidor validan el rol
"""
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import CLAVE_SECRETA, ALGORITMO, HORAS_EXPIRACION_TOKEN

# Contexto para hashear y verificar contraseñas con bcrypt
contexto_contrasena = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Esquema de seguridad HTTP Bearer (extrae el token del encabezado Authorization)
esquema_portador = HTTPBearer()


def crear_token_acceso(datos: dict) -> str:
    """Genera un token JWT firmado con los datos del usuario.

    Args:
        datos: Diccionario con los campos del usuario (id, username, role, name).

    Returns:
        Cadena JWT lista para enviar al cliente.
    """
    carga = datos.copy()
    # Calcula la fecha de expiración sumando las horas configuradas
    expiracion = datetime.now(timezone.utc) + timedelta(hours=HORAS_EXPIRACION_TOKEN)
    carga["exp"] = expiracion
    return jwt.encode(carga, CLAVE_SECRETA, algorithm=ALGORITMO)


def decodificar_token(token: str) -> dict:
    """Decodifica y valida un token JWT.

    Args:
        token: Cadena JWT recibida del cliente.

    Returns:
        Diccionario con la carga del token (datos del usuario).

    Raises:
        HTTPException 401: Si el token es inválido o ha expirado.
    """
    try:
        carga = jwt.decode(token, CLAVE_SECRETA, algorithms=[ALGORITMO])
        return carga
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
        )


def obtener_usuario_actual(
    credenciales: HTTPAuthorizationCredentials = Depends(esquema_portador),
) -> dict:
    """Dependencia FastAPI: extrae y valida el usuario del token Bearer.

    Uso: añadir `usuario: dict = Depends(obtener_usuario_actual)` como parámetro
    en cualquier endpoint para protegerlo.
    """
    return decodificar_token(credenciales.credentials)


def requerir_central(usuario: dict = Depends(obtener_usuario_actual)) -> dict:
    """Dependencia FastAPI: exige que el usuario autenticado sea de rol 'central'.

    Raises:
        HTTPException 403: Si el usuario no es operador central.
    """
    if usuario.get("role") != "central":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: se requiere rol central",
        )
    return usuario


def requerir_repartidor(usuario: dict = Depends(obtener_usuario_actual)) -> dict:
    """Dependencia FastAPI: exige que el usuario autenticado sea de rol 'repartidor'.

    Raises:
        HTTPException 403: Si el usuario no es repartidor.
    """
    if usuario.get("role") != "repartidor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: se requiere rol repartidor",
        )
    return usuario
