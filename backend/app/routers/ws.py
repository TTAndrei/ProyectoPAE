"""WebSocket router for real-time driver location updates and pickup notifications."""
import json
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, HTTPException

from app.auth import decode_token
from app.database import get_connection
from app.routing import calculate_extra_time
from app.ws_manager import manager

router = APIRouter(tags=["websocket"])


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket, token: str = Query(...)):
    """
    Unified WebSocket endpoint.  Clients authenticate via ?token=<jwt>.

    Driver → server messages:
        { "type": "driver:location", "lat": ..., "lng": ..., "heading": ... }
        { "type": "driver:pickup:response", "order_id": "...", "accepted": true/false }

    Server → Central messages:
        { "type": "driver:location:update", "driver_id": ..., "name": ..., "lat": ..., "lng": ..., "heading": ... }
        { "type": "driver:offline", "driver_id": ... }
        { "type": "pickup:response", "order_id": ..., "driver_id": ..., "driver_name": ..., "accepted": ... }

    Central → server messages:
        { "type": "central:pickup:notify", "order_id": "...", "driver_id": "..." }

    Server → Driver messages:
        { "type": "pickup:notification", "order": {...}, "extra_minutes": ... }
    """
    try:
        user = decode_token(token)
    except HTTPException:
        await websocket.close(code=1008)
        return

    user_id: str = user["id"]
    role: str = user["role"]
    name: str = user["name"]

    if role == "repartidor":
        await manager.connect_driver(user_id, websocket)
    else:
        await manager.connect_central(websocket)

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                continue

            msg_type = msg.get("type")

            # ── Driver sends location update ───────────────────────────────
            if msg_type == "driver:location" and role == "repartidor":
                lat = msg.get("lat")
                lng = msg.get("lng")
                heading = msg.get("heading", 0)

                if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                    continue

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
                    (user_id, lat, lng, heading),
                )
                conn.commit()

                await manager.broadcast_to_central({
                    "type": "driver:location:update",
                    "driver_id": user_id,
                    "name": name,
                    "lat": lat,
                    "lng": lng,
                    "heading": heading,
                })

            # ── Central pushes a pickup notification to a driver ───────────
            elif msg_type == "central:pickup:notify" and role == "central":
                order_id = msg.get("order_id")
                driver_id = msg.get("driver_id")
                if not order_id or not driver_id:
                    continue

                conn = get_connection()
                order_row = conn.execute(
                    "SELECT * FROM orders WHERE id = ?", (order_id,)
                ).fetchone()
                if not order_row:
                    continue

                driver_loc = conn.execute(
                    "SELECT * FROM driver_locations WHERE driver_id = ?", (driver_id,)
                ).fetchone()
                active_route = conn.execute(
                    "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
                    (driver_id,),
                ).fetchone()

                extra_minutes = 0.0
                if driver_loc and active_route:
                    order_ids = json.loads(active_route["order_ids"])
                    stops: list[dict] = []
                    if order_ids:
                        placeholders = ",".join("?" * len(order_ids))
                        stops = [
                            {"lat": r["lat"], "lng": r["lng"]}
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
                        {"lat": order_row["lat"], "lng": order_row["lng"]},
                    )
                    extra_minutes = result["extra_minutes"]

                conn.execute(
                    """
                    UPDATE orders
                    SET assigned_driver_id = ?, estimated_extra_minutes = ?,
                        status = 'assigned', updated_at = datetime('now')
                    WHERE id = ?
                    """,
                    (driver_id, extra_minutes, order_id),
                )
                conn.commit()

                await manager.send_to_driver(driver_id, {
                    "type": "pickup:notification",
                    "order": dict(order_row),
                    "extra_minutes": extra_minutes,
                })

            # ── Driver responds to a pickup notification ───────────────────
            elif msg_type == "driver:pickup:response" and role == "repartidor":
                order_id = msg.get("order_id")
                accepted = msg.get("accepted")
                if not order_id or accepted is None:
                    continue

                conn = get_connection()
                order_row = conn.execute(
                    "SELECT * FROM orders WHERE id = ?", (order_id,)
                ).fetchone()
                if not order_row or order_row["assigned_driver_id"] != user_id:
                    continue

                new_status = "in_progress" if accepted else "rejected"
                conn.execute(
                    "UPDATE orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
                    (new_status, order_id),
                )

                if accepted:
                    active_route = conn.execute(
                        "SELECT * FROM routes WHERE driver_id = ? AND status = 'active'",
                        (user_id,),
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

                await manager.broadcast_to_central({
                    "type": "pickup:response",
                    "order_id": order_id,
                    "driver_id": user_id,
                    "driver_name": name,
                    "accepted": accepted,
                })

    except WebSocketDisconnect:
        if role == "repartidor":
            manager.disconnect_driver(user_id)
            await manager.broadcast_to_central({
                "type": "driver:offline",
                "driver_id": user_id,
            })
        else:
            manager.disconnect_central(websocket)
