from neo4j import GraphDatabase
from passlib.context import CryptContext
from app.config import NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE

contexto_contrasena = CryptContext(schemes=["bcrypt"], deprecated="auto")
_driver = None

DEMO_DRIVER_ID = "driver-demo"
DEMO_DRIVER_USERNAME = "drivertest"
DEMO_DRIVER_FALLBACK_USERNAME = "driverdemo"
DEMO_DRIVER_PASSWORD = "driver123"


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
        session.run("CREATE CONSTRAINT auditevent_id_unique IF NOT EXISTS FOR (ae:AuditEvent) REQUIRE ae.id IS UNIQUE")
        session.run("CREATE CONSTRAINT simulationrun_id_unique IF NOT EXISTS FOR (sr:SimulationRun) REQUIRE sr.id IS UNIQUE")
        session.run("CREATE INDEX order_status_idx IF NOT EXISTS FOR (o:Order) ON (o.status)")
        session.run("CREATE INDEX auditevent_order_idx IF NOT EXISTS FOR (ae:AuditEvent) ON (ae.order_id)")
        session.run("CREATE INDEX route_status_idx IF NOT EXISTS FOR (r:Route) ON (r.status)")

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
        _asegurar_repartidor_demo(session)
        _asegurar_rutas_repartidores(session)
        return

    usuarios = [
        {"id": "central-1", "username": "central", "password_hash": contexto_contrasena.hash("central123"), "role": "central", "name": "Central Despacho", "is_available": False},
        {"id": "driver-1", "username": "driver1", "password_hash": contexto_contrasena.hash("driver123"), "role": "repartidor", "name": "Carlos García", "is_available": False},
        {"id": "driver-2", "username": "driver2", "password_hash": contexto_contrasena.hash("driver123"), "role": "repartidor", "name": "María López", "is_available": False},
        {"id": DEMO_DRIVER_ID, "username": DEMO_DRIVER_USERNAME, "password_hash": contexto_contrasena.hash(DEMO_DRIVER_PASSWORD), "role": "repartidor", "name": "Repartidor Demo", "is_available": False},
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

    # Cargar pedidos y rutas desde el CSV
    import os
    import csv
    
    app_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    csv_path = os.path.join(app_dir, "scripts", "rutas_seed_data.csv")
    
    pedidos = []
    rutas = []
    
    if os.path.exists(csv_path):
        with open(csv_path, mode="r", encoding="utf-8") as f:
            section = None
            reader = csv.reader(f)
            headers = []
            for row in reader:
                if not row or not row[0] or row[0].strip().startswith("#"):
                    continue
                # Detectar sección
                row_cleaned = [item.strip() for item in row]
                if "id" in row_cleaned[0] and "type" in row_cleaned:
                    section = "pedidos"
                    headers = row_cleaned
                    continue
                elif "route_id" in row_cleaned[0] and "route_driver" in row_cleaned:
                    section = "rutas"
                    headers = row_cleaned
                    continue
                
                # Procesar fila
                if not headers:
                    continue
                data = {headers[i]: row_cleaned[i] for i in range(min(len(row_cleaned), len(headers)))}
                if section == "pedidos":
                    pedidos.append(data)
                elif section == "rutas":
                    rutas.append(data)
    
    # Si no existe el CSV o falló por algún motivo, usar fallback hardcoded
    if not pedidos:
        pedidos = [
            {"id": "order-1", "type": "delivery", "name": "Restaurante El Prado", "address": "Calle Iglesia 15, Pineda de Mar", "lat": "41.6262", "lng": "2.6908", "status": "assigned", "driver_id": "driver-1"},
            {"id": "order-2", "type": "delivery", "name": "Librería Central", "address": "Calle Mayor 45, Pineda de Mar", "lat": "41.6258", "lng": "2.6875", "status": "assigned", "driver_id": "driver-1"},
            {"id": "order-3", "type": "delivery", "name": "Farmacia Serrano", "address": "Avenida Montserrat 8, Pineda de Mar", "lat": "41.6291", "lng": "2.6844", "status": "pending", "driver_id": ""},
            {"id": "order-4", "type": "delivery", "name": "Tienda Zara", "address": "Calle Iglesia 120, Calella", "lat": "41.6145", "lng": "2.6591", "status": "pending", "driver_id": ""},
            {"id": "order-5", "type": "delivery", "name": "Supermercado Día", "address": "Calle Riera 30, Calella", "lat": "41.6128", "lng": "2.6548", "status": "pending", "driver_id": ""},
            {"id": "order-6", "type": "pickup", "name": "Cafetería Starbucks", "address": "Paseo Marítimo 50, Pineda de Mar", "lat": "41.6235", "lng": "2.6932", "status": "pending", "driver_id": ""},
        ]
    if not rutas:
        rutas = [
            {"route_id": "route-1", "route_driver": "driver-1", "route_orders": "order-1|order-2", "route_status": "active"},
            {"route_id": "route-2", "route_driver": "driver-2", "route_orders": "", "route_status": "active"},
        ]

    # Crear los pedidos en Neo4j
    for p in pedidos:
        driver_id = p.get("driver_id")
        driver_id = driver_id if (driver_id and driver_id != "None" and driver_id != "") else None
        
        # Convertir coordenadas
        try:
            lat_val = float(p["lat"])
            lng_val = float(p["lng"])
        except Exception:
            lat_val = 0.0
            lng_val = 0.0
            
        # Peso
        peso_val = None
        if p.get("peso") and p["peso"].strip() != "":
            try:
                peso_val = float(p["peso"])
            except Exception:
                pass

        session.run("""
            MATCH (c:Company {id: 'pae-logistics'})
            CREATE (o:Order {
                id: $id, 
                type: $type, 
                name: $name,
                address: $address, 
                lat: $lat, 
                lng: $lng, 
                status: $status,
                incoterm: $incoterm,
                origen: $origen,
                destino: $destino,
                tipo_bulto: $tipo_bulto,
                dimensiones: $dimensiones,
                peso: $peso,
                es_adr: $es_adr,
                adr_tipo: $adr_tipo,
                adr_codigo_un: $adr_codigo_un,
                cliente_nombre: $cliente_nombre,
                cliente_contacto: $cliente_contacto,
                destinatario_nombre: $destinatario_nombre,
                destinatario_contacto: $destinatario_contacto,
                created_at: datetime(),
                updated_at: datetime()
            })
            CREATE (o)-[:BELONGS_TO]->(c)
            WITH o
            WHERE $driver_id IS NOT NULL
            MATCH (u:User {id: $driver_id})
            CREATE (u)-[:ASSIGNED_TO]->(o)
        """, {
            "id": p["id"],
            "type": p["type"],
            "name": p.get("name"),
            "address": p["address"],
            "lat": lat_val,
            "lng": lng_val,
            "status": p["status"],
            "driver_id": driver_id,
            "incoterm": p.get("incoterm"),
            "origen": p.get("origen"),
            "destino": p.get("destino"),
            "tipo_bulto": p.get("tipo_bulto"),
            "dimensiones": p.get("dimensiones"),
            "peso": peso_val,
            "es_adr": p.get("es_adr") == "true",
            "adr_tipo": p.get("adr_tipo"),
            "adr_codigo_un": p.get("adr_codigo_un"),
            "cliente_nombre": p.get("cliente_nombre"),
            "cliente_contacto": p.get("cliente_contacto"),
            "destinatario_nombre": p.get("destinatario_nombre"),
            "destinatario_contacto": p.get("destinatario_contacto"),
        })

    for r in rutas:
        order_ids = [oid for oid in r.get("route_orders", "").split("|") if oid]
        session.run("""
            MATCH (u:User {id: $driver_id})
            CREATE (u)-[:HAS_ROUTE]->(rt:Route {
                id: $id,
                order_ids: $order_ids,
                status: $status,
                created_at: datetime(),
                updated_at: datetime()
            })
        """, {
            "driver_id": r["route_driver"],
            "id": r["route_id"],
            "order_ids": order_ids,
            "status": r["route_status"],
        })

    ubicaciones = [
        {"driver_id": "driver-1", "lat": 41.6260, "lng": 2.6900},
        {"driver_id": "driver-2", "lat": 41.6140, "lng": 2.6580},
        {"driver_id": DEMO_DRIVER_ID, "lat": 41.6262, "lng": 2.6880},
    ]
    for loc in ubicaciones:
        session.run("""
            MATCH (u:User {id: $driver_id})
            SET u.lat = $lat, u.lng = $lng, u.heading = 0, u.location_updated_at = datetime()
        """, loc)


def _asegurar_repartidor_demo(session):
    password_hash = contexto_contrasena.hash(DEMO_DRIVER_PASSWORD)
    session.run("""
        OPTIONAL MATCH (existing_username:User {username: $username})
        WITH existing_username
        MERGE (u:User {id: $id})
        ON CREATE SET
            u.username = CASE
                WHEN existing_username IS NULL OR existing_username.id = $id THEN $username
                ELSE $fallback_username
            END,
            u.password_hash = $password_hash,
            u.role = 'repartidor',
            u.name = 'Repartidor Demo',
            u.is_available = false,
            u.created_at = datetime()
        SET u.role = 'repartidor',
            u.name = coalesce(u.name, 'Repartidor Demo'),
            u.username = coalesce(u.username, CASE
                WHEN existing_username IS NULL OR existing_username.id = $id THEN $username
                ELSE $fallback_username
            END),
            u.password_hash = coalesce(u.password_hash, $password_hash)
        WITH u
        MATCH (c:Company {id: 'pae-logistics'})
        MERGE (u)-[:BELONGS_TO]->(c)
    """, {
        "id": DEMO_DRIVER_ID,
        "username": DEMO_DRIVER_USERNAME,
        "fallback_username": DEMO_DRIVER_FALLBACK_USERNAME,
        "password_hash": password_hash,
    })


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
