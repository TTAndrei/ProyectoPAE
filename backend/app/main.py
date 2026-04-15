"""Fábrica de la aplicación FastAPI para PAE – Gestión de Rutas.

Patrón "application factory": la función crear_aplicacion() construye y
configura la instancia FastAPI. Esto facilita las pruebas (cada test puede
obtener una instancia fresca) y la reutilización con distintas configuraciones.
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import ORIGENES_CORS
from app.database import inicializar_bd
from app.routers.auth import enrutador as enrutador_auth
from app.routers.drivers import enrutador as enrutador_repartidores
from app.routers.orders import enrutador as enrutador_pedidos
from app.routers.ws import enrutador as enrutador_ws


def crear_aplicacion() -> FastAPI:
    """Crea y configura la instancia FastAPI con todos los routers y middleware.

    Proceso de arranque (lifespan):
      1. Se inicializa la base de datos SQLite (tablas + datos demo)
      2. Se registran los middleware CORS
      3. Se incluyen los routers de la API

    Returns:
        Instancia FastAPI completamente configurada.
    """

    @asynccontextmanager
    async def ciclo_vida(_aplicacion: FastAPI):
        """Contexto de ciclo de vida: se ejecuta al arrancar y al apagar."""
        # Arranque: inicializar la base de datos
        inicializar_bd()
        yield
        # Apagado: aquí se podrían cerrar conexiones, etc.

    aplicacion = FastAPI(
        title="PAE – Gestión de Rutas de Última Milla",
        description=(
            "Sistema de gestión de rutas para repartidores de última milla: "
            "ubicación en tiempo real, notificaciones de recogidas y optimización "
            "de trayectos con algoritmo de inserción óptima (Haversine)."
        ),
        version="1.0.0",
        lifespan=ciclo_vida,
    )

    # Middleware CORS: permite que el frontend acceda a la API desde otro origen
    aplicacion.add_middleware(
        CORSMiddleware,
        allow_origins=ORIGENES_CORS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Registrar todos los routers de la API
    aplicacion.include_router(enrutador_auth)
    aplicacion.include_router(enrutador_repartidores)
    aplicacion.include_router(enrutador_pedidos)
    aplicacion.include_router(enrutador_ws)

    @aplicacion.get("/health", tags=["sistema"])
    def verificar_estado():
        """Endpoint de comprobación de salud del servidor."""
        return {"status": "ok"}

    return aplicacion


# Instancia de la aplicación usada por uvicorn:
# uvicorn app.main:aplicacion --reload --port 8000
aplicacion = crear_aplicacion()

# Alias para compatibilidad con herramientas que buscan la variable 'app'
app = aplicacion
