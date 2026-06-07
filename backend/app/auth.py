from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.config import CLAVE_SECRETA, ALGORITMO, HORAS_EXPIRACION_TOKEN

contexto_contrasena = CryptContext(schemes=["bcrypt"], deprecated="auto")
esquema_portador = HTTPBearer()


def crear_token_acceso(datos: dict) -> str:
    carga = datos.copy()
    carga["exp"] = datetime.now(timezone.utc) + timedelta(hours=HORAS_EXPIRACION_TOKEN)
    return jwt.encode(carga, CLAVE_SECRETA, algorithm=ALGORITMO)


def decodificar_token(token: str) -> dict:
    try:
        return jwt.decode(token, CLAVE_SECRETA, algorithms=[ALGORITMO])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token inválido o expirado",
        )


def obtener_usuario_actual(
    credenciales: HTTPAuthorizationCredentials = Depends(esquema_portador),
) -> dict:
    return decodificar_token(credenciales.credentials)


def requerir_central(usuario: dict = Depends(obtener_usuario_actual)) -> dict:
    if usuario.get("role") != "central":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: se requiere rol central",
        )
    return usuario


def requerir_repartidor(usuario: dict = Depends(obtener_usuario_actual)) -> dict:
    if usuario.get("role") != "repartidor":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Acceso denegado: se requiere rol repartidor",
        )
    return usuario


def obtener_id_compania(usuario: dict) -> str:
    company = usuario.get("company")
    if isinstance(company, dict):
        return company.get("id") or "pae-logistics"
    return "pae-logistics"
