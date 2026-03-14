"""Inicialización de la base de datos SQLite y carga de datos de prueba.

Utiliza SQLite de la biblioteca estándar de Python (sin dependencias externas)
junto con el modo WAL para mayor rendimiento en concurrencia.
"""
import sqlite3
import threading
from pathlib import Path
from passlib.context import CryptContext
from app.config import RUTA_BD

# Almacenamiento local por hilo para mantener una conexión por hilo de ejecución
_hilo_local = threading.local()

# Contexto de hashing de contraseñas (bcrypt)
contexto_contrasena = CryptContext(schemes=["bcrypt"], deprecated="auto")


def obtener_conexion() -> sqlite3.Connection:
    """Devuelve la conexión SQLite del hilo actual (crea una nueva si no existe).

    Se usa WAL (Write-Ahead Logging) para mejorar la concurrencia en lecturas
    y se activan las claves foráneas para garantizar la integridad referencial.
    """
    if not hasattr(_hilo_local, "conexion"):
        conexion = sqlite3.connect(RUTA_BD, check_same_thread=False)
        # Devuelve filas como objetos similares a diccionarios
        conexion.row_factory = sqlite3.Row
        # Modo WAL: mejora el rendimiento en accesos concurrentes
        conexion.execute("PRAGMA journal_mode=WAL")
        # Activa la comprobación de integridad referencial
        conexion.execute("PRAGMA foreign_keys=ON")
        _hilo_local.conexion = conexion
    return _hilo_local.conexion


def cerrar_conexion() -> None:
    """Cierra la conexión del hilo actual si está abierta."""
    if hasattr(_hilo_local, "conexion"):
        _hilo_local.conexion.close()
        del _hilo_local.conexion


def inicializar_bd() -> None:
    """Crea las tablas si no existen y carga los datos de demostración.

    Esta función se llama automáticamente al arrancar la aplicación
    (ver el ciclo de vida en main.py). Es seguro llamarla varias veces.
    """
    conexion = obtener_conexion()
    conexion.executescript(
        """
        -- Tabla de usuarios: tanto repartidores como operadores centrales
        CREATE TABLE IF NOT EXISTS users (
            id          TEXT PRIMARY KEY,
            username    TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role        TEXT NOT NULL CHECK(role IN ('central','repartidor')),
            name        TEXT NOT NULL,
            created_at  TEXT DEFAULT (datetime('now'))
        );

        -- Tabla de pedidos/recogidas
        -- type: 'delivery' (entrega) o 'pickup' (recogida)
        -- status: ciclo de vida del pedido
        CREATE TABLE IF NOT EXISTS orders (
            id              TEXT PRIMARY KEY,
            type            TEXT NOT NULL CHECK(type IN ('delivery','pickup')),
            address         TEXT NOT NULL,
            lat             REAL NOT NULL,
            lng             REAL NOT NULL,
            status          TEXT NOT NULL DEFAULT 'pending'
                CHECK(status IN ('pending','assigned','in_progress','completed','rejected')),
            assigned_driver_id TEXT REFERENCES users(id),
            estimated_extra_minutes REAL,
            created_at      TEXT DEFAULT (datetime('now')),
            updated_at      TEXT DEFAULT (datetime('now'))
        );

        -- Tabla de rutas activas: lista ordenada de paradas de un repartidor
        CREATE TABLE IF NOT EXISTS routes (
            id          TEXT PRIMARY KEY,
            driver_id   TEXT NOT NULL REFERENCES users(id),
            order_ids   TEXT NOT NULL DEFAULT '[]',  -- JSON array de IDs de pedidos
            status      TEXT NOT NULL DEFAULT 'active'
                CHECK(status IN ('active','completed')),
            created_at  TEXT DEFAULT (datetime('now')),
            updated_at  TEXT DEFAULT (datetime('now'))
        );

        -- Tabla de ubicaciones en tiempo real de los repartidores
        CREATE TABLE IF NOT EXISTS driver_locations (
            driver_id   TEXT PRIMARY KEY REFERENCES users(id),
            lat         REAL NOT NULL,
            lng         REAL NOT NULL,
            heading     REAL DEFAULT 0,   -- dirección de movimiento en grados
            updated_at  TEXT DEFAULT (datetime('now'))
        );
        """
    )
    conexion.commit()
    _sembrar_datos(conexion)


def _sembrar_datos(conexion: sqlite3.Connection) -> None:
    """Inserta usuarios y pedidos de demostración en el primer arranque.

    Solo actúa si la tabla de usuarios está vacía (primera ejecución).
    Los datos de demo permiten probar la aplicación sin configuración adicional.
    """
    conteo = conexion.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    if conteo > 0:
        # La base de datos ya tiene datos → no volver a sembrar
        return

    # Usuarios de demostración: 1 central + 2 repartidores
    usuarios = [
        ("central-1", "central",  contexto_contrasena.hash("central123"), "central",     "Central Despacho"),
        ("driver-1",  "driver1",  contexto_contrasena.hash("driver123"),  "repartidor",  "Carlos García"),
        ("driver-2",  "driver2",  contexto_contrasena.hash("driver123"),  "repartidor",  "María López"),
    ]
    conexion.executemany(
        "INSERT INTO users (id,username,password_hash,role,name) VALUES (?,?,?,?,?)",
        usuarios,
    )

    # Pedidos de demo: entregas asignadas + una recogida pendiente
    pedidos = [
        ("order-1","delivery","Calle Gran Via 1, Madrid",      40.4168,-3.7038,"assigned","driver-1"),
        ("order-2","delivery","Calle Alcalá 50, Madrid",       40.4189,-3.6929,"assigned","driver-1"),
        ("order-3","delivery","Paseo Castellana 100, Madrid",  40.4356,-3.6882,"assigned","driver-1"),
        ("order-4","delivery","Calle Serrano 20, Madrid",      40.4259,-3.6887,"assigned","driver-2"),
        ("order-5","delivery","Calle Goya 30, Madrid",         40.4238,-3.6797,"assigned","driver-2"),
        ("order-6","pickup",  "Calle Fuencarral 80, Madrid",   40.4277,-3.7025,"pending", None),
    ]
    conexion.executemany(
        "INSERT INTO orders (id,type,address,lat,lng,status,assigned_driver_id) "
        "VALUES (?,?,?,?,?,?,?)",
        pedidos,
    )

    # Rutas iniciales para cada repartidor
    conexion.executemany(
        "INSERT INTO routes (id,driver_id,order_ids,status) VALUES (?,?,?,?)",
        [
            ("route-1","driver-1",'["order-1","order-2","order-3"]',"active"),
            ("route-2","driver-2",'["order-4","order-5"]',"active"),
        ],
    )

    # Posiciones iniciales de los repartidores
    conexion.executemany(
        "INSERT INTO driver_locations (driver_id,lat,lng) VALUES (?,?,?)",
        [
            ("driver-1", 40.4168, -3.7038),
            ("driver-2", 40.4259, -3.6887),
        ],
    )
    conexion.commit()
