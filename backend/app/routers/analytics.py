from fastapi import APIRouter, Depends

from app.auth import requerir_central, obtener_id_compania
from app.database import obtener_conexion
from app.schemas import (
    AnaliticasFlotaRespuesta,
    LogAuditoriaRespuesta,
    RendimientoRepartidorRespuesta,
    RutaHistoricaRespuesta,
)
from app.services.analytics import (
    obtener_historial_rutas,
    obtener_linea_tiempo_pedido,
    obtener_ranking_repartidores,
    obtener_resumen_flota,
)

enrutador = APIRouter(prefix="/analytics", tags=["analytics"])


@enrutador.get("/fleet-summary", response_model=AnaliticasFlotaRespuesta)
def get_fleet_summary(usuario_actual: dict = Depends(requerir_central)):
    company_id = obtener_id_compania(usuario_actual)
    with obtener_conexion() as session:
        return obtener_resumen_flota(session, company_id)


@enrutador.get("/driver-performance", response_model=list[RendimientoRepartidorRespuesta])
def get_driver_performance(usuario_actual: dict = Depends(requerir_central)):
    company_id = obtener_id_compania(usuario_actual)
    with obtener_conexion() as session:
        return obtener_ranking_repartidores(session, company_id)


@enrutador.get("/routes-history", response_model=list[RutaHistoricaRespuesta])
def get_routes_history(usuario_actual: dict = Depends(requerir_central)):
    company_id = obtener_id_compania(usuario_actual)
    with obtener_conexion() as session:
        return obtener_historial_rutas(session, company_id)


@enrutador.get("/audit-logs/{id_pedido}", response_model=list[LogAuditoriaRespuesta])
def get_audit_logs(id_pedido: str, usuario_actual: dict = Depends(requerir_central)):
    company_id = obtener_id_compania(usuario_actual)
    with obtener_conexion() as session:
        return obtener_linea_tiempo_pedido(session, id_pedido, company_id)
