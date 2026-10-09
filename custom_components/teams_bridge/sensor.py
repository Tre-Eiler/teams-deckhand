"""Sensors for Deckhand."""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.const import UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity import EntityCategory
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .entity import TeamsBridgeEntity


@dataclass(frozen=True, kw_only=True)
class TeamsBridgeSensorDescription(SensorEntityDescription):
    value_fn: Callable[[dict[str, Any]], int | None]


DESCRIPTIONS: tuple[TeamsBridgeSensorDescription, ...] = (
    TeamsBridgeSensorDescription(
        key="auto_mute_countdown",
        name="Auto-mute countdown",
        icon="mdi:timer-sand",
        device_class=SensorDeviceClass.DURATION,
        native_unit_of_measurement=UnitOfTime.SECONDS,
        state_class=SensorStateClass.MEASUREMENT,
        # None (unknown) whenever no countdown is running.
        value_fn=lambda s: s.get("autoMuteRemainingSeconds"),
    ),
    TeamsBridgeSensorDescription(
        key="auto_mute_timeout",
        name="Auto-mute timeout",
        icon="mdi:timer-cog",
        device_class=SensorDeviceClass.DURATION,
        native_unit_of_measurement=UnitOfTime.SECONDS,
        entity_category=EntityCategory.DIAGNOSTIC,
        value_fn=lambda s: s.get("autoMuteTimeoutSeconds"),
    ),
)


async def async_setup_entry(hass: HomeAssistant, entry, async_add_entities: AddEntitiesCallback) -> None:
    client = entry.runtime_data
    async_add_entities(TeamsBridgeSensor(entry, client, description) for description in DESCRIPTIONS)


class TeamsBridgeSensor(TeamsBridgeEntity, SensorEntity):
    entity_description: TeamsBridgeSensorDescription

    @property
    def native_value(self) -> int | None:
        return self.entity_description.value_fn(self._client.status)
