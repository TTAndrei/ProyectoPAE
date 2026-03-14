"""Route optimisation utilities.

Uses the Haversine formula for straight-line distances and a
best-insertion heuristic to minimise the extra travel time
introduced by adding a new pickup to an existing route.
"""
import math


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Return the great-circle distance (km) between two lat/lng points."""
    R = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lng / 2) ** 2
    )
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def estimate_minutes(km: float, avg_speed_kmh: float = 30.0) -> float:
    """Convert a distance in km to an estimated travel time in minutes."""
    return (km / avg_speed_kmh) * 60.0


def calculate_extra_time(
    current_stops: list[dict],
    driver_pos: dict,
    new_stop: dict,
) -> dict:
    """Calculate the minimum extra time (minutes) of inserting *new_stop*
    into the driver's remaining route at the optimal position.

    Args:
        current_stops: Ordered list of dicts with 'lat' and 'lng' keys.
        driver_pos:    Dict with 'lat' and 'lng' of the driver's current position.
        new_stop:      Dict with 'lat' and 'lng' of the new pickup.

    Returns:
        Dict with 'extra_minutes' (float) and 'insert_index' (int).
    """
    if not current_stops:
        km = haversine_km(driver_pos["lat"], driver_pos["lng"], new_stop["lat"], new_stop["lng"])
        return {"extra_minutes": round(estimate_minutes(km), 1), "insert_index": 0}

    # Full waypoint list: driver position followed by all remaining stops
    waypoints = [driver_pos] + list(current_stops)

    best_extra = math.inf
    best_index = 0

    # Try inserting between every consecutive pair of waypoints
    for i in range(len(waypoints) - 1):
        detour = (
            haversine_km(waypoints[i]["lat"], waypoints[i]["lng"], new_stop["lat"], new_stop["lng"])
            + haversine_km(new_stop["lat"], new_stop["lng"], waypoints[i + 1]["lat"], waypoints[i + 1]["lng"])
            - haversine_km(waypoints[i]["lat"], waypoints[i]["lng"], waypoints[i + 1]["lat"], waypoints[i + 1]["lng"])
        )
        if detour < best_extra:
            best_extra = detour
            best_index = i

    # Also consider appending at the very end
    last = waypoints[-1]
    append_dist = haversine_km(last["lat"], last["lng"], new_stop["lat"], new_stop["lng"])
    if append_dist < best_extra:
        best_extra = append_dist
        best_index = len(waypoints) - 1

    return {
        "extra_minutes": round(estimate_minutes(best_extra), 1),
        "insert_index": best_index,
    }
