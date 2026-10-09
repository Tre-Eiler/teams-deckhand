"""Teams Bridge: Microsoft Teams call, microphone and camera state in Home Assistant.

Connects to the Teams Bridge macOS app's read-only status feed and mirrors it
as entities. Reporting only — nothing here can control Teams.
"""
from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_HOST, CONF_PORT, Platform
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .client import TeamsBridgeClient

PLATFORMS = [Platform.BINARY_SENSOR, Platform.SENSOR]

TeamsBridgeConfigEntry = ConfigEntry[TeamsBridgeClient]


async def async_setup_entry(hass: HomeAssistant, entry: TeamsBridgeConfigEntry) -> bool:
    client = TeamsBridgeClient(async_get_clientsession(hass), entry.data[CONF_HOST], entry.data[CONF_PORT])
    entry.runtime_data = client
    # Reconnects forever on its own; cancelled automatically when the entry unloads.
    entry.async_create_background_task(hass, client.async_run(), name=f"teams_bridge {entry.data[CONF_HOST]}")
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: TeamsBridgeConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
