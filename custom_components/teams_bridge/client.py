"""Push client for the Teams Bridge status feed.

Deliberately free of Home Assistant imports so it can be tested on its own.

The Teams Bridge macOS app serves a read-only feed on its network port:
``GET /status`` (a snapshot) and ``/ws`` (a WebSocket that sends the current
status on connect and again whenever it changes). Controls aren't reachable
over the network by design; this integration only reports state.
"""
from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Callable
from typing import Any

import aiohttp

_LOGGER = logging.getLogger(__name__)

RECONNECT_MIN_SECONDS = 1.0
RECONNECT_MAX_SECONDS = 30.0
REQUEST_TIMEOUT = aiohttp.ClientTimeout(total=10)
HEARTBEAT_SECONDS = 20


class TeamsBridgeClient:
    """Keeps a WebSocket open to one Teams Bridge app and tracks its status."""

    def __init__(self, session: aiohttp.ClientSession, host: str, port: int) -> None:
        self._session = session
        self.host = host
        self.port = port
        self.status: dict[str, Any] = {}
        self.connected = False
        self._listeners: list[Callable[[], None]] = []

    @property
    def status_url(self) -> str:
        return f"http://{self.host}:{self.port}/status"

    @property
    def ws_url(self) -> str:
        return f"ws://{self.host}:{self.port}/ws"

    def add_listener(self, callback: Callable[[], None]) -> Callable[[], None]:
        """Calls `callback` on every status or availability change. Returns a remover."""
        self._listeners.append(callback)

        def remove() -> None:
            if callback in self._listeners:
                self._listeners.remove(callback)

        return remove

    async def async_fetch_status(self) -> dict[str, Any]:
        """One-off snapshot; used to validate an address. Raises on failure."""
        async with self._session.get(self.status_url, timeout=REQUEST_TIMEOUT) as response:
            response.raise_for_status()
            data = await response.json(content_type=None)
        if not isinstance(data, dict) or "inCall" not in data:
            raise ValueError("That address doesn't look like Teams Bridge")
        return data

    async def async_run(self) -> None:
        """Connects and stays connected until cancelled, retrying with backoff."""
        delay = RECONNECT_MIN_SECONDS
        while True:
            try:
                async with self._session.ws_connect(self.ws_url, heartbeat=HEARTBEAT_SECONDS) as ws:
                    delay = RECONNECT_MIN_SECONDS
                    async for message in ws:
                        if message.type == aiohttp.WSMsgType.TEXT:
                            self._handle_frame(message.data)
                        elif message.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR):
                            break
            except asyncio.CancelledError:
                raise
            except (aiohttp.ClientError, asyncio.TimeoutError, OSError) as err:
                _LOGGER.debug("Teams Bridge connection to %s:%s failed: %s", self.host, self.port, err)

            self._set_connected(False)
            await asyncio.sleep(delay)
            delay = min(delay * 2, RECONNECT_MAX_SECONDS)

    def _handle_frame(self, data: str) -> None:
        try:
            status = json.loads(data)
        except ValueError:
            _LOGGER.debug("Ignoring malformed Teams Bridge frame")
            return
        if not isinstance(status, dict):
            return
        self.status = status
        self.connected = True
        self._notify()

    def _set_connected(self, connected: bool) -> None:
        if self.connected != connected:
            self.connected = connected
            self._notify()

    def _notify(self) -> None:
        for callback in list(self._listeners):
            callback()
