"""Gestor de conexiones WebSocket para actualizaciones de ubicación en tiempo real.

Mantiene un registro de todos los WebSockets activos separados por rol:
- _repartidores: un WebSocket por repartidor (clave = id del repartidor)
- _centrales: lista de WebSockets de operadores centrales (puede haber varios)

Al desconectarse un repartidor, se notifica automáticamente a todos los
operadores centrales para que actualicen el mapa.
"""
import asyncio
import json
from typing import Dict
from fastapi import WebSocket


class GestorConexiones:
    """Gestiona todas las conexiones WebSocket activas por tipo de usuario.

    Uso típico:
        gestor = GestorConexiones()
        await gestor.conectar_repartidor("driver-1", websocket)
        await gestor.difundir_a_central({"type": "driver:location:update", ...})
    """

    def __init__(self) -> None:
        # Diccionario id_repartidor → WebSocket
        self._repartidores: Dict[str, WebSocket] = {}
        # Lista de WebSockets de operadores centrales conectados
        self._centrales: list[WebSocket] = []

    # ── Ciclo de vida de conexiones ────────────────────────────────────────────

    async def conectar_repartidor(self, id_repartidor: str, ws: WebSocket) -> None:
        """Acepta y registra la conexión WebSocket de un repartidor."""
        await ws.accept()
        self._repartidores[id_repartidor] = ws

    async def conectar_central(self, ws: WebSocket) -> None:
        """Acepta y registra la conexión WebSocket de un operador central."""
        await ws.accept()
        self._centrales.append(ws)

    def desconectar_repartidor(self, id_repartidor: str) -> None:
        """Elimina el WebSocket del repartidor del registro."""
        self._repartidores.pop(id_repartidor, None)

    def desconectar_central(self, ws: WebSocket) -> None:
        """Elimina el WebSocket de un operador central del registro."""
        if ws in self._centrales:
            self._centrales.remove(ws)

    # ── Métodos de envío de mensajes ───────────────────────────────────────────

    async def difundir_a_central(self, mensaje: dict) -> None:
        """Envía un mensaje JSON a todos los operadores centrales conectados.

        Si alguna conexión falla (cliente desconectado sin notificación),
        se elimina automáticamente del registro.
        """
        conexiones_muertas: list[WebSocket] = []
        for ws in list(self._centrales):
            try:
                await ws.send_json(mensaje)
            except Exception:
                # Conexión rota: se eliminará al terminar el bucle
                conexiones_muertas.append(ws)
        for ws in conexiones_muertas:
            self.desconectar_central(ws)

    async def enviar_a_repartidor(self, id_repartidor: str, mensaje: dict) -> None:
        """Envía un mensaje JSON a un repartidor específico.

        Si el repartidor no está conectado o la conexión falló, no hace nada.
        """
        ws = self._repartidores.get(id_repartidor)
        if ws:
            try:
                await ws.send_json(mensaje)
            except Exception:
                # Conexión rota → limpiar el registro
                self.desconectar_repartidor(id_repartidor)


# Instancia única (singleton) compartida entre todos los routers de la aplicación
gestor = GestorConexiones()
