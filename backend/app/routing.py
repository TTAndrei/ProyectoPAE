"""Utilidades de optimización de rutas para la aplicación PAE.

Implementa dos algoritmos principales:

1. **Fórmula Haversine**: calcula la distancia en km entre dos puntos geográficos
   (latitud/longitud) teniendo en cuenta la curvatura de la Tierra.

2. **Heurística de inserción óptima** (best-insertion): dado un repartidor con
   una ruta de paradas ya definida, encuentra la posición en la ruta donde
   insertar una nueva parada (recogida) que minimice el desvío extra.

Ambos algoritmos trabajan en tiempo real, por lo que priorizan la velocidad
de cómputo sobre la precisión absoluta.
"""
import math


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


def calcular_tiempo_extra(
    paradas_actuales: list[dict],
    posicion_repartidor: dict,
    nueva_parada: dict,
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
    # Caso especial: ruta vacía → tiempo directo desde el repartidor a la nueva parada
    if not paradas_actuales:
        km = distancia_haversine_km(
            posicion_repartidor["lat"], posicion_repartidor["lng"],
            nueva_parada["lat"], nueva_parada["lng"],
        )
        return {"extra_minutos": round(estimar_minutos(km), 1), "indice_insercion": 0}

    # Lista completa de puntos: posición actual + todas las paradas pendientes
    puntos_ruta = [posicion_repartidor] + list(paradas_actuales)

    mejor_desvio = math.inf   # Desvío mínimo encontrado (inicialmente infinito)
    mejor_indice = 0          # Índice de inserción óptimo

    # Probar inserción entre cada par consecutivo de puntos
    for i in range(len(puntos_ruta) - 1):
        desvio = (
            distancia_haversine_km(
                puntos_ruta[i]["lat"], puntos_ruta[i]["lng"],
                nueva_parada["lat"], nueva_parada["lng"],
            )
            + distancia_haversine_km(
                nueva_parada["lat"], nueva_parada["lng"],
                puntos_ruta[i + 1]["lat"], puntos_ruta[i + 1]["lng"],
            )
            - distancia_haversine_km(
                puntos_ruta[i]["lat"], puntos_ruta[i]["lng"],
                puntos_ruta[i + 1]["lat"], puntos_ruta[i + 1]["lng"],
            )
        )
        if desvio < mejor_desvio:
            mejor_desvio = desvio
            mejor_indice = i

    # Considerar también añadir la parada al final de la ruta
    ultimo_punto = puntos_ruta[-1]
    distancia_al_final = distancia_haversine_km(
        ultimo_punto["lat"], ultimo_punto["lng"],
        nueva_parada["lat"], nueva_parada["lng"],
    )
    if distancia_al_final < mejor_desvio:
        mejor_desvio = distancia_al_final
        mejor_indice = len(puntos_ruta) - 1

    return {
        "extra_minutos": round(estimar_minutos(mejor_desvio), 1),
        "indice_insercion": mejor_indice,
    }
