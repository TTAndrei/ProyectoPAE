"""Fixtures compartidos de pytest para todas las pruebas de PAE.

Configuración:
- Usa la base de datos Neo4j configurada para pruebas.
- Define variables de entorno ANTES de importar módulos de la app.
"""
import os
import pytest
from httpx import AsyncClient, ASGITransport

# Establecer las variables de entorno para pruebas
os.environ["SECRET_KEY"] = "clave_secreta_para_pruebas"
# Por defecto usamos la base de datos local 'neo4j'
# En un entorno de CI/CD se cambiaría por una instancia de pruebas.
os.environ["NEO4J_DATABASE"] = os.getenv("NEO4J_DATABASE", "neo4j")

@pytest.fixture(scope="session", autouse=True)
def base_de_datos_prueba():
    """Inicializa la base de datos de prueba una sola vez por sesión de test."""
    from app.database import inicializar_bd, cerrar_conexion
    # NOTA: En Neo4j, esto creará las restricciones y sembrará datos si está vacía.
    # PRECAUCIÓN: Las pruebas compartirán el estado si no se limpia explícitamente.
    inicializar_bd()
    yield
    try:
        cerrar_conexion()
    except Exception:
        pass


@pytest.fixture(scope="session")
def aplicacion(base_de_datos_prueba):
    """Devuelve una instancia fresca de la aplicación FastAPI para las pruebas."""
    from app.main import crear_aplicacion
    return crear_aplicacion()


@pytest.fixture
async def cliente(aplicacion):
    """Cliente HTTP asíncrono (httpx) configurado para llamar a la app directamente."""
    async with AsyncClient(
        transport=ASGITransport(app=aplicacion), base_url="http://test"
    ) as c:
        yield c


@pytest.fixture
async def token_central(cliente):
    """Token JWT de un operador central para usar en los tests que requieren ese rol."""
    respuesta = await cliente.post(
        "/auth/login", json={"username": "central", "password": "central123"}
    )
    return respuesta.json()["token"]


@pytest.fixture
async def token_repartidor1(cliente):
    """Token JWT del repartidor 'driver1' for tests que requieren rol repartidor."""
    respuesta = await cliente.post(
        "/auth/login", json={"username": "driver1", "password": "driver123"}
    )
    return respuesta.json()["token"]
