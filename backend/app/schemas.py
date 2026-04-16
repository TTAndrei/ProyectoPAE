"""Modelos Pydantic para validación de peticiones y respuestas de la API PAE.

Cada clase define la forma exacta (tipo y campos) de los datos que entran
o salen de los endpoints REST. Pydantic valida automáticamente los tipos
y devuelve errores 422 si los datos no cumplen los requisitos.
"""
from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, field_validator


# ── Autenticación ─────────────────────────────────────────────────────────────

class SolicitudLogin(BaseModel):
    """Datos necesarios para iniciar sesión."""
    username: str
    password: str


class UsuarioRespuesta(BaseModel):
    """Información pública del usuario (sin contraseña)."""
    id: str
    username: str
    role: str
    name: str


class RespuestaToken(BaseModel):
    """Respuesta completa del endpoint de login: token JWT + datos del usuario."""
    token: str
    user: UsuarioRespuesta


# ── Pedidos ───────────────────────────────────────────────────────────────────

class CrearPedido(BaseModel):
    """Datos para crear un nuevo pedido o recogida."""
    type: str       # 'delivery' (entrega) o 'pickup' (recogida)
    address: str    # Dirección completa del punto de parada
    lat: float      # Latitud geográfica
    lng: float      # Longitud geográfica

    @field_validator("type")
    @classmethod
    def validar_tipo(cls, valor: str) -> str:
        """Verifica que el tipo sea 'delivery' o 'pickup'."""
        if valor not in ("delivery", "pickup"):
            raise ValueError("El tipo debe ser 'delivery' (entrega) o 'pickup' (recogida)")
        return valor


class AsignarPedido(BaseModel):
    """Datos para asignar un pedido a un repartidor."""
    driver_id: str   # ID del repartidor al que se asigna


class ResponderPedido(BaseModel):
    """Respuesta del repartidor ante una notificación de recogida."""
    accepted: bool   # True = aceptar, False = rechazar


class ActualizarEstadoPedido(BaseModel):
    """Datos para actualizar el estado de un pedido (solo repartidor)."""
    status: str   # 'in_progress' (en curso) o 'completed' (completado)

    @field_validator("status")
    @classmethod
    def validar_estado(cls, valor: str) -> str:
        """Verifica que el estado sea uno de los valores permitidos."""
        if valor not in ("in_progress", "completed"):
            raise ValueError("El estado debe ser 'in_progress' o 'completed'")
        return valor


class PedidoRespuesta(BaseModel):
    """Representación completa de un pedido devuelto por la API."""
    id: str
    type: str
    address: str
    lat: float
    lng: float
    status: str
    assigned_driver_id: Optional[str]
    estimated_extra_minutes: Optional[float]
    created_at: str
    updated_at: str


# ── Repartidores ──────────────────────────────────────────────────────────────

class ActualizarUbicacion(BaseModel):
    """Datos de ubicación enviados por un repartidor."""
    lat: float           # Latitud actual
    lng: float           # Longitud actual
    heading: float = 0.0  # Dirección de movimiento en grados (0–360)


class RepartidorRespuesta(BaseModel):
    """Información de un repartidor con su ubicación actual."""
    id: str
    username: str
    name: str
    lat: Optional[float]              # None si no ha enviado ubicación aún
    lng: Optional[float]
    heading: Optional[float]
    location_updated_at: Optional[str]


# ── Rutas ─────────────────────────────────────────────────────────────────────

class RutaRespuesta(BaseModel):
    """Ruta activa de un repartidor con su lista de paradas."""
    id: str
    driver_id: str
    order_ids: str          # JSON array con los IDs de pedidos en orden
    status: str
    created_at: str
    updated_at: str
    orders: list[PedidoRespuesta] = []   # Objetos de pedido completos
    total_minutes: float = 0.0
    total_distance_km: float = 0.0
    route_geometry: list[dict[str, float]] = []
    leg_minutes: list[float] = []
