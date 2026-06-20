from fastapi import APIRouter, Depends

from app.auth import requerir_central
from app.schemas import DriverKpiResponse, SimulationStatusResponse
from app.services.route20_simulation import (
    get_route20_kpis,
    get_route20_status,
    reset_route20_simulation,
    start_route20_simulation,
)
from app.services.rerouting_simulation import (
    get_rerouting_kpis,
    get_rerouting_status,
    reset_rerouting_simulation,
    start_rerouting_simulation,
)

enrutador = APIRouter(prefix="/simulations", tags=["simulaciones"])


@enrutador.post("/route-20/start", response_model=SimulationStatusResponse)
async def iniciar_simulacion_route20(_: dict = Depends(requerir_central)):
    return await start_route20_simulation()


@enrutador.get("/route-20/status", response_model=SimulationStatusResponse)
def obtener_estado_route20(_: dict = Depends(requerir_central)):
    return get_route20_status()


@enrutador.get("/route-20/kpis", response_model=DriverKpiResponse)
def obtener_kpis_route20(_: dict = Depends(requerir_central)):
    return get_route20_kpis()


@enrutador.post("/route-20/reset", response_model=SimulationStatusResponse)
def resetear_simulacion_route20(_: dict = Depends(requerir_central)):
    return reset_route20_simulation()


@enrutador.post("/rerouting/start", response_model=SimulationStatusResponse)
async def iniciar_simulacion_rerouting(_: dict = Depends(requerir_central)):
    return await start_rerouting_simulation()


@enrutador.get("/rerouting/status", response_model=SimulationStatusResponse)
def obtener_estado_rerouting(_: dict = Depends(requerir_central)):
    return get_rerouting_status()


@enrutador.get("/rerouting/kpis", response_model=DriverKpiResponse)
def obtener_kpis_rerouting(_: dict = Depends(requerir_central)):
    return get_rerouting_kpis()


@enrutador.post("/rerouting/reset", response_model=SimulationStatusResponse)
def resetear_simulacion_rerouting(_: dict = Depends(requerir_central)):
    return reset_rerouting_simulation()
