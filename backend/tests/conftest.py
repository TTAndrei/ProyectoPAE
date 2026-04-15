"""Fixtures compartidos de pytest para todas las pruebas de PAE.

Configuración:
- Usa una base de datos SQLite temporal (archivo .db en /tmp) por sesión
- Define variables de entorno ANTES de importar módulos de la app
- Proporciona fixtures reutilizables: cliente HTTP async, tokens de sesión
"""
import os
import tempfile
import pytest
from httpx import AsyncClient, ASGITransport

# Establecer las variables de entorno ANTES de importar cualquier módulo de la app
# para que config.py las recoja correctamente
archivo_tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
RUTA_BD_TEMPORAL = archivo_tmp.name
archivo_tmp.close()
os.environ["DB_PATH"] = RUTA_BD_TEMPORAL
os.environ["SECRET_KEY"] = "clave_secreta_para_pruebas"


@pytest.fixture(scope="session", autouse=True)
def base_de_datos_prueba():
    """Inicializa la base de datos de prueba una sola vez por sesión de test.

    Se usa scope='session' para evitar reinicializar la BD en cada test,
    lo que aceleraría considerablemente la ejecución de la suite.
    """
    from app.database import inicializar_bd, cerrar_conexion
    inicializar_bd()
    yield RUTA_BD_TEMPORAL
    # Cerrar la conexión SQLite para liberar el archivo en Windows.
    try:
        cerrar_conexion()
    except Exception:
        pass
    # Limpieza: eliminar el archivo temporal al terminar
    try:
        os.unlink(RUTA_BD_TEMPORAL)
    except (FileNotFoundError, PermissionError):
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
    """Token JWT del repartidor 'driver1' para tests que requieren rol repartidor."""
    respuesta = await cliente.post(
        "/auth/login", json={"username": "driver1", "password": "driver123"}
    )
    return respuesta.json()["token"]
