from neo4j import GraphDatabase
from passlib.context import CryptContext
from app.config import NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE

contexto_contrasena = CryptContext(schemes=["bcrypt"], deprecated="auto")
_driver = None


def obtener_driver():
    global _driver
    if _driver is None:
        _driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
    return _driver


def obtener_conexion():
    return obtener_driver().session(database=NEO4J_DATABASE)


def cerrar_conexion():
    global _driver
    if _driver:
        _driver.close()
        _driver = None


def inicializar_bd():
    driver = obtener_driver()
    with driver.session(database=NEO4J_DATABASE) as session:
        # Crear restricciones de unicidad (equivalente a PRIMARY KEY / UNIQUE)
        session.run("CREATE CONSTRAINT user_id_unique IF NOT EXISTS FOR (u:User) REQUIRE u.id IS UNIQUE")
        session.run("CREATE CONSTRAINT user_username_unique IF NOT EXISTS FOR (u:User) REQUIRE u.username IS UNIQUE")
        session.run("CREATE CONSTRAINT order_id_unique IF NOT EXISTS FOR (o:Order) REQUIRE o.id IS UNIQUE")
        session.run("CREATE CONSTRAINT route_id_unique IF NOT EXISTS FOR (r:Route) REQUIRE r.id IS UNIQUE")
        session.run("CREATE CONSTRAINT jornada_id_unique IF NOT EXISTS FOR (j:Jornada) REQUIRE j.id IS UNIQUE")
        session.run("CREATE INDEX order_status_idx IF NOT EXISTS FOR (o:Order) ON (o.status)")

        _sembrar_datos(session)

def _sembrar_datos(session):
    result = session.run("MATCH (u:User) RETURN count(u) AS count")
    if result.single()["count"] > 0:
        return

    usuarios = [
        {"id": "central-1", "username": "central", "password_hash": contexto_contrasena.hash("central123"), "role": "central", "name": "Central Despacho"},
        {"id": "driver-1", "username": "driver1", "password_hash": contexto_contrasena.hash("driver123"), "role": "repartidor", "name": "Carlos García"},
        {"id": "driver-2", "username": "driver2", "password_hash": contexto_contrasena.hash("driver123"), "role": "repartidor", "name": "María López"},
    ]
    for u in usuarios:
        session.run("""
            CREATE (u:User {
                id: $id, 
                username: $username, 
                password_hash: $password_hash, 
                role: $role, 
                name: $name,
                created_at: datetime()
            })
        """, u)

    pedidos = [
        {"id": "order-1", "type": "delivery", "address": "Calle Gran Via 1, Madrid", "lat": 40.4168, "lng": -3.7038, "status": "assigned", "driver_id": "driver-1"},
        {"id": "order-2", "type": "delivery", "address": "Calle Alcalá 50, Madrid", "lat": 40.4189, "lng": -3.6929, "status": "assigned", "driver_id": "driver-1"},
        {"id": "order-3", "type": "delivery", "address": "Paseo Castellana 100, Madrid", "lat": 40.4356, "lng": -3.6882, "status": "assigned", "driver_id": "driver-1"},
        {"id": "order-4", "type": "delivery", "address": "Calle Serrano 20, Madrid", "lat": 40.4259, "lng": -3.6887, "status": "assigned", "driver_id": "driver-2"},
        {"id": "order-5", "type": "delivery", "address": "Calle Goya 30, Madrid", "lat": 40.4238, "lng": -3.6797, "status": "assigned", "driver_id": "driver-2"},
        {"id": "order-6", "type": "pickup", "address": "Calle Fuencarral 80, Madrid", "lat": 40.4277, "lng": -3.7025, "status": "pending", "driver_id": None},
    ]
    for p in pedidos:
        session.run("""
            CREATE (o:Order {
                id: $id, 
                type: $type, 
                address: $address, 
                lat: $lat, 
                lng: $lng, 
                status: $status,
                created_at: datetime(),
                updated_at: datetime()
            })
            WITH o
            WHERE $driver_id IS NOT NULL
            MATCH (u:User {id: $driver_id})
            CREATE (u)-[:ASSIGNED_TO]->(o)
        """, p)

    rutas = [
        {"id": "route-1", "driver_id": "driver-1", "order_ids": ["order-1", "order-2", "order-3"], "status": "active"},
        {"id": "route-2", "driver_id": "driver-2", "order_ids": ["order-4", "order-5"], "status": "active"},
    ]
    for r in rutas:
        session.run("""
            MATCH (u:User {id: $driver_id})
            CREATE (u)-[:HAS_ROUTE]->(rt:Route {
                id: $id,
                order_ids: $order_ids,
                status: $status,
                created_at: datetime(),
                updated_at: datetime()
            })
        """, r)

    ubicaciones = [
        {"driver_id": "driver-1", "lat": 40.4168, "lng": -3.7038},
        {"driver_id": "driver-2", "lat": 40.4259, "lng": -3.6887},
    ]
    for loc in ubicaciones:
        session.run("""
            MATCH (u:User {id: $driver_id})
            SET u.lat = $lat, u.lng = $lng, u.heading = 0, u.location_updated_at = datetime()
        """, loc)
