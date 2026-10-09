"""Shared base for Deckhand entities."""
from __future__ import annotations

from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity import Entity, EntityDescription

from .client import TeamsBridgeClient
from .const import DOMAIN


class TeamsBridgeEntity(Entity):
    """An entity that mirrors one field of the Deckhand status feed."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, entry, client: TeamsBridgeClient, description: EntityDescription) -> None:
        self._client = client
        self.entity_description = description
        self._attr_unique_id = f"{entry.entry_id}_{description.key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.entry_id)},
            name=f"Deckhand ({entry.data[CONF_HOST]})",
            manufacturer="Deckhand",
            model="macOS menu bar app",
            configuration_url=f"http://{entry.data[CONF_HOST]}:{entry.data[CONF_PORT]}/status",
        )

    @property
    def available(self) -> bool:
        # Unavailable (not "off") while the Mac is asleep or the app isn't
        # running: we don't know, so don't claim you're not in a call.
        return self._client.connected

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(self._client.add_listener(self.async_write_ha_state))
