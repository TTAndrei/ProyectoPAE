"""Orders router."""
import json
import uuid
from fastapi import APIRouter, HTTPException, status, Depends

from app.database import get_connection
from app.schemas import (
    OrderCreate, OrderAssign, OrderRespond, OrderStatusUpdate, OrderOut, RouteOut,
)
from app.auth import get_current_user, require_central
from app.routing import calculate_extra_time

router = APIRouter(prefix="/orders", tags=["orders"])


def _row_to_order(row) -> dict:
    return dict(row)


@router.get("/", response_model=list[OrderOut])
def list_orders(current_user: dict = Depends(get_current_user)):
    """Return orders. Central sees all; driver sees their own + pending pickups."""
    conn = get_connection()
    if current_user["role"] == "central":
        rows = conn.execute("SELECT * FROM orders ORDER BY created_at DESC").fetchall()
    else:
        rows = conn.execute(
            """
            SELECT * FROM orders
            WHERE assigned_driver_id = ? OR status = 'pending'
            ORDER BY created_at DESC
            """,
            (current_user["id"],),
        ).fetchall()
    return [_row_to_order(r) for r in rows]


@router.post("/", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
def create_order(body: OrderCreate, _: dict = Depends(require_central)):
    order_id = str(uuid.uuid4())
    conn = get_connection()
    conn.execute(
        "INSERT INTO orders (id, type, address, lat, lng, status) VALUES (?,?,?,?,?,?)",
        (order_id, body.type, body.address, body.lat, body.lng, "pending"),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    return _row_to_order(row)


@router.post("/{order_id}/assign")
def assign_order(
    order_id: str,
    body: OrderAssign,
    _: dict = Depends(require_central),
):
    """Assign a pending order to a driver, calculating estimated extra time."""
    conn = get_connection()
    order = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    driver_loc = conn.execute(
        "SELECT * FROM driver_locations WHERE driver_id = ?", (body.driver_id,)
    ).fetchone()

    active_route = conn.execute(
        "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
        (body.driver_id,),
    ).fetchone()

    extra_minutes = 0.0
    if driver_loc and active_route:
        order_ids = json.loads(active_route["order_ids"])
        stops: list[dict] = []
        if order_ids:
            placeholders = ",".join("?" * len(order_ids))
            stops = [
                dict(r)
                for r in conn.execute(
                    f"SELECT lat, lng FROM orders "
                    f"WHERE id IN ({placeholders}) "
                    f"AND status NOT IN ('completed','rejected')",
                    order_ids,
                ).fetchall()
            ]
        result = calculate_extra_time(
            stops,
            {"lat": driver_loc["lat"], "lng": driver_loc["lng"]},
            {"lat": order["lat"], "lng": order["lng"]},
        )
        extra_minutes = result["extra_minutes"]

    conn.execute(
        """
        UPDATE orders
        SET assigned_driver_id = ?, status = 'assigned',
            estimated_extra_minutes = ?, updated_at = datetime('now')
        WHERE id = ?
        """,
        (body.driver_id, extra_minutes, order_id),
    )
    conn.commit()

    updated = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    return {"order": _row_to_order(updated), "extra_minutes": extra_minutes}


@router.post("/{order_id}/respond")
def respond_to_order(
    order_id: str,
    body: OrderRespond,
    current_user: dict = Depends(get_current_user),
):
    """Driver accepts or rejects a pickup notification."""
    if current_user["role"] != "repartidor":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")

    conn = get_connection()
    order = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order["assigned_driver_id"] != current_user["id"]:
        raise HTTPException(status_code=403, detail="This order is not assigned to you")

    new_status = "in_progress" if body.accepted else "rejected"
    conn.execute(
        "UPDATE orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
        (new_status, order_id),
    )

    if body.accepted:
        active_route = conn.execute(
            "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
            (current_user["id"],),
        ).fetchone()
        if active_route:
            ids = json.loads(active_route["order_ids"])
            if order_id not in ids:
                ids.append(order_id)
                conn.execute(
                    "UPDATE routes SET order_ids = ?, updated_at = datetime('now') WHERE id = ?",
                    (json.dumps(ids), active_route["id"]),
                )

    conn.commit()
    updated = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    return {"order": _row_to_order(updated)}


@router.patch("/{order_id}/status")
def update_order_status(
    order_id: str,
    body: OrderStatusUpdate,
    current_user: dict = Depends(get_current_user),
):
    conn = get_connection()
    order = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if current_user["role"] == "repartidor" and order["assigned_driver_id"] != current_user["id"]:
        raise HTTPException(status_code=403, detail="This order is not assigned to you")

    conn.execute(
        "UPDATE orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
        (body.status, order_id),
    )
    conn.commit()
    updated = conn.execute("SELECT * FROM orders WHERE id = ?", (order_id,)).fetchone()
    return {"order": _row_to_order(updated)}


@router.get("/route/{driver_id}", response_model=RouteOut)
def get_driver_route(driver_id: str, current_user: dict = Depends(get_current_user)):
    if current_user["role"] != "central" and (
        current_user["role"] != "repartidor" or current_user["id"] != driver_id
    ):
        raise HTTPException(status_code=403, detail="Forbidden")

    conn = get_connection()
    route = conn.execute(
        "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'", (driver_id,)
    ).fetchone()
    if not route:
        raise HTTPException(status_code=404, detail="No active route found")

    order_ids = json.loads(route["order_ids"])
    orders: list[dict] = []
    if order_ids:
        placeholders = ",".join("?" * len(order_ids))
        orders = [
            _row_to_order(r)
            for r in conn.execute(
                f"SELECT * FROM orders WHERE id IN ({placeholders})", order_ids
            ).fetchall()
        ]

    return {**dict(route), "orders": orders}
