import math

import httpx


def distancia_haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    RADIO_TIERRA_KM = 6371.0
    delta_lat = math.radians(lat2 - lat1)
    delta_lng = math.radians(lng2 - lng1)
    termino_central = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(delta_lng / 2) ** 2
    )
    return RADIO_TIERRA_KM * 2 * math.atan2(math.sqrt(termino_central), math.sqrt(1 - termino_central))


def estimar_minutos(km: float, velocidad_media_kmh: float = 30.0) -> float:
    return (km / velocidad_media_kmh) * 60.0



def _optimizar_indices_por_matriz(matriz_duraciones: list[list[float | None]]) -> list[int]:
    """Optimiza orden de visitas usando matriz de tiempos (NN + 2-opt)."""
    if not matriz_duraciones or len(matriz_duraciones) <= 1:
        return []

    ultimo_indice = len(matriz_duraciones) - 1
    pendientes = set(range(1, ultimo_indice + 1))
    actual = 0
    orden = []

    while pendientes:
        siguiente = min(
            pendientes,
            key=lambda indice: _dur_mat(matriz_duraciones, actual, indice),
        )
        orden.append(siguiente)
        pendientes.remove(siguiente)
        actual = siguiente

    def duracion_total(indices: list[int]) -> float:
        if not indices:
            return 0.0
        acumulado = _dur_mat(matriz_duraciones, 0, indices[0])
        for idx in range(len(indices) - 1):
            acumulado += _dur_mat(matriz_duraciones, indices[idx], indices[idx + 1])
        return acumulado

    mejor = list(orden)
    mejor_duracion = duracion_total(mejor)
    mejoro = True

    while mejoro:
        mejoro = False
        for i in range(len(mejor) - 1):
            for j in range(i + 1, len(mejor)):
                candidata = mejor[:i] + list(reversed(mejor[i : j + 1])) + mejor[j + 1 :]
                duracion_candidata = duracion_total(candidata)
                if duracion_candidata + 1e-9 < mejor_duracion:
                    mejor = candidata
                    mejor_duracion = duracion_candidata
                    mejoro = True

    return mejor


def _dur_mat(matriz: list[list[float | None]], i: int, j: int) -> float:
    """Duración i→j de una matriz o infinito si no existe."""
    try:
        v = matriz[i][j]
        return float(v) if v is not None else math.inf
    except (IndexError, TypeError):
        return math.inf


def _coords_osrm(puntos: list[dict]) -> str:
    """Convierte [{'lat','lng'}] a cadena lon,lat;lon,lat para OSRM."""
    return ";".join(f"{punto['lng']:.8f},{punto['lat']:.8f}" for punto in puntos)


def _consultar_ruta_osrm(
    base_url: str,
    puntos_ordenados: list[dict],
    timeout_seconds: float,
) -> dict | None:
    """Obtiene geometria y tiempos de ruta para un orden de puntos dado."""
    if len(puntos_ordenados) < 2:
        return None

    route_coords = _coords_osrm(puntos_ordenados)
    route_url = f"{base_url}/route/v1/driving/{route_coords}"

    try:
        route_response = httpx.get(
            route_url,
            params={
                "overview": "full",
                "geometries": "geojson",
                "steps": "false",
            },
            timeout=timeout_seconds,
        )
        route_response.raise_for_status()
        route_data = route_response.json()
    except Exception:
        return None

    if route_data.get("code") != "Ok" or not route_data.get("routes"):
        return None

    mejor_ruta = route_data["routes"][0]
    route_geometry = [
        {"lat": float(coord[1]), "lng": float(coord[0])}
        for coord in (mejor_ruta.get("geometry", {}).get("coordinates") or [])
        if isinstance(coord, list) and len(coord) >= 2
    ]
    if not route_geometry:
        return None

    leg_minutes = [
        round(float(leg.get("duration", 0.0)) / 60.0, 1)
        for leg in (mejor_ruta.get("legs") or [])
    ]
    if not leg_minutes:
        leg_minutes = _legs_haversine_minutos(
            puntos_ordenados[0],
            puntos_ordenados[1:],
        )

    distancia_km = float(mejor_ruta.get("distance", 0.0)) / 1000.0
    minutos_totales = float(mejor_ruta.get("duration", 0.0)) / 60.0
    return {
        "route_geometry": route_geometry,
        "leg_minutes": leg_minutes,
        "distancia_km": distancia_km,
        "minutos_totales": minutos_totales,
    }


