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
        session.run("CREATE CONSTRAINT company_id_unique IF NOT EXISTS FOR (c:Company) REQUIRE c.id IS UNIQUE")
        session.run("CREATE INDEX order_status_idx IF NOT EXISTS FOR (o:Order) ON (o.status)")

        _sembrar_datos(session)

def _sembrar_datos(session):
    # Asegurar que la compañía demo exista
    session.run("""
        MERGE (c:Company {id: 'pae-logistics'})
        ON CREATE SET c.name = 'PAE Logistics'
    """)

    result = session.run("MATCH (u:User) RETURN count(u) AS count")
    if result.single()["count"] > 0:
        # Vincular usuarios existentes a la compañía
        session.run("""
            MATCH (u:User)
            MATCH (c:Company {id: 'pae-logistics'})
            MERGE (u)-[:BELONGS_TO]->(c)
        """)
        _asegurar_rutas_repartidores(session)
        return

    usuarios = [
        {"id": "central-1", "username": "central", "password_hash": contexto_contrasena.hash("central123"), "role": "central", "name": "Central Despacho", "is_available": False},
        {"id": "driver-1", "username": "driver1", "password_hash": contexto_contrasena.hash("driver123"), "role": "repartidor", "name": "Carlos García", "is_available": False},
        {"id": "driver-2", "username": "driver2", "password_hash": contexto_contrasena.hash("driver123"), "role": "repartidor", "name": "María López", "is_available": False},
    ]
    for u in usuarios:
        session.run("""
            CREATE (u:User {
                id: $id, 
                username: $username, 
                password_hash: $password_hash, 
                role: $role, 
                name: $name,
                is_available: $is_available,
                created_at: datetime()
            })
            WITH u
            MATCH (c:Company {id: 'pae-logistics'})
            CREATE (u)-[:BELONGS_TO]->(c)
        """, u)

    pedidos = [
        {"id": "order-1", "type": "delivery", "name": "Restaurante El Prado", "address": "Calle Iglesia 15, Pineda de Mar", "lat": 41.6262, "lng": 2.6908, "status": "assigned", "driver_id": "driver-1"},
        {"id": "order-2", "type": "delivery", "name": "Librería Central", "address": "Calle Mayor 45, Pineda de Mar", "lat": 41.6258, "lng": 2.6875, "status": "assigned", "driver_id": "driver-1"},
        {"id": "order-3", "type": "delivery", "name": "Farmacia Serrano", "address": "Avenida Montserrat 8, Pineda de Mar", "lat": 41.6291, "lng": 2.6844, "status": "pending", "driver_id": None},
        {"id": "order-4", "type": "delivery", "name": "Tienda Zara", "address": "Calle Iglesia 120, Calella", "lat": 41.6145, "lng": 2.6591, "status": "pending", "driver_id": None},
        {"id": "order-5", "type": "delivery", "name": "Supermercado Día", "address": "Calle Riera 30, Calella", "lat": 41.6128, "lng": 2.6548, "status": "pending", "driver_id": None},
        {"id": "order-6", "type": "pickup", "name": "Cafetería Starbucks", "address": "Paseo Marítimo 50, Pineda de Mar", "lat": 41.6235, "lng": 2.6932, "status": "pending", "driver_id": None},
    ]
    for p in pedidos:
        session.run("""
            CREATE (o:Order {
                id: $id, 
                type: $type, 
                name: $name,
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
        {"id": "route-1", "driver_id": "driver-1", "order_ids": ["order-1", "order-2"], "status": "active"},
        {"id": "route-2", "driver_id": "driver-2", "order_ids": [], "status": "active"},
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
        {"driver_id": "driver-1", "lat": 41.6260, "lng": 2.6900},
        {"driver_id": "driver-2", "lat": 41.6140, "lng": 2.6580},
    ]
    for loc in ubicaciones:
        session.run("""
            MATCH (u:User {id: $driver_id})
            SET u.lat = $lat, u.lng = $lng, u.heading = 0, u.location_updated_at = datetime()
        """, loc)


def _asegurar_rutas_repartidores(session):
    session.run("""
        MATCH (u:User {role: 'repartidor'})
        WHERE NOT (u)-[:HAS_ROUTE]->(:Route {status: 'active'})
        CREATE (u)-[:HAS_ROUTE]->(:Route {
            id: randomUUID(),
            order_ids: [],
            status: 'active',
            created_at: datetime(),
            updated_at: datetime()
        })
    """)
