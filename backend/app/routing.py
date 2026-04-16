"""Utilidades de optimización de rutas para la aplicación PAE.

Incluye:
1. Distancia Haversine y estimación de minutos.
2. Pathfinding heurístico para ordenar paradas y minimizar tiempo total
    (vecino más cercano + mejora 2-opt).
3. Cálculo de tiempo extra al insertar/aceptar una nueva parada.
"""
import math

import httpx


def distancia_haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calcula la distancia en línea recta (km) entre dos puntos geográficos.

    Usa la fórmula Haversine, que tiene en cuenta la esfericidad de la Tierra.
    Es una aproximación precisa para distancias menores a ~2000 km.

    Args:
        lat1: Latitud del punto de origen (grados decimales).
        lng1: Longitud del punto de origen (grados decimales).
        lat2: Latitud del punto de destino (grados decimales).
        lng2: Longitud del punto de destino (grados decimales).

    Returns:
        Distancia en kilómetros (float).

    Ejemplo:
        >>> distancia_haversine_km(40.4168, -3.7038, 41.3851, 2.1734)
        # ~505 km (Madrid → Barcelona)
    """
    # Radio medio de la Tierra en kilómetros
    RADIO_TIERRA_KM = 6371.0

    # Convertir diferencias de coordenadas a radianes
    delta_lat = math.radians(lat2 - lat1)
    delta_lng = math.radians(lng2 - lng1)

    # Término central de la fórmula Haversine
    termino_central = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(delta_lng / 2) ** 2
    )

    # Distancia angular y distancia final en km
    return RADIO_TIERRA_KM * 2 * math.atan2(math.sqrt(termino_central), math.sqrt(1 - termino_central))


def estimar_minutos(km: float, velocidad_media_kmh: float = 30.0) -> float:
    """Convierte una distancia en km a tiempo estimado de viaje en minutos.

    Se asume una velocidad media urbana de 30 km/h por defecto,
    que es representativa para repartos en ciudad con tráfico.

    Args:
        km: Distancia en kilómetros.
        velocidad_media_kmh: Velocidad media asumida (km/h). Por defecto 30.

    Returns:
        Tiempo estimado en minutos (float).
    """
    return (km / velocidad_media_kmh) * 60.0


def _duracion_segundos_en_matriz(matriz: list[list[float | None]], i: int, j: int) -> float:
    """Obtiene duración i->j de la matriz o infinito si no existe."""
    try:
        valor = matriz[i][j]
    except (IndexError, TypeError):
        return math.inf
    if valor is None:
        return math.inf
    return float(valor)


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
            key=lambda indice: _duracion_segundos_en_matriz(
                matriz_duraciones,
                actual,
                indice,
            ),
        )
        orden.append(siguiente)
        pendientes.remove(siguiente)
        actual = siguiente

    def duracion_total(indices: list[int]) -> float:
        if not indices:
            return 0.0
        acumulado = _duracion_segundos_en_matriz(matriz_duraciones, 0, indices[0])
        for idx in range(len(indices) - 1):
            acumulado += _duracion_segundos_en_matriz(
                matriz_duraciones,
                indices[idx],
                indices[idx + 1],
            )
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


def optimizar_ruta(paradas: list[dict], posicion_repartidor: dict) -> dict:
    """Ordena paradas para minimizar tiempo estimado total de recorrido.

    Devuelve:
      - paradas_ordenadas: lista en el orden recomendado
      - distancia_km: distancia total estimada
      - minutos_totales: tiempo total estimado
    """
    if not paradas:
        return {
            "paradas_ordenadas": [],
            "distancia_km": 0.0,
            "minutos_totales": 0.0,
        }

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


def calcular_tiempo_extra(
    paradas_actuales: list[dict],
    posicion_repartidor: dict,
    nueva_parada: dict,
    osrm_base_url: str | None = None,
    timeout_seconds: float = 2.0,
) -> dict:
    """Calcula el tiempo mínimo extra (en minutos) de añadir una nueva parada a la ruta.

    Usa la heurística de inserción óptima: prueba insertar la nueva parada
    entre cada par consecutivo de puntos de la ruta y elige la posición
    que minimiza el desvío total.

    El desvío de insertar entre el punto A y el punto B es:
        dist(A → nueva) + dist(nueva → B) − dist(A → B)

    Args:
        paradas_actuales: Lista ordenada de diccionarios con claves 'lat' y 'lng'.
                          Representa las paradas pendientes del repartidor.
        posicion_repartidor: Diccionario {'lat': ..., 'lng': ...} con la
                             posición actual del repartidor.
        nueva_parada: Diccionario {'lat': ..., 'lng': ...} con la ubicación
                      de la recogida que se quiere añadir.

    Returns:
        Diccionario con:
          - 'extra_minutos': float — tiempo extra estimado en minutos.
          - 'indice_insercion': int — posición óptima en la lista de paradas.

    Ejemplo:
        >>> calcular_tiempo_extra(
        ...     [{"lat": 40.42, "lng": -3.70}],
        ...     {"lat": 40.41, "lng": -3.71},
        ...     {"lat": 40.425, "lng": -3.705},
        ... )
        {'extra_minutos': 1.2, 'indice_insercion': 0}
    """
    base = optimizar_ruta_vial(
        paradas_actuales,
        posicion_repartidor,
        osrm_base_url=osrm_base_url,
        timeout_seconds=timeout_seconds,
    )

    nueva_marcada = dict(nueva_parada)
    nueva_marcada["_tmp_id"] = "__new_stop__"
    con_nueva = list(paradas_actuales) + [nueva_marcada]

    optimizada = optimizar_ruta_vial(
        con_nueva,
        posicion_repartidor,
        osrm_base_url=osrm_base_url,
        timeout_seconds=timeout_seconds,
    )
    extra_minutos = max(0.0, optimizada["minutos_totales"] - base["minutos_totales"])

    indice_insercion = 0
    for indice, parada in enumerate(optimizada["paradas_ordenadas"]):
        if parada.get("_tmp_id") == "__new_stop__":
            indice_insercion = indice
            break

    return {
        "extra_minutos": round(extra_minutos, 1),
        "indice_insercion": indice_insercion,
    }