def _consultar_ruta_osrm_por_tramos(
    base_url: str,
    puntos_ordenados: list[dict],
    timeout_seconds: float,
) -> dict | None:
    """Obtiene geometria vial encadenando rutas OSRM de cada tramo."""
    if len(puntos_ordenados) < 2:
        return None

    route_geometry: list[dict[str, float]] = []
    leg_minutes: list[float] = []
    distancia_km = 0.0
    minutos_totales = 0.0

    for indice in range(len(puntos_ordenados) - 1):
        origen = puntos_ordenados[indice]
        destino = puntos_ordenados[indice + 1]
        route_coords = _coords_osrm([origen, destino])
        route_url = f"{base_url}/route/v1/driving/{route_coords}"

        try:
            route_response = httpx.get(
                route_url,
                params={
                    "overview": "full",
                    "geometries": "geojson",
                    "steps": "false",
                },
                timeout=timeout_seconds,
            )
            route_response.raise_for_status()
            route_data = route_response.json()
        except Exception:
            return None

        if route_data.get("code") != "Ok" or not route_data.get("routes"):
            return None

        mejor_ruta = route_data["routes"][0]
        segmento_geometry = [
            {"lat": float(coord[1]), "lng": float(coord[0])}
            for coord in (mejor_ruta.get("geometry", {}).get("coordinates") or [])
            if isinstance(coord, list) and len(coord) >= 2
        ]
        if len(segmento_geometry) < 2:
            return None

        if not route_geometry:
            route_geometry.extend(segmento_geometry)
        else:
            route_geometry.extend(segmento_geometry[1:])

        distancia_km += float(mejor_ruta.get("distance", 0.0)) / 1000.0
        tramo_minutos = float(mejor_ruta.get("duration", 0.0)) / 60.0
        minutos_totales += tramo_minutos
        leg_minutes.append(round(tramo_minutos, 1))

    return {
        "route_geometry": route_geometry,
        "leg_minutes": leg_minutes,
        "distancia_km": distancia_km,
        "minutos_totales": minutos_totales,
    }


def _legs_haversine_minutos(origen: dict, paradas_ordenadas: list[dict]) -> list[float]:
    """Calcula duración estimada de cada tramo de forma local (fallback)."""
    if not paradas_ordenadas:
        return []

    legs = []
    actual = origen
    for parada in paradas_ordenadas:
        km = _distancia_entre_puntos_km(actual, parada)
        legs.append(round(estimar_minutos(km), 1))
        actual = parada
    return legs


def _resultado_fallback_haversine(paradas: list[dict], posicion_repartidor: dict) -> dict:
    """Resultado de respaldo sin red vial real."""
    base = optimizar_ruta(paradas, posicion_repartidor)
    paradas_ordenadas = base["paradas_ordenadas"]
    route_geometry = [
        {"lat": posicion_repartidor["lat"], "lng": posicion_repartidor["lng"]},
        *[{"lat": parada["lat"], "lng": parada["lng"]} for parada in paradas_ordenadas],
    ]
    legs = _legs_haversine_minutos(posicion_repartidor, paradas_ordenadas)

    return {
        "paradas_ordenadas": paradas_ordenadas,
        "distancia_km": base["distancia_km"],
        "minutos_totales": base["minutos_totales"],
        "route_geometry": route_geometry,
        "leg_minutes": legs,
    }


def _distancia_entre_puntos_km(origen: dict, destino: dict) -> float:
    """Calcula la distancia entre dos puntos {'lat','lng'} en km."""
    return distancia_haversine_km(
        origen["lat"], origen["lng"], destino["lat"], destino["lng"]
    )


def _distancia_ruta_km(origen: dict, paradas_ordenadas: list[dict]) -> float:
    """Distancia acumulada desde origen recorriendo paradas en el orden dado."""
    if not paradas_ordenadas:
        return 0.0

    total_km = 0.0
    actual = origen
    for parada in paradas_ordenadas:
        total_km += _distancia_entre_puntos_km(actual, parada)
        actual = parada
    return total_km


def _ruta_vecino_mas_cercano(origen: dict, paradas: list[dict]) -> list[dict]:
    """Construye una ruta inicial rápida usando nearest-neighbor."""
    pendientes = list(paradas)
    actual = origen
    ruta = []

    while pendientes:
        indice_minimo = min(
            range(len(pendientes)),
            key=lambda idx: _distancia_entre_puntos_km(actual, pendientes[idx]),
        )
        siguiente = pendientes.pop(indice_minimo)
        ruta.append(siguiente)
        actual = siguiente

    return ruta


def _mejorar_ruta_2opt(origen: dict, ruta_inicial: list[dict]) -> list[dict]:
    """Mejora la ruta aplicando intercambios 2-opt hasta converger."""
    if len(ruta_inicial) < 4:
        return list(ruta_inicial)

    mejor = list(ruta_inicial)
    mejor_distancia = _distancia_ruta_km(origen, mejor)
    mejoro = True

    while mejoro:
        mejoro = False
        for i in range(len(mejor) - 1):
            for j in range(i + 1, len(mejor)):
                if j - i < 2:
                    continue

                candidata = (
                    mejor[:i]
                    + list(reversed(mejor[i: j + 1]))
                    + mejor[j + 1:]
                )
                distancia_candidata = _distancia_ruta_km(origen, candidata)
                if distancia_candidata + 1e-9 < mejor_distancia:
                    mejor = candidata
                    mejor_distancia = distancia_candidata
                    mejoro = True

    return mejor


