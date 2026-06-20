"""
Simulación de demo PAE — driver1 (Carlos García), driver2 (María López) y drivertest (Repartidor Demo).

Requisitos:
  - Backend corriendo en http://localhost:8000
  - Neo4j corriendo con la BD inicializada

Uso:
  cd ProyectoPAE
  python scripts/simulate_demo.py

Opciones:
  python scripts/simulate_demo.py --auto         # Ejecuta todo sin pausas interactivas
  python scripts/simulate_demo.py --no-reset     # Salta el reseteo de la base de datos
  python scripts/simulate_demo.py -d 1.0         # Ajusta el delay de simulación en modo auto
"""

import sys
import os
import time
import requests
import math
import subprocess
import argparse
import random

# Configurar stdout para usar UTF-8 en Windows para evitar errores con emojis y caracteres especiales
try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

# ─── Configuración ─────────────────────────────────────────────────────────────
API = os.getenv("API_BASE_URL", "http://localhost:8000")
STEP_DELAY = 1.0  # segundos entre cada paso de la simulación en modo automático o tick
INTERACTIVE_MODE = True


# ─── Colores para la consola ───────────────────────────────────────────────────
class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    GREEN = "\033[92m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    YELLOW = "\033[93"
    RED = "\033[91m"
    MAGENTA = "\033[95m"
    GRAY = "\033[90m"


def step(msg):
    print(f"\n{C.CYAN}{C.BOLD}══> {msg}{C.RESET}")


def info(msg):
    print(f"  {C.GREEN}✓{C.RESET} {msg}")


def warn(msg):
    print(f"  {C.YELLOW}⚠{C.RESET} {msg}")


def driver_log(name, msg):
    color = C.BLUE if "Carlos" in name else (C.MAGENTA if "María" in name else C.YELLOW)
    print(f"  {color}🚚 [{name}]{C.RESET} {msg}")


def central_log(msg):
    print(f"  {C.CYAN}🏢 [Central]{C.RESET} {msg}")


# ─── Helpers HTTP ──────────────────────────────────────────────────────────────
def login(username, password):
    r = requests.post(f"{API}/auth/login", json={"username": username, "password": password})
    r.raise_for_status()
    data = r.json()
    return data["token"], data["user"]


def headers(token):
    return {"Authorization": f"Bearer {token}"}


def api_get(endpoint, token):
    r = requests.get(f"{API}{endpoint}", headers=headers(token))
    r.raise_for_status()
    return r.json()


def api_post(endpoint, token, json_data=None):
    r = requests.post(f"{API}{endpoint}", headers=headers(token), json=json_data or {})
    r.raise_for_status()
    return r.json()


def api_put(endpoint, token, json_data=None):
    r = requests.put(f"{API}{endpoint}", headers=headers(token), json=json_data or {})
    r.raise_for_status()
    return r.json()


def api_patch(endpoint, token, json_data=None):
    r = requests.patch(f"{API}{endpoint}", headers=headers(token), json=json_data or {})
    r.raise_for_status()
    return r.json()


def wait(seconds=None):
    time.sleep(seconds or STEP_DELAY)


def next_step(title):
    global INTERACTIVE_MODE
    print(f"\n{C.CYAN}{C.BOLD}══> {title}{C.RESET}")
    if not INTERACTIVE_MODE:
        wait(STEP_DELAY)
    else:
        try:
            val = input(f"  {C.YELLOW}👉 Presiona [Enter] para avanzar (o escribe 'auto' para omitir pausas): {C.RESET}").strip().lower()
            if val == 'auto':
                INTERACTIVE_MODE = False
                print(f"  {C.GREEN}✓ Modo automático activado para el resto de la simulación.{C.RESET}\n")
                wait(STEP_DELAY)
        except (EOFError, KeyboardInterrupt):
            print(f"\n{C.YELLOW}Simulación cancelada por el usuario.{C.RESET}")
            sys.exit(0)


# ─── Tablas y Visuales de Estado del Sistema ──────────────────────────────────
def print_status_table(token):
    try:
        orders = api_get("/orders/", token)
        drivers = api_get("/drivers/", token)
        
        print(f"\n  {C.BOLD}┌─ Estado de Pedidos ────────────────────────────────────────────────────────┐{C.RESET}")
        print(f"  {C.BOLD}│ ID         │ Nombre/Cliente       │ Tipo     │ Estado      │ Repartidor      │{C.RESET}")
        print(f"  {C.BOLD}├────────────┼──────────────────────┼──────────┼─────────────┼─────────────────┤{C.RESET}")
        for o in orders:
            oid = o.get("id", "")[:10]
            name = o.get("name", "N/A")[:20]
            type_str = o.get("type", "N/A")
            status = o.get("status", "pending")
            driver_id = o.get("assigned_driver_id")
            
            status_color = C.GRAY
            if status == "completed":
                status_color = C.GREEN
            elif status == "in_progress":
                status_color = C.BLUE
            elif status == "assigned":
                status_color = C.YELLOW
            
            driver_name = "Ninguno"
            if driver_id:
                for d in drivers:
                    if d["id"] == driver_id:
                        driver_name = d["name"]
                        break
            driver_name = driver_name[:15]
            
            print(f"  │ {oid:<10} │ {name:<20} │ {type_str:<8} │ {status_color}{status:<11}{C.RESET} │ {driver_name:<15} │")
        print(f"  {C.BOLD}└────────────────────────────────────────────────────────────────────────────┘{C.RESET}")

        print(f"  {C.BOLD}┌─ Estado de Conductores ────────────────────────────────────────────────────┐{C.RESET}")
        print(f"  {C.BOLD}│ ID         │ Nombre               │ Estado       │ Ubicación        │ Eficiencia │{C.RESET}")
        print(f"  {C.BOLD}├────────────┼──────────────────────┼──────────────┼──────────────────┼────────────┤{C.RESET}")
        for d in drivers:
            did = d.get("id", "")[:10]
            name = d.get("name", "N/A")[:20]
            avail = d.get("is_available", False)
            lat = d.get("lat")
            lng = d.get("lng")
            eff = d.get("load_efficiency_percent")
            
            avail_pad = "Activo" if avail else "Inactivo"
            avail_color = C.GREEN if avail else C.RED
            avail_display = f"{avail_color}{avail_pad:<12}{C.RESET}"
            loc_str = f"{lat:.4f},{lng:.4f}" if lat is not None else "Sin GPS"
            eff_str = f"{eff:.1f}%" if eff is not None else "N/A"
            
            print(f"  │ {did:<10} │ {name:<20} │ {avail_display} │ {loc_str:<16} │ {eff_str:<10} │")
        print(f"  {C.BOLD}└────────────────────────────────────────────────────────────────────────────┘{C.RESET}")
    except Exception as e:
        warn(f"No se pudo imprimir la tabla de estado: {e}")


# ─── Movimiento GPS simulado ──────────────────────────────────────────────────
def interpolate_points(start, end, steps=5):
    """Genera puntos intermedios entre start y end."""
    points = []
    for i in range(1, steps + 1):
        t = i / steps
        lat = start[0] + (end[0] - start[0]) * t
        lng = start[1] + (end[1] - start[1]) * t
        points.append((lat, lng))
    return points


def send_location(token, driver_id, lat, lng):
    """Actualiza la ubicación GPS de un driver."""
    api_put(f"/drivers/{driver_id}/location", token, {
        "lat": lat,
        "lng": lng,
        "heading": 0.0,
    })


def print_progress(name, current, total, lat, lng, type_str="vial"):
    percent = int(current / total * 100)
    bar_length = 20
    filled_length = int(bar_length * current // total)
    bar = "█" * filled_length + "░" * (bar_length - filled_length)
    color = C.BLUE if "Carlos" in name else (C.MAGENTA if "María" in name else C.YELLOW)
    sys.stdout.write(f"\r  {color}🚚 [{name}]{C.RESET} Tránsito {type_str} [{bar}] {percent}% | GPS: {lat:.4f}, {lng:.4f}  ")
    sys.stdout.flush()
    if current == total:
        sys.stdout.write("\n")


def move_driver_along_geometry(name, token, driver_id, start_pos, geometry, steps=10):
    sampled_points = []
    n = len(geometry)
    if n <= steps:
        sampled_points = geometry
    else:
        for idx in range(steps):
            sampled_idx = int(idx * (n - 1) / (steps - 1))
            sampled_points.append(geometry[sampled_idx])
            
    for idx, pt in enumerate(sampled_points):
        lat = pt["lat"]
        lng = pt["lng"]
        send_location(token, driver_id, lat, lng)
        print_progress(name, idx + 1, len(sampled_points), lat, lng, "vial (OSRM)")
        time.sleep(0.2)


def move_driver_lineal(name, token, driver_id, start_pos, end_pos, steps=10):
    points = interpolate_points(start_pos, end_pos, steps)
    for idx, pt in enumerate(points):
        lat, lng = pt
        send_location(token, driver_id, lat, lng)
        print_progress(name, idx + 1, len(points), lat, lng, "lineal")
        time.sleep(0.2)


def move_driver_along_route_plan(name, token, driver_id, current_pos, steps=10):
    try:
        route_plan = api_get(f"/orders/route/{driver_id}", token)
        geometry = route_plan.get("route_geometry", [])
        if geometry:
            move_driver_along_geometry(name, token, driver_id, current_pos, geometry, steps)
            return geometry[-1]
    except Exception as e:
        warn(f"No se pudo simular movimiento vial OSRM para {name}: {e}")
    return None


def create_random_order(token):
    """Crea un pedido express aleatorio en Pineda, Calella o Canet de Mar."""
    cities = [
        {
            "name": "Pineda de Mar",
            "lat_range": (41.6220, 41.6290),
            "lng_range": (2.6850, 2.6950),
            "addresses": ["Carrer de Mar", "Calle Mayor", "Avinguda Montserrat", "Carrer Església", "Carrer Santiago Rusiñol"]
        },
        {
            "name": "Calella",
            "lat_range": (41.6110, 41.6180),
            "lng_range": (2.6520, 2.6650),
            "addresses": ["Carrer Sant Jaume", "Calle Riera", "Carrer de l'Església", "Avinguda del Valès", "Carrer Jovara"]
        },
        {
            "name": "Canet de Mar",
            "lat_range": (41.5850, 41.5930),
            "lng_range": (2.5720, 2.5830),
            "addresses": ["Carrer Ample", "Riera de Sant Domenech", "Carrer de la Font", "Carrer de Mar", "Carrer Vall"]
        }
    ]
    
    city = random.choice(cities)
    lat = round(random.uniform(*city["lat_range"]), 6)
    lng = round(random.uniform(*city["lng_range"]), 6)
    street = random.choice(city["addresses"])
    number = random.randint(1, 150)
    address = f"{street} {number}, {city['name']}"
    
    order_type = random.choice(["pickup", "delivery"])
    commerces = ["Supermercado", "Restaurante", "Farmacia", "Ferretería", "Panadería", "Librería", "Cafetería", "Floristería", "Pizzería"]
    names = ["Gourmet", "Express", "Central", "Familiar", "del Barrio", "24h", "Eco", "Premium", "Estrella"]
    order_name = f"{random.choice(commerces)} {random.choice(names)} {city['name']}"
    
    order_data = {
        "type": order_type,
        "name": order_name,
        "address": address,
        "lat": lat,
        "lng": lng
    }
    
    try:
        created = api_post("/orders/", token, order_data)
        driver_id = created.get("assigned_driver_id")
        assigned_name = "Ninguno"
        if driver_id:
            drivers = api_get("/drivers/", token)
            for d in drivers:
                if d["id"] == driver_id:
                    assigned_name = d["name"]
                    break
        
        print(f"\n  {C.YELLOW}{C.BOLD}⚡ [SIMULACIÓN DINÁMICA] ¡Pedido Express Generado!{C.RESET}")
        central_log(f"Pedido: {created['id'][:8]} — {order_name} ({order_type.upper()})")
        central_log(f"Ubicación: {address} ({lat:.4f}, {lng:.4f})")
        central_log(f"Asignado automáticamente por Backhauling 🤖: {C.GREEN}{assigned_name}{C.RESET}")
        return created
    except Exception as e:
        warn(f"No se pudo crear el pedido aleatorio: {e}")
        return None


# ═══════════════════════════════════════════════════════════════════════════════
#  SIMULACIÓN PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    global INTERACTIVE_MODE, STEP_DELAY
    parser = argparse.ArgumentParser(description="Simulación de demo PAE — repartidores y central.")
    parser.add_argument("--delay", "-d", type=float, default=1.0, help="Segundos entre cada paso en modo automático o tick.")
    parser.add_argument("--no-reset", "-n", action="store_true", help="Evita resetear la base de datos.")
    parser.add_argument("--auto", "-a", action="store_true", help="Ejecuta la simulación completa sin pausas interactivas.")
    args = parser.parse_args()

    STEP_DELAY = args.delay
    INTERACTIVE_MODE = not args.auto

    print(f"\n{C.BOLD}{'═' * 70}{C.RESET}")
    print(f"{C.BOLD}{C.CYAN}   SIMULACIÓN COMPLETA DE DEMO PAE — Gestión y Backhauling de Rutas{C.RESET}")
    print(f"{C.BOLD}{'═' * 70}{C.RESET}")
    if INTERACTIVE_MODE:
        print(f" {C.YELLOW}ℹ Modo interactivo activo. Abre la app móvil o central para ver los cambios.{C.RESET}")
        print(f"   Podrás presionar Enter para pasar al siguiente evento y ver cómo interactúan.")
    else:
        print(f" {C.GREEN}ℹ Modo automático activo con delay de {STEP_DELAY}s.{C.RESET}")

    # ── 1. Verificar Backend ──────────────────────────────────────────────────
    step("Verificando conexión con el backend...")
    try:
        r = requests.get(f"{API}/health", timeout=5)
        if r.status_code == 200:
            info(f"Backend disponible en {API}")
        else:
            warn(f"Backend respondió con estado inesperado {r.status_code}")
    except requests.ConnectionError:
        print(f"\n  {C.RED}✗ Error: No se puede conectar al servidor backend en {API}{C.RESET}")
        print(f"  {C.GRAY}Asegúrate de iniciar el backend con:")
        print(f"    cd backend && python -m uvicorn app.main:aplicacion --reload --port 8000{C.RESET}")
        sys.exit(1)

    # ── 2. Resetear Base de Datos ──────────────────────────────────────────────
    if not args.no_reset:
        step("Reseteando y sembrando base de datos Neo4j...")
        try:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            reset_script = os.path.abspath(os.path.join(script_dir, "..", "backend", "reset_db.py"))
            venv_python = os.path.abspath(os.path.join(script_dir, "..", "backend", ".venv", "Scripts", "python.exe"))
            python_cmd = venv_python if os.path.exists(venv_python) else sys.executable
            
            if os.path.exists(reset_script):
                subprocess.run(
                    [python_cmd, "reset_db.py"],
                    cwd=os.path.abspath(os.path.join(script_dir, "..", "backend")),
                    capture_output=True,
                    text=True,
                    check=True
                )
                info("¡Base de datos Neo4j limpia y sembrada con datos iniciales de Pineda/Calella!")
            else:
                warn(f"No se localizó el script de reseteo en: {reset_script}")
        except Exception as e:
            warn(f"No se pudo ejecutar reset_db.py de forma automática: {e}")
    else:
        info("Omitiendo el reseteo de la base de datos (--no-reset).")

    # ── 3. Login ──────────────────────────────────────────────────────────────
    next_step("Iniciando sesión con los usuarios de prueba...")
    
    central_token, central_user = login("central", "central123")
    info(f"Central: {central_user['name']} (ID: {central_user['id']})")

    d1_token, d1_user = login("driver1", "driver123")
    info(f"Driver 1: {d1_user['name']} (ID: {d1_user['id']})")

    d2_token, d2_user = login("driver2", "driver123")
    info(f"Driver 2: {d2_user['name']} (ID: {d2_user['id']})")

    try:
        d3_token, d3_user = login("drivertest", "driver123")
    except Exception:
        d3_token, d3_user = login("driverdemo", "driver123")
    info(f"Driver 3 (Demo): {d3_user['name']} (ID: {d3_user['id']})")

    # ── 4. Iniciar Jornada Laboral ─────────────────────────────────────────────
    next_step("Activando jornada laboral de los 3 repartidores...")
    
    for name, token, user in [
        ("Carlos García", d1_token, d1_user),
        ("María López", d2_token, d2_user),
        ("Repartidor Demo", d3_token, d3_user),
    ]:
        try:
            active = api_get("/drivers/me/jornada/active", token)
            if active:
                driver_log(name, "Ya tiene una jornada de trabajo activa")
                continue
        except Exception:
            pass
        
        try:
            api_post("/drivers/me/jornada/start", token)
            driver_log(name, "¡Jornada de trabajo iniciada! 🟢 (Estado disponible)")
        except requests.HTTPError as e:
            if e.response.status_code == 409:
                driver_log(name, "Ya tiene jornada de trabajo activa")
            else:
                raise

    # ── 5. Enviar Ubicaciones GPS Iniciales y Aceptar Pedidos Iniciales ─────────
    next_step("Estableciendo posiciones GPS iniciales...")

    # Carlos (Pineda Almacén)
    d1_pos = (41.6260, 2.6900)
    send_location(d1_token, d1_user["id"], *d1_pos)
    driver_log("Carlos García", f"GPS: {d1_pos[0]:.4f}, {d1_pos[1]:.4f} (Almacén central Pineda)")

    # María (Calella Entrada)
    d2_pos = (41.6140, 2.6580)
    send_location(d2_token, d2_user["id"], *d2_pos)
    driver_log("María López", f"GPS: {d2_pos[0]:.4f}, {d2_pos[1]:.4f} (Calella)")

    # Repartidor Demo (Canet de Mar)
    d3_pos = (41.5900, 2.5800)
    send_location(d3_token, d3_user["id"], *d3_pos)
    driver_log("Repartidor Demo", f"GPS: {d3_pos[0]:.4f}, {d3_pos[1]:.4f} (Canet de Mar)")

    # Los conductores aceptan sus pedidos iniciales asignados en la base de datos
    orders = api_get("/orders/", central_token)
    for token, uid, name in [
        (d1_token, d1_user["id"], "Carlos García"),
        (d2_token, d2_user["id"], "María López"),
        (d3_token, d3_user["id"], "Repartidor Demo"),
    ]:
        assigned = [o for o in orders if o.get("assigned_driver_id") == uid and o["status"] == "assigned"]
        for o in assigned:
            try:
                api_post(f"/orders/{o['id']}/respond", token, {"accepted": True})
                driver_log(name, f"Acepta pedido inicial {o['id']} ({o.get('name')}) ✅")
            except Exception as e:
                warn(f"No se pudo aceptar el pedido inicial {o['id']} para {name}: {e}")

    print_status_table(central_token)

    # ── 6. Línea de Tiempo de Reparto Unificada (Simulación Dinámica) ─────────────
    next_step("Iniciando línea de tiempo de reparto y creación dinámica de pedidos...")
    print("  (Los conductores avanzan por sus rutas. Central creará nuevos pedidos calientes")
    print("   que se auto-asignarán, se aceptarán y replanificarán las rutas sobre la marcha.)")
    print(f"  {C.YELLOW}ℹ La simulación correrá automáticamente segundo a segundo para mostrar la animación en el mapa.{C.RESET}")

    # Guardar estado de la ruta de cada conductor para controlar el progreso
    driver_routes = {
        d1_user["id"]: {"geometry": [], "index": 0, "order_ids": []},
        d2_user["id"]: {"geometry": [], "index": 0, "order_ids": []},
        d3_user["id"]: {"geometry": [], "index": 0, "order_ids": []},
    }

    # Nuevos pedidos a crear en caliente durante la simulación en puntos estratégicos
    hot_orders = [
        {"step": 2, "data": {"type": "delivery", "name": "Comercio Pineda Express", "address": "Carrer de Mar 25, Pineda", "lat": 41.6240, "lng": 2.6885}, "expected": "Carlos García (driver1)"},
        {"step": 4, "data": {"type": "delivery", "name": "Tienda Calella Express", "address": "Carrer Sant Jaume 100, Calella", "lat": 41.6150, "lng": 2.6605}, "expected": "María López (driver2)"},
        {"step": 6, "data": {"type": "delivery", "name": "Café Canet Express", "address": "Carrer Ample 5, Canet de Mar", "lat": 41.5870, "lng": 2.5750}, "expected": "Repartidor Demo (drivertest)"},
        {"step": 8, "data": {"type": "pickup", "name": "Supermercado Día Calella", "address": "Calle Riera 30, Calella", "lat": 41.6128, "lng": 2.6548}, "expected": "María López (driver2)"},
        {"step": 10, "data": {"type": "pickup", "name": "Librería Central Pineda", "address": "Calle Mayor 45, Pineda", "lat": 41.6258, "lng": 2.6875}, "expected": "Carlos García (driver1)"},
    ]

    total_ticks = 20
    for tick in range(1, total_ticks + 1):
        print(f"\n{C.BOLD}⏰ [TICK SIMULADO: {tick}/{total_ticks} | Frecuencia: {STEP_DELAY}s]{C.RESET}")
        
        # 1. Crear pedidos express predefinidos según el tick de la línea de tiempo
        for ho in hot_orders:
            if ho["step"] == tick:
                print(f"  {C.YELLOW}{C.BOLD}⚡ [EVENTO CENTRAL] Creando pedido express sobre la marcha...{C.RESET}")
                try:
                    created = api_post("/orders/", central_token, ho["data"])
                    driver_id = created.get("assigned_driver_id")
                    assigned_name = "Ninguno"
                    if driver_id == d1_user["id"]:
                        assigned_name = "Carlos García"
                    elif driver_id == d2_user["id"]:
                        assigned_name = "María López"
                    elif driver_id == d3_user["id"]:
                        assigned_name = "Repartidor Demo"
                    central_log(f"Pedido express creado: {created['id'][:8]} — {ho['data']['name']}")
                    central_log(f"Asignado dinámicamente por Backhauling 🤖: {C.GREEN}{assigned_name}{C.RESET} (Esperado: {ho['expected']})")
                except Exception as e:
                    warn(f"No se pudo crear el pedido express predefinido: {e}")

        # 2. Generar pedidos aleatorios cada 4 ticks después del tick 12 para una simulación continua/dinámica rápida
        if tick >= 12 and tick % 4 == 0:
            create_random_order(central_token)


        # 3. Actualizar posiciones de los conductores de manera suave y completar entregas
        for name, token, uid in [
            ("Carlos García", d1_token, d1_user["id"]),
            ("María López", d2_token, d2_user["id"]),
            ("Repartidor Demo", d3_token, d3_user["id"]),
        ]:
            try:
                # Obtener la ruta activa del conductor
                plan = api_get(f"/orders/route/{uid}", token)
                orders_list = plan.get("orders", [])
                
                # Auto-aceptar asignaciones nuevas si las hay en la lista
                for o in orders_list:
                    if o["status"] == "assigned":
                        api_post(f"/orders/{o['id']}/respond", token, {"accepted": True})
                        driver_log(name, f"¡Acepta dinámicamente la nueva asignación: {o['id'][:8]}! 📦✅")
                
                # Volver a consultar si hubo cambios aceptados
                if any(o["status"] == "assigned" for o in orders_list):
                    plan = api_get(f"/orders/route/{uid}", token)
                    orders_list = plan.get("orders", [])

                if not orders_list:
                    # Si el conductor no tiene paradas activas, permanece en su sitio y mostramos reposo
                    # Solo imprimimos reposo cada 10 ticks para no saturar la consola
                    if tick % 10 == 0:
                        driver_log(name, "En reposo. Esperando nuevas asignaciones... 💤")
                    continue

                geometry = plan.get("route_geometry", [])
                if not geometry:
                    continue

                geom_pts = [(pt["lat"], pt["lng"]) for pt in geometry]
                current_order_ids = [o["id"] for o in orders_list]
                saved = driver_routes[uid]
                
                # Si las paradas o geometría cambiaron (por nueva asignación o finalización), re-inicializar
                if saved["order_ids"] != current_order_ids or not saved["geometry"]:
                    saved["geometry"] = geom_pts
                    saved["index"] = 0
                    saved["order_ids"] = current_order_ids
                
                geom = saved["geometry"]
                idx = saved["index"]
                
                # Avanzamos un tramo de la geometría restante de forma rápida (un tercio de la ruta restante por tick)
                step_size = max(1, len(geom) // 3)
                new_idx = min(idx + step_size, len(geom) - 1)
                saved["index"] = new_idx


                
                lat, lng = geom[new_idx]
                send_location(token, uid, lat, lng)
                
                # Mostrar progreso visual en consola
                print_progress(name, new_idx + 1, len(geom), lat, lng, "vial (OSRM)")
                
                # Verificar llegada al primer destino de su ruta
                target_order = orders_list[0]
                t_lat, t_lng = target_order["lat"], target_order["lng"]
                dist = math.sqrt((lat - t_lat)**2 + (lng - t_lng)**2)
                
                # Si está a menos de ~120 metros o al final de la geometría de este tramo
                if dist < 0.0012 or new_idx >= len(geom) - 1:
                    api_patch(f"/orders/{target_order['id']}/status", token, {"status": "completed"})
                    driver_log(name, f"🏁 ¡Llegó al destino! Pedido {C.GREEN}{target_order['id'][:8]}{C.RESET} ({target_order.get('name', 'N/A')}) completado 📦✅")
                    # Borrar geometría guardada para obligar a recargar la nueva ruta reducida en el siguiente tick
                    saved["geometry"] = []
                    
            except Exception as e:
                warn(f"Error procesando movimiento del repartidor {name}: {e}")

        # Tiempo entre ticks simulados
        time.sleep(STEP_DELAY)

    # Mostrar tablas de estado al finalizar el reparto de la simulación
    print_status_table(central_token)

    # ── 7. KPIs de Eficiencia (Tras terminar la jornada y entregas) ────────────
    next_step("Consultando KPIs de eficiencia y carga finales...")
    print("  (Al estar vacíos los camiones, la eficiencia actual de ruta será de 0.0%,")
    print("   pero el total de pedidos completados durante el día quedará guardado)")

    for name, token, user_id in [
        ("Carlos García", d1_token, d1_user["id"]),
        ("María López", d2_token, d2_user["id"]),
        ("Repartidor Demo", d3_token, d3_user["id"]),
    ]:
        try:
            kpis = api_get(f"/drivers/{user_id}/kpis", token)
            eff = kpis.get("load_efficiency_percent", 0)
            completed = kpis.get("completed_order_count", 0)
            driver_log(name, f"Eficiencia de carga final: {eff:.1f}% | Total completados hoy: {C.GREEN}{completed}{C.RESET} 📦")
        except Exception as e:
            warn(f"No se pudieron obtener métricas KPI finales para {name}: {e}")

    # ── 8. Terminar la Jornada Laboral ────────────────────────────────────────
    next_step("Los conductores terminan su jornada de trabajo al final del día...")

    for name, token in [
        ("Carlos García", d1_token),
        ("María López", d2_token),
        ("Repartidor Demo", d3_token),
    ]:
        try:
            api_post("/drivers/me/jornada/end", token)
            driver_log(name, "¡Jornada de trabajo finalizada y cerrada! 🔴 (Ruta archivada)")
        except Exception as e:
            warn(f"No se pudo cerrar la jornada laboral para {name}: {e}")

    # Mostrar tablas de estado final
    print_status_table(central_token)

    print(f"\n{C.BOLD}{'═' * 70}{C.RESET}")
    print(f"{C.BOLD}{C.GREEN}   🎉 SIMULACIÓN COMPLETADA Y MEJORADA CON ÉXITO{C.RESET}")
    print(f"{C.BOLD}{'═' * 70}{C.RESET}")
    print(f"\n{C.GRAY}Los cambios se han guardado en la base de datos.")
    print(f"Puedes ver la jornada y métricas en las pantallas de Analytics de la central.")
    print(f"El modo interactivo te permitió controlar los eventos de despacho a tu propio ritmo.{C.RESET}\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{C.YELLOW}Simulación cancelada por el usuario.{C.RESET}")
    except requests.HTTPError as e:
        print(f"\n{C.RED}Error de red / API: {e.response.status_code} — {e.response.text}{C.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{C.RED}Error inesperado en la ejecución: {e}{C.RESET}")
        sys.exit(1)
