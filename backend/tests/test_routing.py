"""Pruebas unitarias del módulo de optimización de rutas (routing.py).

Cubre los tres componentes principales:
- distancia_haversine_km: cálculo de distancias geográficas
- estimar_minutos: conversión de distancia a tiempo
- calcular_tiempo_extra: algoritmo de inserción óptima
"""
import math
import pytest
from app.routing import (
    distancia_haversine_km,
    estimar_minutos,
    calcular_tiempo_extra,
    optimizar_ruta,
)


def test_haversine_mismo_punto():
    """La distancia de un punto a sí mismo debe ser 0."""
    assert distancia_haversine_km(40.4, -3.7, 40.4, -3.7) == 0.0


def test_haversine_un_grado_latitud():
    """Un grado de latitud equivale aproximadamente a 111 km."""
    distancia = distancia_haversine_km(0, 0, 1, 0)
    assert abs(distancia - 111.19) < 1.0


def test_haversine_madrid_barcelona():
    """La distancia Madrid–Barcelona debe estar entre 490 y 520 km."""
    # Coordenadas: Madrid (40.4168, -3.7038), Barcelona (41.3851, 2.1734)
    distancia = distancia_haversine_km(40.4168, -3.7038, 41.3851, 2.1734)
    assert 490 < distancia < 520


def test_estimar_minutos_30km():
    """30 km a 30 km/h deben corresponder exactamente a 60 minutos."""
    assert estimar_minutos(30) == 60.0


def test_estimar_minutos_cero():
    """Una distancia de 0 km debe dar 0 minutos de tiempo estimado."""
    assert estimar_minutos(0) == 0.0


def test_calcular_tiempo_extra_ruta_vacia():
    """Con ruta vacía, el tiempo extra es el trayecto directo al nuevo punto."""
    posicion_repartidor = {"lat": 40.4168, "lng": -3.7038}
    nueva_parada = {"lat": 40.43, "lng": -3.69}
    resultado = calcular_tiempo_extra([], posicion_repartidor, nueva_parada)
    assert resultado["extra_minutos"] > 0
    assert resultado["indice_insercion"] == 0


def test_calcular_tiempo_extra_devuelve_numero():
    """El tiempo extra debe ser un número flotante no negativo."""
    posicion_repartidor = {"lat": 40.4168, "lng": -3.7038}
    paradas = [
        {"lat": 40.4189, "lng": -3.6929},
        {"lat": 40.4356, "lng": -3.6882},
    ]
    nueva_parada = {"lat": 40.4277, "lng": -3.7025}
    resultado = calcular_tiempo_extra(paradas, posicion_repartidor, nueva_parada)
    assert isinstance(resultado["extra_minutos"], float)
    assert resultado["extra_minutos"] >= 0


def test_calcular_tiempo_extra_cercano_menos_que_lejano():
    """Una parada más cercana debe generar menos tiempo extra que una lejana."""
    posicion_repartidor = {"lat": 40.4168, "lng": -3.7038}
    paradas = [{"lat": 40.4189, "lng": -3.6929}]

    resultado_cercano = calcular_tiempo_extra(
        paradas, posicion_repartidor, {"lat": 40.417, "lng": -3.704}
    )
    resultado_lejano = calcular_tiempo_extra(
        paradas, posicion_repartidor, {"lat": 40.50, "lng": -3.80}
    )
    assert resultado_cercano["extra_minutos"] < resultado_lejano["extra_minutos"]


def test_calcular_tiempo_extra_indice_insercion_valido():
    """El índice de inserción devuelto debe ser un entero no negativo."""
    posicion_repartidor = {"lat": 40.4168, "lng": -3.7038}
    paradas = [
        {"lat": 40.42, "lng": -3.70},
        {"lat": 40.43, "lng": -3.69},
    ]
    nueva_parada = {"lat": 40.415, "lng": -3.705}
    resultado = calcular_tiempo_extra(paradas, posicion_repartidor, nueva_parada)
    assert resultado["indice_insercion"] >= 0


def test_optimizar_ruta_devuelve_orden_y_metricas_validas():
    """El optimizador debe devolver todas las paradas con tiempo/distancia válidos."""
    posicion_repartidor = {"lat": 40.4168, "lng": -3.7038}
    paradas = [
        {"id": "a", "lat": 40.4356, "lng": -3.6882},
        {"id": "b", "lat": 40.4238, "lng": -3.6797},
        {"id": "c", "lat": 40.4277, "lng": -3.7025},
    ]

    resultado = optimizar_ruta(paradas, posicion_repartidor)
    ids_resultado = [parada["id"] for parada in resultado["paradas_ordenadas"]]

    assert sorted(ids_resultado) == ["a", "b", "c"]
    assert resultado["distancia_km"] >= 0
    assert resultado["minutos_totales"] >= 0