def _clarke_wright_orden(origen: dict, paradas: list[dict]) -> list[dict]:
    """Ordena paradas usando Clarke-Wright savings. Mejor que NN para 5+ paradas."""
    n = len(paradas)
    if n <= 1:
        return list(paradas)

    ahorros = []
    for i in range(n):
        for j in range(i + 1, n):
            s = (
                _distancia_entre_puntos_km(origen, paradas[i])
                + _distancia_entre_puntos_km(origen, paradas[j])
                - _distancia_entre_puntos_km(paradas[i], paradas[j])
            )
            ahorros.append((s, i, j))
    ahorros.sort(reverse=True)

    rutas: list[list[int]] = [[i] for i in range(n)]
    pertenece: dict[int, int] = {i: i for i in range(n)}

    for _, i, j in ahorros:
        ri, rj = pertenece[i], pertenece[j]
        if ri == rj:
            continue
        ruta_i, ruta_j = rutas[ri], rutas[rj]
        i_at_end = ruta_i[-1] == i or ruta_i[0] == i
        j_at_end = ruta_j[-1] == j or ruta_j[0] == j
        if not (i_at_end and j_at_end):
            continue
        if ruta_i[0] == i:
            ruta_i.reverse()
        if ruta_j[-1] == j:
            ruta_j.reverse()
        rutas[ri] = ruta_i + ruta_j
        rutas[rj] = []
        for stop in ruta_j:
            pertenece[stop] = ri

    merged = next((r for r in rutas if r), list(range(n)))
    return [paradas[idx] for idx in merged]


def optimizar_ruta(paradas: list[dict], posicion_repartidor: dict) -> dict:
    """Ordena paradas para minimizar tiempo total. Clarke-Wright para 5+, NN para menos."""
    if not paradas:
        return {
            "paradas_ordenadas": [],
            "distancia_km": 0.0,
            "minutos_totales": 0.0,
        }

    if len(paradas) >= 5:
        ruta_inicial = _clarke_wright_orden(posicion_repartidor, paradas)
    else:
        ruta_inicial = _ruta_vecino_mas_cercano(posicion_repartidor, paradas)

    ruta_optimizada = _mejorar_ruta_2opt(posicion_repartidor, ruta_inicial)
    distancia_km = _distancia_ruta_km(posicion_repartidor, ruta_optimizada)

    return {
        "paradas_ordenadas": ruta_optimizada,
        "distancia_km": round(distancia_km, 2),
        "minutos_totales": round(estimar_minutos(distancia_km), 1),
    }


def optimizar_ruta_vial(
    paradas: list[dict],
    posicion_repartidor: dict,
    osrm_base_url: str | None = None,
    timeout_seconds: float = 2.0,
) -> dict:
    """Optimiza ruta por calles con OSRM (y fallback local si falla)."""
    if not paradas:
        return {
            "paradas_ordenadas": [],
            "distancia_km": 0.0,
            "minutos_totales": 0.0,
            "route_geometry": [],
            "leg_minutes": [],
        }

    if not osrm_base_url:
        return _resultado_fallback_haversine(paradas, posicion_repartidor)

    puntos = [
        {"lat": posicion_repartidor["lat"], "lng": posicion_repartidor["lng"]},
        *paradas,
    ]
    coords = _coords_osrm(puntos)
    base = osrm_base_url.rstrip("/")
    paradas_ordenadas: list[dict] | None = None

    try:
        tabla_url = f"{base}/table/v1/driving/{coords}"
        tabla_response = httpx.get(
            tabla_url,
            params={"annotations": "duration"},
            timeout=timeout_seconds,
        )
        tabla_response.raise_for_status()
        tabla_data = tabla_response.json()

        if tabla_data.get("code") == "Ok":
            matriz_duraciones = tabla_data.get("durations")
            if isinstance(matriz_duraciones, list) and len(matriz_duraciones) >= 2:
                orden_indices = _optimizar_indices_por_matriz(matriz_duraciones)
                if orden_indices:
                    paradas_ordenadas = [puntos[indice] for indice in orden_indices]
    except Exception:
        paradas_ordenadas = None

    if paradas_ordenadas is None:
        base_local = optimizar_ruta(paradas, posicion_repartidor)
        paradas_ordenadas = base_local["paradas_ordenadas"]

    puntos_ordenados = [puntos[0], *paradas_ordenadas]
    ruta_osrm = _consultar_ruta_osrm(base, puntos_ordenados, timeout_seconds)
    if ruta_osrm is None:
        ruta_osrm = _consultar_ruta_osrm_por_tramos(
            base,
            puntos_ordenados,
            timeout_seconds,
        )
    if ruta_osrm is not None:
        return {
            "paradas_ordenadas": paradas_ordenadas,
            "distancia_km": round(ruta_osrm["distancia_km"], 2),
            "minutos_totales": round(ruta_osrm["minutos_totales"], 1),
            "route_geometry": ruta_osrm["route_geometry"],
            "leg_minutes": ruta_osrm["leg_minutes"],
        }

    distancia_km = _distancia_ruta_km(posicion_repartidor, paradas_ordenadas)
    return {
        "paradas_ordenadas": paradas_ordenadas,
        "distancia_km": round(distancia_km, 2),
        "minutos_totales": round(estimar_minutos(distancia_km), 1),
        "route_geometry": [
            {"lat": posicion_repartidor["lat"], "lng": posicion_repartidor["lng"]},
            *[
                {"lat": parada["lat"], "lng": parada["lng"]}
                for parada in paradas_ordenadas
            ],
        ],
        "leg_minutes": _legs_haversine_minutos(posicion_repartidor, paradas_ordenadas),
    }


