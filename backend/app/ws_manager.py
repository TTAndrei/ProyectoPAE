import json
import logging
from typing import Dict
from fastapi import WebSocket

logger = logging.getLogger("ws_manager")


class GestorConexiones:
    def __init__(self) -> None:
        self._repartidores: Dict[str, WebSocket] = {}
        self._centrales: list[WebSocket] = []

    async def conectar_repartidor(self, id_repartidor: str, ws: WebSocket) -> None:
        await ws.accept()
        self._repartidores[id_repartidor] = ws
        print(f"[WS_MANAGER] Repartidor CONECTADO: {id_repartidor}  |  Total repartidores: {list(self._repartidores.keys())}")

    async def conectar_central(self, ws: WebSocket) -> None:
        await ws.accept()
        self._centrales.append(ws)
        print(f"[WS_MANAGER] Central CONECTADA  |  Total centrales: {len(self._centrales)}")

    def desconectar_repartidor(self, id_repartidor: str) -> None:
        self._repartidores.pop(id_repartidor, None)
        print(f"[WS_MANAGER] Repartidor DESCONECTADO: {id_repartidor}  |  Total repartidores: {list(self._repartidores.keys())}")

    def desconectar_central(self, ws: WebSocket) -> None:
        if ws in self._centrales:
            self._centrales.remove(ws)
        print(f"[WS_MANAGER] Central DESCONECTADA  |  Total centrales: {len(self._centrales)}")

    async def difundir_a_central(self, mensaje: dict) -> None:
        print(f"[WS_MANAGER] Difundir a central: type={mensaje.get('type')}  |  Total centrales: {len(self._centrales)}")
        muertas: list[WebSocket] = []
        for ws in list(self._centrales):
            try:
                await ws.send_json(mensaje)
            except Exception as e:
                print(f"[WS_MANAGER] Error enviando a central: {e}")
                muertas.append(ws)
        for ws in muertas:
            self.desconectar_central(ws)

    async def enviar_a_repartidor(self, id_repartidor: str, mensaje: dict) -> None:
        print(f"[WS_MANAGER] Intentando enviar a repartidor '{id_repartidor}': type={mensaje.get('type')}")
        print(f"[WS_MANAGER] Repartidores registrados: {list(self._repartidores.keys())}")
        ws = self._repartidores.get(id_repartidor)
        if ws:
            try:
                await ws.send_json(mensaje)
                print(f"[WS_MANAGER] ✅ Mensaje enviado exitosamente a '{id_repartidor}'")
            except Exception as e:
                print(f"[WS_MANAGER] ❌ Error enviando a '{id_repartidor}': {e}")
                self.desconectar_repartidor(id_repartidor)
        else:
            print(f"[WS_MANAGER] ⚠️ Repartidor '{id_repartidor}' NO ENCONTRADO en conexiones activas")


gestor = GestorConexiones()
