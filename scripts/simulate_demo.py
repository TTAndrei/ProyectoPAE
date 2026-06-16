"""
Simulación de demo PAE — driver1 (Carlos García) y driver2 (María López).

Requisitos:
  - Backend corriendo en http://localhost:8000
  - Neo4j corriendo con la BD inicializada

Uso:
  cd ProyectoPAE
  python scripts/simulate_demo.py

El script:
  1. Resetea la BD para empezar limpio
  2. Hace login con central, driver1 y driver2
  3. Los drivers inician jornada y envían ubicación GPS
  4. Central crea pedidos nuevos y los asigna
  5. Los drivers aceptan pedidos
  6. Simula movimiento GPS gradual hacia los destinos
  7. Los drivers completan las entregas
"""

import sys
import os
import time
import requests
import math

# ─── Configuración ─────────────────────────────────────────────────────────────
API = os.getenv("API_BASE_URL", "http://localhost:8000")
STEP_DELAY = 2.0  # segundos entre cada paso de la simulación


# ─── Colores para la consola ───────────────────────────────────────────────────
class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    GREEN = "\033[92m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    YELLOW = "\033[93m"
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
    color = C.BLUE if "Carlos" in name else C.MAGENTA
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


# ═══════════════════════════════════════════════════════════════════════════════
#  SIMULACIÓN PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    print(f"\n{C.BOLD}{'═' * 60}{C.RESET}")
    print(f"{C.BOLD}{C.CYAN}   SIMULACIÓN DEMO PAE — Última Milla{C.RESET}")
    print(f"{C.BOLD}{'═' * 60}{C.RESET}")

    # ── 0. Verificar que el backend está corriendo ─────────────────────────
    step("Verificando backend...")
    try:
        r = requests.get(f"{API}/health", timeout=5)
        if r.status_code == 200:
            info(f"Backend OK en {API}")
        else:
            warn(f"Backend respondió con status {r.status_code}")
    except requests.ConnectionError:
        print(f"\n  {C.RED}✗ No se pudo conectar al backend en {API}{C.RESET}")
        print(f"  {C.GRAY}Asegúrate de que el backend esté corriendo con:")
        print(f"    cd backend && python -m uvicorn app.main:aplicacion --reload --port 8000{C.RESET}")
        sys.exit(1)

    # ── 1. Login ───────────────────────────────────────────────────────────
    step("Iniciando sesión con usuarios demo...")

    central_token, central_user = login("central", "central123")
    info(f"Central: {central_user['name']} (id: {central_user['id']})")

    d1_token, d1_user = login("driver1", "driver123")
    info(f"Driver 1: {d1_user['name']} (id: {d1_user['id']})")

    d2_token, d2_user = login("driver2", "driver123")
    info(f"Driver 2: {d2_user['name']} (id: {d2_user['id']})")

    wait(1)

    # ── 2. Drivers inician jornada ─────────────────────────────────────────
    step("Drivers inician jornada laboral...")

    # Verificar si ya tienen jornada activa
    for name, token, user in [("Carlos García", d1_token, d1_user), ("María López", d2_token, d2_user)]:
        try:
            active = api_get("/drivers/me/jornada/active", token)
            if active:
                driver_log(name, "Ya tiene jornada activa, continuando...")
                continue
        except Exception:
            pass
        try:
            api_post("/drivers/me/jornada/start", token)
            driver_log(name, "¡Jornada iniciada! 🟢")
        except requests.HTTPError as e:
            if e.response.status_code == 409:
                driver_log(name, "Ya tiene jornada activa")
            else:
                raise

    wait(1)

    # ── 3. Enviar ubicación inicial GPS ────────────────────────────────────
    step("Enviando ubicación GPS inicial de los drivers...")

    # Carlos empieza en el almacén central (Pineda de Mar)
    d1_pos = (41.6260, 2.6900)
    send_location(d1_token, d1_user["id"], *d1_pos)
    driver_log("Carlos García", f"GPS: {d1_pos[0]:.4f}, {d1_pos[1]:.4f} (Almacén Pineda)")

    # María empieza en zona Calella
    d2_pos = (41.6140, 2.6580)
    send_location(d2_token, d2_user["id"], *d2_pos)
    driver_log("María López", f"GPS: {d2_pos[0]:.4f}, {d2_pos[1]:.4f} (Zona Calella)")

    wait(1)

    # ── 4. Ver pedidos existentes ──────────────────────────────────────────
    step("Consultando pedidos actuales...")
    orders = api_get("/orders/", central_token)
    info(f"Total pedidos en el sistema: {len(orders)}")

    assigned_orders = [o for o in orders if o.get("status") == "assigned"]
    pending_orders = [o for o in orders if o.get("status") == "pending"]
    info(f"  Asignados: {len(assigned_orders)}, Pendientes: {len(pending_orders)}")

    for o in orders[:6]:
        status_icon = {"assigned": "🟡", "pending": "⚪", "in_progress": "🔵", "completed": "✅"}.get(o["status"], "❓")
        driver_tag = f" → {o['assigned_driver_id']}" if o.get('assigned_driver_id') else ""
        print(f"    {status_icon} [{o['id']}] {o.get('name', 'Sin nombre')} — {o['status']}{driver_tag}")

    wait(1)

    # ── 5. Movimiento en ruta y creación de pedidos en caliente ─────────────
    step("Simulando movimiento de los drivers y creación de pedidos en caliente...")

    # Carlos se mueve hacia zona Pineda Centro
    d1_dest = (41.6245, 2.6890)
    d1_route = interpolate_points(d1_pos, d1_dest, steps=15)

    # María se mueve hacia zona Calella Centro
    d2_dest = (41.6155, 2.6610)
    d2_route = interpolate_points(d2_pos, d2_dest, steps=15)

    new_orders = []
    # Pedidos que se crearán en caliente durante el trayecto
    hot_orders_data = [
        {"step": 2, "data": {"type": "delivery", "name": "Panadería Artesana", "address": "Carrer del Mar 25, Pineda de Mar", "lat": 41.6245, "lng": 2.6890}},
        {"step": 4, "data": {"type": "pickup", "name": "Bodega Can Riera", "address": "Avinguda Maresme 12, Pineda de Mar", "lat": 41.6278, "lng": 2.6855}},
        {"step": 6, "data": {"type": "delivery", "name": "Electro Calella", "address": "Carrer Sant Joan 8, Calella", "lat": 41.6155, "lng": 2.6610}},
    ]

    max_steps = max(len(d1_route), len(d2_route))

    for i in range(max_steps):
        # Mover conductores
        if i < len(d1_route):
            lat, lng = d1_route[i]
            send_location(d1_token, d1_user["id"], lat, lng)
            driver_log("Carlos García", f"📍 GPS {lat:.4f}, {lng:.4f}  (paso {i+1}/{len(d1_route)})")

        if i < len(d2_route):
            lat, lng = d2_route[i]
            send_location(d2_token, d2_user["id"], lat, lng)
            driver_log("María López", f"📍 GPS {lat:.4f}, {lng:.4f}  (paso {i+1}/{len(d2_route)})")

        # Central crea pedidos en caliente en pasos específicos
        for ho in hot_orders_data:
            if ho["step"] == i + 1:
                print(f"\n{C.YELLOW}⚡ [EVENTO CENTRAL] Creando pedido sobre la marcha...{C.RESET}")
                new_order = api_post("/orders/", central_token, ho["data"])
                new_orders.append(new_order)
                driver_id = new_order.get("assigned_driver_id")
                driver_name = "Carlos García" if driver_id == d1_user["id"] else ("María López" if driver_id == d2_user["id"] else None)
                if driver_name:
                    central_log(f"Pedido creado: {new_order['id']} — {ho['data']['name']} (Asignado automáticamente a {driver_name} 🤖)")
                else:
                    central_log(f"Pedido creado: {new_order['id']} — {ho['data']['name']} (Queda PENDIENTE ⚪)")
                print()

        wait(1.2)

    info("Drivers han llegado a sus ubicaciones intermedias")
    wait(1)

    # ── 6. Central asigna pedidos pendientes manualmente ───────────────────
    step("Central asigna pedidos pendientes de forma manual...")

    # Refrescar lista de pedidos
    orders = api_get("/orders/", central_token)
    pending = [o for o in orders if o["status"] == "pending"]

    if not pending:
        info("No hay pedidos pendientes en el sistema que requieran asignación manual.")
    else:
        # Si hay pendientes, los asignamos manualmente para demostrar la funcionalidad de la central
        for i, po in enumerate(pending):
            # Alternamos la asignación entre Carlos (driver1) y María (driver2)
            target_driver = d1_user if i % 2 == 0 else d2_user
            target_name = "Carlos García" if i % 2 == 0 else "María López"
            try:
                api_post(f"/orders/{po['id']}/assign", central_token, {"driver_id": target_driver["id"]})
                central_log(f"Asignación Manual: {po['id']} ({po.get('name', 'N/A')}) → {target_name} 🏢")
            except requests.HTTPError as e:
                warn(f"No se pudo asignar manualmente {po['id']}: {e.response.text}")

    wait(1)

    # ── 7. Drivers aceptan TODOS sus pedidos asignados ─────────────────────
    step("Drivers responden a los pedidos asignados...")

    # Refrescar pedidos para cada driver
    orders = api_get("/orders/", central_token)
    carlos_assigned = [o for o in orders if o.get("assigned_driver_id") == d1_user["id"] and o["status"] == "assigned"]
    maria_assigned = [o for o in orders if o.get("assigned_driver_id") == d2_user["id"] and o["status"] == "assigned"]

    for o in carlos_assigned:
        try:
            result = api_post(f"/orders/{o['id']}/respond", d1_token, {"accepted": True})
            extra = result.get("extra_minutes")
            extra_text = f" (+{extra:.1f} min)" if extra else ""
            driver_log("Carlos García", f"Acepta {o['id']} — {o.get('name', 'N/A')}{extra_text} ✅")
        except requests.HTTPError as e:
            warn(f"Carlos no pudo aceptar {o['id']}: {e.response.text}")
        wait(0.3)

    for o in maria_assigned:
        try:
            result = api_post(f"/orders/{o['id']}/respond", d2_token, {"accepted": True})
            extra = result.get("extra_minutes")
            extra_text = f" (+{extra:.1f} min)" if extra else ""
            driver_log("María López", f"Acepta {o['id']} — {o.get('name', 'N/A')}{extra_text} ✅")
        except requests.HTTPError as e:
            warn(f"María no pudo aceptar {o['id']}: {e.response.text}")
        wait(0.3)

    wait(1)

    # ── 8. Simular movimiento final GPS a destino ───────────────────────────
    step("Drivers continúan su ruta final...")
    # (Ya llegaron a destino intermedio, mandamos confirmación final de GPS)
    if carlos_assigned:
        # Carlos se mueve a la posición de su último pedido asignado
        final_pos = (carlos_assigned[-1]["lat"], carlos_assigned[-1]["lng"])
        send_location(d1_token, d1_user["id"], *final_pos)
        driver_log("Carlos García", f"📍 GPS Final {final_pos[0]:.4f}, {final_pos[1]:.4f} (Destino alcanzado)")
    if maria_assigned:
        final_pos = (maria_assigned[-1]["lat"], maria_assigned[-1]["lng"])
        send_location(d2_token, d2_user["id"], *final_pos)
        driver_log("María López", f"📍 GPS Final {final_pos[0]:.4f}, {final_pos[1]:.4f} (Destino alcanzado)")

    wait(1)

    # ── 9. Completar pedidos de los drivers ──────────────────
    step("Drivers completan entregas...")

    for name, token, assigned in [("Carlos García", d1_token, carlos_assigned), ("María López", d2_token, maria_assigned)]:
        if assigned:
            # Completamos todos los asignados tal como el usuario quiere
            to_complete = assigned[:]
            for order in to_complete:
                api_patch(f"/orders/{order['id']}/status", token, {"status": "completed"})
                driver_log(name, f"Pedido {order['id']} completado — {order.get('name', 'N/A')} 📦✅")
            remaining = len(assigned) - len(to_complete)
            if remaining > 0:
                driver_log(name, f"Quedan {remaining} pedido(s) en ruta 🔵")

    wait(1)

    # ── 10. KPIs de los drivers ────────────────────────────────────────────
    step("Consultando KPIs de eficiencia...")

    for name, token, user_id in [
        ("Carlos García", d1_token, d1_user["id"]),
        ("María López", d2_token, d2_user["id"]),
    ]:
        try:
            kpis = api_get(f"/drivers/{user_id}/kpis", token)
            efficiency = kpis.get("load_efficiency_percent", 0)
            loaded_km = kpis.get("loaded_distance_km", 0)
            total_km = kpis.get("total_distance_km", 0)
            active = kpis.get("active_order_count", 0)
            completed_count = kpis.get("completed_order_count", 0)
            meets_target = kpis.get("meets_load_efficiency_target", False)
            target_icon = "✅" if meets_target else "⚠️"

            driver_log(name, f"Eficiencia de carga: {efficiency:.1f}% {target_icon}")
            print(f"      📊 Cargados: {loaded_km:.2f} km / Total: {total_km:.2f} km")
            print(f"      📦 Activos: {active} | Completados: {completed_count}")
        except Exception as e:
            warn(f"No se pudieron obtener KPIs de {name}: {e}")

    wait(1)

    # ── 11. Estado final ───────────────────────────────────────────────────
    step("Estado final del sistema...")

    orders = api_get("/orders/", central_token)
    completed = [o for o in orders if o["status"] == "completed"]
    in_progress = [o for o in orders if o["status"] == "in_progress"]
    assigned = [o for o in orders if o["status"] == "assigned"]
    pending_final = [o for o in orders if o["status"] == "pending"]

    info(f"Total pedidos: {len(orders)}")
    print(f"    ✅ Completados: {len(completed)}")
    print(f"    🔵 En progreso: {len(in_progress)}")
    print(f"    🟡 Asignados: {len(assigned)}")
    print(f"    ⚪ Pendientes: {len(pending_final)}")

    # Mostrar drivers con KPIs
    try:
        drivers = api_get("/drivers/", central_token)
        print()
        for d in drivers:
            avail = "🟢 Disponible" if d.get("is_available") else "🔴 No disponible"
            loc = f"({d['lat']:.4f}, {d['lng']:.4f})" if d.get("lat") else "(sin GPS)"
            eff = d.get("load_efficiency_percent")
            eff_text = f" | Carga: {eff:.1f}%" if eff is not None else ""
            print(f"    🚚 {d['name']} — {avail} — {loc}{eff_text}")
    except Exception:
        pass

    # ── 12. Terminar jornada de los drivers ────────────────────────────────
    step("Drivers terminan su jornada laboral al final del día...")

    for name, token in [("Carlos García", d1_token), ("María López", d2_token)]:
        try:
            api_post("/drivers/me/jornada/end", token)
            driver_log(name, "¡Jornada finalizada con éxito! Su ruta se ha archivado 🔴")
        except Exception as e:
            warn(f"No se pudo cerrar la jornada para {name}: {e}")

    wait(1)

    print(f"\n{C.BOLD}{'═' * 60}{C.RESET}")
    print(f"{C.BOLD}{C.GREEN}   ✅ SIMULACIÓN COMPLETADA CON ÉXITO{C.RESET}")
    print(f"{C.BOLD}{'═' * 60}{C.RESET}")
    print(f"\n{C.GRAY}Abre la app para ver los cambios reflejados en tiempo real.")
    print(f"Los KPIs aparecen en: Perfil del conductor y Analytics de la central.{C.RESET}\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{C.YELLOW}Simulación cancelada por el usuario.{C.RESET}")
    except requests.HTTPError as e:
        print(f"\n{C.RED}Error HTTP: {e.response.status_code} — {e.response.text}{C.RESET}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{C.RED}Error: {e}{C.RESET}")
        sys.exit(1)

