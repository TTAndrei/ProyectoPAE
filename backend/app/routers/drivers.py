"""Drivers router."""
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import get_connection
from app.schemas import DriverOut, LocationUpdate
from app.auth import get_current_user, require_central

router = APIRouter(prefix="/drivers", tags=["drivers"])


@router.get("/", response_model=list[DriverOut])
def list_drivers(_: dict = Depends(require_central)):
    """List all drivers with their current location. Central only."""
    conn = get_connection()
    rows = conn.execute(
        """
        SELECT u.id, u.username, u.name,
               dl.lat, dl.lng, dl.heading,
               dl.updated_at AS location_updated_at
        FROM users u
        LEFT JOIN driver_locations dl ON dl.driver_id = u.id
        WHERE u.role = 'repartidor'
        """
    ).fetchall()
    return [dict(r) for r in rows]


@router.get("/{driver_id}/location")
def get_driver_location(driver_id: str, _: dict = Depends(get_current_user)):
    conn = get_connection()
    row = conn.execute(
        "SELECT * FROM driver_locations WHERE driver_id = ?", (driver_id,)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Location not found")
    return dict(row)


@router.put("/{driver_id}/location")
def update_driver_location(
    driver_id: str,
    body: LocationUpdate,
    current_user: dict = Depends(get_current_user),
):
    """Update a driver's location. Only the driver themselves can do this."""
    if current_user.get("role") != "repartidor" or current_user.get("id") != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")

    conn = get_connection()
    conn.execute(
        """
        INSERT INTO driver_locations (driver_id, lat, lng, heading, updated_at)
        VALUES (?, ?, ?, ?, datetime('now'))
        ON CONFLICT(driver_id) DO UPDATE SET
            lat = excluded.lat,
            lng = excluded.lng,
            heading = excluded.heading,
            updated_at = excluded.updated_at
        """,
        (driver_id, body.lat, body.lng, body.heading),
    )
    conn.commit()
    return {"success": True}
