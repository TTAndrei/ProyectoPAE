"""WebSocket connection manager for real-time location updates."""
import asyncio
import json
from typing import Dict
from fastapi import WebSocket


class ConnectionManager:
    """Keeps track of active WebSocket connections by user id and role."""

    def __init__(self) -> None:
        # driver_id -> WebSocket
        self._drivers: Dict[str, WebSocket] = {}
        # list of central connections
        self._central: list[WebSocket] = []

    # ── Connection lifecycle ───────────────────────────────────────────────────

    async def connect_driver(self, driver_id: str, ws: WebSocket) -> None:
        await ws.accept()
        self._drivers[driver_id] = ws

    async def connect_central(self, ws: WebSocket) -> None:
        await ws.accept()
        self._central.append(ws)

    def disconnect_driver(self, driver_id: str) -> None:
        self._drivers.pop(driver_id, None)

    def disconnect_central(self, ws: WebSocket) -> None:
        if ws in self._central:
            self._central.remove(ws)

    # ── Broadcast helpers ─────────────────────────────────────────────────────

    async def broadcast_to_central(self, message: dict) -> None:
        """Send a JSON message to all connected Central users."""
        dead: list[WebSocket] = []
        for ws in list(self._central):
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect_central(ws)

    async def send_to_driver(self, driver_id: str, message: dict) -> None:
        """Send a JSON message to a specific driver."""
        ws = self._drivers.get(driver_id)
        if ws:
            try:
                await ws.send_json(message)
            except Exception:
                self.disconnect_driver(driver_id)


# Singleton instance shared across all routers
manager = ConnectionManager()
