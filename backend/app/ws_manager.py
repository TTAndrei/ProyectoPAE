import json
from typing import Dict
from fastapi import WebSocket


class GestorConexiones:
    def __init__(self) -> None:
        self._repartidores: Dict[str, WebSocket] = {}
        self._centrales: list[WebSocket] = []

    async def conectar_repartidor(self, id_repartidor: str, ws: WebSocket) -> None:
        await ws.accept()
        self._repartidores[id_repartidor] = ws

    async def conectar_central(self, ws: WebSocket) -> None:
        await ws.accept()
        self._centrales.append(ws)

    def desconectar_repartidor(self, id_repartidor: str) -> None:
        self._repartidores.pop(id_repartidor, None)

    def desconectar_central(self, ws: WebSocket) -> None:
        if ws in self._centrales:
            self._centrales.remove(ws)

    async def difundir_a_central(self, mensaje: dict) -> None:
        muertas: list[WebSocket] = []
        for ws in list(self._centrales):
            try:
                await ws.send_json(mensaje)
            except Exception:
                muertas.append(ws)
        for ws in muertas:
            self.desconectar_central(ws)

    async def enviar_a_repartidor(self, id_repartidor: str, mensaje: dict) -> None:
        ws = self._repartidores.get(id_repartidor)
        if ws:
            try:
                await ws.send_json(mensaje)
            except Exception:
                self.desconectar_repartidor(id_repartidor)


gestor = GestorConexiones()
