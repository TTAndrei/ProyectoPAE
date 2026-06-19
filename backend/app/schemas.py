from __future__ import annotations
from typing import Optional
from pydantic import BaseModel, Field, field_validator


class SolicitudLogin(BaseModel):
    username: str
    password: str


class CompaniaRespuesta(BaseModel):
    id: str
    name: str


class CrearCompania(BaseModel):
    name: str

class CrearUsuario(BaseModel):
    username: str
    password: str
    role: str
    name: str
    company_id: Optional[str] = None

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
    company: Optional[CompaniaRespuesta] = None


class RespuestaToken(BaseModel):
    token: str
    user: UsuarioRespuesta


class CrearPedido(BaseModel):
    type: str
    address: str
    lat: float
    lng: float
    name: Optional[str] = None
    driver_id: Optional[str] = None
    incoterm: Optional[str] = None
    origen: Optional[str] = None
    destino: Optional[str] = None
    tipo_bulto: Optional[str] = None
    dimensiones: Optional[str] = None
    peso: Optional[float] = None
    es_adr: Optional[bool] = False
    adr_tipo: Optional[str] = None
    adr_codigo_un: Optional[str] = None
    cliente_nombre: Optional[str] = None
    cliente_contacto: Optional[str] = None
    destinatario_nombre: Optional[str] = None
    destinatario_contacto: Optional[str] = None

    @field_validator("type")
    @classmethod
    def validar_tipo(cls, valor: str) -> str:
        if valor not in ("delivery", "pickup"):
            raise ValueError("El tipo debe ser 'delivery' o 'pickup'")
        return valor

    @field_validator("tipo_bulto")
    @classmethod
    def validar_tipo_bulto(cls, valor: Optional[str]) -> Optional[str]:
        if valor is not None and valor not in ("caja", "pallet", "cajon"):
            raise ValueError("El tipo de bulto debe ser 'caja', 'pallet' o 'cajon'")
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
    incoterm: Optional[str] = None
    origen: Optional[str] = None
    destino: Optional[str] = None
    tipo_bulto: Optional[str] = None
    dimensiones: Optional[str] = None
    peso: Optional[float] = None
    es_adr: Optional[bool] = False
    adr_tipo: Optional[str] = None
    adr_codigo_un: Optional[str] = None
    cliente_nombre: Optional[str] = None
    cliente_contacto: Optional[str] = None
    destinatario_nombre: Optional[str] = None
    destinatario_contacto: Optional[str] = None



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
    company: Optional[CompaniaRespuesta] = None
    load_efficiency_ratio: float = 0.0
    load_efficiency_percent: float = 0.0
    loaded_distance_km: float = 0.0
    total_distance_km: float = 0.0
    active_order_count: int = 0
    pending_confirmation_count: int = 0
    completed_order_count: int = 0
    average_load_packages: float = 0.0
    load_weighted_distance: float = 0.0
    average_insertion_detour_minutes: float = 0.0
    packages_per_km: float = 0.0
    insertion_acceptance_rate: float = 0.0
    accepted_insertion_count: int = 0
    rejected_insertion_count: int = 0
    target_load_efficiency_ratio: float = 0.75
    meets_load_efficiency_target: bool = False
    measurement_note: str = ""


class DriverKpiResponse(BaseModel):
    driver_id: str
    load_efficiency_ratio: float = 0.0
    load_efficiency_percent: float = 0.0
    loaded_distance_km: float = 0.0
    total_distance_km: float = 0.0
    active_order_count: int = 0
    pending_confirmation_count: int = 0
    completed_order_count: int = 0
    average_load_packages: float = 0.0
    load_weighted_distance: float = 0.0
    average_insertion_detour_minutes: float = 0.0
    packages_per_km: float = 0.0
    insertion_acceptance_rate: float = 0.0
    accepted_insertion_count: int = 0
    rejected_insertion_count: int = 0
    target_load_efficiency_ratio: float = 0.75
    meets_load_efficiency_target: bool = False
    measurement_note: str = ""


class SimulationStatusResponse(BaseModel):
    id: str
    status: str
    current_index: int = 0
    total_stops: int = 20
    driver_id: str = "driver-demo"
    current_stop: Optional[PedidoRespuesta] = None
    started_at: Optional[str] = None
    finished_at: Optional[str] = None
    error: Optional[str] = None
    comparison: Optional[dict] = None
    events: list[dict] = Field(default_factory=list)
    kpis: DriverKpiResponse

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


class LogAuditoriaRespuesta(BaseModel):
    id: str
    order_id: str
    action: str
    driver_id: Optional[str] = None
    timestamp: str
    details: Optional[str] = None


class RendimientoRepartidorRespuesta(BaseModel):
    driver_id: str
    name: str
    load_efficiency_ratio: float
    load_efficiency_percent: float
    loaded_distance_km: float
    total_distance_km: float
    active_order_count: int
    pending_confirmation_count: int
    completed_order_count: int
    average_load_packages: float = 0.0
    average_insertion_detour_minutes: float = 0.0
    packages_per_km: float = 0.0
    insertion_acceptance_rate: float = 0.0
    meets_load_efficiency_target: bool


class AnaliticasFlotaRespuesta(BaseModel):
    total_distance_km: float
    loaded_distance_km: float
    average_load_efficiency_percent: float
    total_active_orders: int
    total_pending_confirmations: int
    total_completed_orders: int
    average_load_packages: float = 0.0
    average_insertion_detour_minutes: float = 0.0
    packages_per_km: float = 0.0
    insertion_acceptance_rate: float = 0.0


class RutaHistoricaRespuesta(BaseModel):
    id: str
    driver_id: str
    order_ids: list[str] = []
    completed_order_ids: list[str] = []
    status: str
    created_at: str
    updated_at: str
    total_minutes: float = 0.0
    total_distance_km: float = 0.0
    route_geometry: list[dict[str, float]] = []
    leg_minutes: list[float] = []
