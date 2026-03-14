"""SQLite database initialisation and seeding."""
import sqlite3
import threading
from pathlib import Path
from passlib.context import CryptContext
from app.config import DB_PATH

_local = threading.local()
pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_connection() -> sqlite3.Connection:
    """Return a per-thread SQLite connection (WAL mode, foreign keys on)."""
    if not hasattr(_local, "conn"):
        conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        _local.conn = conn
    return _local.conn


def close_connection() -> None:
    """Close the per-thread connection if open."""
    if hasattr(_local, "conn"):
        _local.conn.close()
        del _local.conn


def init_db() -> None:
    """Create tables if they don't exist and seed default data."""
    conn = get_connection()
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS users (
            id          TEXT PRIMARY KEY,
            username    TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role        TEXT NOT NULL CHECK(role IN ('central','repartidor')),
            name        TEXT NOT NULL,
            created_at  TEXT DEFAULT (datetime('now'))
        );

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

        CREATE TABLE IF NOT EXISTS routes (
            id          TEXT PRIMARY KEY,
            driver_id   TEXT NOT NULL REFERENCES users(id),
            order_ids   TEXT NOT NULL DEFAULT '[]',
            status      TEXT NOT NULL DEFAULT 'active'
                CHECK(status IN ('active','completed')),
            created_at  TEXT DEFAULT (datetime('now')),
            updated_at  TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS driver_locations (
            driver_id   TEXT PRIMARY KEY REFERENCES users(id),
            lat         REAL NOT NULL,
            lng         REAL NOT NULL,
            heading     REAL DEFAULT 0,
            updated_at  TEXT DEFAULT (datetime('now'))
        );
        """
    )
    conn.commit()
    _seed(conn)


def _seed(conn: sqlite3.Connection) -> None:
    """Insert default users and demo data on first run."""
    count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    if count > 0:
        return

    users = [
        ("central-1", "central",  pwd_ctx.hash("central123"), "central",     "Central Dispatch"),
        ("driver-1",  "driver1",  pwd_ctx.hash("driver123"),  "repartidor",  "Carlos García"),
        ("driver-2",  "driver2",  pwd_ctx.hash("driver123"),  "repartidor",  "María López"),
    ]
    conn.executemany(
        "INSERT INTO users (id,username,password_hash,role,name) VALUES (?,?,?,?,?)",
        users,
    )

    # Demo deliveries + one pending pickup
    orders = [
        ("order-1","delivery","Calle Gran Via 1, Madrid",      40.4168,-3.7038,"assigned","driver-1"),
        ("order-2","delivery","Calle Alcalá 50, Madrid",       40.4189,-3.6929,"assigned","driver-1"),
        ("order-3","delivery","Paseo Castellana 100, Madrid",  40.4356,-3.6882,"assigned","driver-1"),
        ("order-4","delivery","Calle Serrano 20, Madrid",      40.4259,-3.6887,"assigned","driver-2"),
        ("order-5","delivery","Calle Goya 30, Madrid",         40.4238,-3.6797,"assigned","driver-2"),
        ("order-6","pickup",  "Calle Fuencarral 80, Madrid",   40.4277,-3.7025,"pending", None),
    ]
    conn.executemany(
        "INSERT INTO orders (id,type,address,lat,lng,status,assigned_driver_id) "
        "VALUES (?,?,?,?,?,?,?)",
        orders,
    )

    conn.executemany(
        "INSERT INTO routes (id,driver_id,order_ids,status) VALUES (?,?,?,?)",
        [
            ("route-1","driver-1",'["order-1","order-2","order-3"]',"active"),
            ("route-2","driver-2",'["order-4","order-5"]',"active"),
        ],
    )

    conn.executemany(
        "INSERT INTO driver_locations (driver_id,lat,lng) VALUES (?,?,?)",
        [
            ("driver-1", 40.4168, -3.7038),
            ("driver-2", 40.4259, -3.6887),
        ],
    )
    conn.commit()
