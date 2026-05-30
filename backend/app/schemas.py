from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, field_validator


class SolicitudLogin(BaseModel):
    username: str
    password: str


class CrearUsuario(BaseModel):
    username: str
    password: str
    role: str
    name: str

    @field_validator("role")
    @classmethod
    def validar_rol(cls, valor: str) -> str:
        if valor not in ("central", "repartidor"):
            raise ValueError("El rol debe ser 'central' o 'repartidor'")
        return valor


class UsuarioRespuesta(BaseModel):
    id: str
    username: str
    role: str
    name: str


class RespuestaToken(BaseModel):
    token: str
    user: UsuarioRespuesta


class CrearPedido(BaseModel):
    type: str
    address: str
    lat: float
    lng: float
    name: Optional[str] = None

    @field_validator("type")
    @classmethod
    def validar_tipo(cls, valor: str) -> str:
        if valor not in ("delivery", "pickup"):
            raise ValueError("El tipo debe ser 'delivery' o 'pickup'")
        return valor


class AsignarPedido(BaseModel):
    driver_id: str


class ResponderPedido(BaseModel):
    accepted: bool


class ActualizarEstadoPedido(BaseModel):
    status: str

    @field_validator("status")
    @classmethod
    def validar_estado(cls, valor: str) -> str:
        if valor not in ("in_progress", "completed"):
            raise ValueError("El estado debe ser 'in_progress' o 'completed'")
        return valor


class PedidoRespuesta(BaseModel):
    id: str
    type: str
    name: Optional[str] = None
    address: str
    lat: float
    lng: float
    status: str
    assigned_driver_id: Optional[str] = None
    estimated_extra_minutes: Optional[float] = None
    backhauling_candidates: list[dict] = []
    created_at: str
    updated_at: str


class ActualizarUbicacion(BaseModel):
    lat: float
    lng: float
    heading: float = 0.0


class RepartidorRespuesta(BaseModel):
    id: str
    username: str
    name: str
    lat: Optional[float] = None
    lng: Optional[float] = None
    heading: Optional[float] = None
    location_updated_at: Optional[str] = None
    is_available: bool = True

class RutaRespuesta(BaseModel):
    id: str
    driver_id: str
    order_ids: list[str] = []
    status: str
    created_at: str
    updated_at: str
    orders: list[PedidoRespuesta] = []
    total_minutes: float = 0.0
    total_distance_km: float = 0.0
    route_geometry: list[dict[str, float]] = []
    leg_minutes: list[float] = []


class IniciarJornada(BaseModel):
    pass


class JornadaRespuesta(BaseModel):
    id: str
    driver_id: str
    status: str
    start_time: str
    end_time: Optional[str] = None


class ActualizarPerfil(BaseModel):
    name: Optional[str] = None
    username: Optional[str] = None
    password: Optional[str] = None


class ActualizarDisponibilidad(BaseModel):
    is_available: bool