def _obtener_matriz_duraciones(
    puntos: list[dict],
    osrm_base_url: str | None,
    timeout_seconds: float,
) -> list[list[float]]:
    """Matriz de duraciones (segundos) entre todos los puntos. Una sola llamada OSRM o fallback haversine."""
    n = len(puntos)
    if osrm_base_url and n >= 2:
        coords = _coords_osrm(puntos)
        url = f"{osrm_base_url.rstrip('/')}/table/v1/driving/{coords}"
        try:
            resp = httpx.get(url, params={"annotations": "duration"}, timeout=timeout_seconds)
            resp.raise_for_status()
            data = resp.json()
            if data.get("code") == "Ok" and data.get("durations"):
                return data["durations"]
        except Exception:
            pass
    # Fallback: haversine convertido a segundos (30 km/h)
    return [
        [
            estimar_minutos(_distancia_entre_puntos_km(puntos[i], puntos[j])) * 60.0
            if i != j else 0.0
            for j in range(n)
        ]
        for i in range(n)
    ]


def calcular_tiempo_extra(
    paradas_actuales: list[dict],
    posicion_repartidor: dict,
    nueva_parada: dict,
    osrm_base_url: str | None = None,
    timeout_seconds: float = 2.0,
) -> dict:
    """Tiempo mínimo extra (minutos) de insertar nueva_parada en la ruta actual. Una sola llamada OSRM /table."""
    puntos = [posicion_repartidor] + list(paradas_actuales)
    n = len(puntos)
    nueva_idx = n
    todos = puntos + [nueva_parada]

    matriz = _obtener_matriz_duraciones(todos, osrm_base_url, timeout_seconds)

    mejor_extra = math.inf
    mejor_indice = 0
    for i in range(n):
        after = i + 1
        a_new = _dur_mat(matriz, i, nueva_idx)
        new_b = _dur_mat(matriz, nueva_idx, after) if after < n else 0.0
        a_b   = _dur_mat(matriz, i, after)         if after < n else 0.0
        delta = a_new + new_b - a_b
        if delta < mejor_extra:
            mejor_extra = delta
            mejor_indice = i

    return {
        "extra_minutos": round(max(0.0, mejor_extra / 60.0), 1),
        "indice_insercion": mejor_indice,
    }


UMBRAL_BACKHAULING_MINUTOS: float = 2.0


def detectar_candidatos_backhauling(
    nueva_parada: dict,
    repartidores: list[dict],
    osrm_base_url: str | None = None,
    timeout_seconds: float = 2.0,
    umbral_minutos: float = UMBRAL_BACKHAULING_MINUTOS,
) -> list[dict]:
    """Drivers para quienes añadir nueva_parada cuesta <= umbral_minutos de desvío."""
    candidatos = []
    for rep in repartidores:
        if not rep.get("lat") or not rep.get("paradas_activas"):
            continue
        resultado = calcular_tiempo_extra(
            rep["paradas_activas"],
            {"lat": rep["lat"], "lng": rep["lng"]},
            nueva_parada,
            osrm_base_url=osrm_base_url,
            timeout_seconds=timeout_seconds,
        )
        if resultado["extra_minutos"] <= umbral_minutos:
            candidatos.append({
                "driver_id": rep["id"],
                "extra_minutos": resultado["extra_minutos"],
                "indice_insercion": resultado["indice_insercion"],
            })
    candidatos.sort(key=lambda x: x["extra_minutos"])
    return candidatos
