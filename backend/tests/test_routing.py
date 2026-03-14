"""Tests for the routing utility."""
import math
import pytest
from app.routing import haversine_km, estimate_minutes, calculate_extra_time


def test_haversine_same_point():
    assert haversine_km(40.4, -3.7, 40.4, -3.7) == 0.0


def test_haversine_one_degree_latitude():
    dist = haversine_km(0, 0, 1, 0)
    assert abs(dist - 111.19) < 1.0


def test_haversine_madrid_barcelona():
    # ~505 km
    dist = haversine_km(40.4168, -3.7038, 41.3851, 2.1734)
    assert 490 < dist < 520


def test_estimate_minutes_30km():
    # 30 km at 30 km/h = 60 minutes
    assert estimate_minutes(30) == 60.0


def test_estimate_minutes_zero():
    assert estimate_minutes(0) == 0.0


def test_calculate_extra_time_empty_stops():
    driver = {"lat": 40.4168, "lng": -3.7038}
    new_stop = {"lat": 40.43, "lng": -3.69}
    result = calculate_extra_time([], driver, new_stop)
    assert result["extra_minutes"] > 0
    assert result["insert_index"] == 0


def test_calculate_extra_time_returns_number():
    driver = {"lat": 40.4168, "lng": -3.7038}
    stops = [
        {"lat": 40.4189, "lng": -3.6929},
        {"lat": 40.4356, "lng": -3.6882},
    ]
    new_stop = {"lat": 40.4277, "lng": -3.7025}
    result = calculate_extra_time(stops, driver, new_stop)
    assert isinstance(result["extra_minutes"], float)
    assert result["extra_minutes"] >= 0


def test_calculate_extra_time_nearby_less_than_far():
    driver = {"lat": 40.4168, "lng": -3.7038}
    stops = [{"lat": 40.4189, "lng": -3.6929}]

    near = calculate_extra_time(stops, driver, {"lat": 40.417, "lng": -3.704})
    far  = calculate_extra_time(stops, driver, {"lat": 40.50,  "lng": -3.80})
    assert near["extra_minutes"] < far["extra_minutes"]


def test_calculate_extra_time_insert_index_valid():
    driver = {"lat": 40.4168, "lng": -3.7038}
    stops = [{"lat": 40.42, "lng": -3.70}, {"lat": 40.43, "lng": -3.69}]
    new_stop = {"lat": 40.415, "lng": -3.705}
    result = calculate_extra_time(stops, driver, new_stop)
    assert result["insert_index"] >= 0
