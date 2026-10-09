"""Binary sensors for Deckhand."""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
    BinarySensorEntityDescription,
)
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import EntityCategory
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .entity import TeamsBridgeEntity


@dataclass(frozen=True, kw_only=True)
class TeamsBridgeBinarySensorDescription(BinarySensorEntityDescription):
    value_fn: Callable[[dict[str, Any]], bool]
    icon_on: str
    icon_off: str


DESCRIPTIONS: tuple[TeamsBridgeBinarySensorDescription, ...] = (
    TeamsBridgeBinarySensorDescription(
        key="in_call",
        name="In a call",
        value_fn=lambda s: bool(s.get("inCall")),
        icon_on="mdi:phone-in-talk",
        icon_off="mdi:phone-hangup",
    ),
    TeamsBridgeBinarySensorDescription(
        key="microphone_enabled",
        name="Microphone enabled",
        value_fn=lambda s: bool(s.get("micEnabled")),
        icon_on="mdi:microphone",
        icon_off="mdi:microphone-off",
    ),
    TeamsBridgeBinarySensorDescription(
        key="camera_enabled",
        name="Camera enabled",
        value_fn=lambda s: bool(s.get("cameraEnabled")),
        icon_on="mdi:video",
        icon_off="mdi:video-off",
    ),
    TeamsBridgeBinarySensorDescription(
        key="hand_raised",
        name="Hand raised",
        value_fn=lambda s: bool(s.get("handRaised")),
        icon_on="mdi:hand-back-right",
        icon_off="mdi:hand-back-right-off",
    ),
    TeamsBridgeBinarySensorDescription(
        key="auto_mute_enabled",
        name="Auto-mute enabled",
        value_fn=lambda s: bool(s.get("autoMuteEnabled")),
        icon_on="mdi:timer-sand",
        icon_off="mdi:timer-off",
    ),
    TeamsBridgeBinarySensorDescription(
        key="auto_mute_paused",
        name="Auto-mute can't hear microphone",
        device_class=BinarySensorDeviceClass.PROBLEM,
        entity_category=EntityCategory.DIAGNOSTIC,
        value_fn=lambda s: bool(s.get("autoMuteHolding")),
        icon_on="mdi:microphone-question",
        icon_off="mdi:microphone-check",
    ),
)


async def async_setup_entry(hass: HomeAssistant, entry, async_add_entities: AddEntitiesCallback) -> None:
    client = entry.runtime_data
    async_add_entities(TeamsBridgeBinarySensor(entry, client, description) for description in DESCRIPTIONS)


class TeamsBridgeBinarySensor(TeamsBridgeEntity, BinarySensorEntity):
    entity_description: TeamsBridgeBinarySensorDescription

    @property
    def is_on(self) -> bool:
        return self.entity_description.value_fn(self._client.status)

    @property
    def icon(self) -> str:
        description = self.entity_description
        return description.icon_on if self.is_on else description.icon_off
