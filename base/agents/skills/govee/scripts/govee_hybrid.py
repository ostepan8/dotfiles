"""Merge Govee cloud metadata with locally discovered LAN devices."""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass

from govee_api import Capability, Device
from govee_lan import LanDevice, LanStatus

LIGHT_TYPE = "devices.types.light"
LAN_ONLY_NAMES = {"H8022": "Bedside Lamp"}


@dataclass(frozen=True)
class HybridDevice:
    sku: str
    device_id: str
    name: str
    device_type: str
    capabilities: tuple[Capability, ...]
    cloud: Device | None
    lan: LanDevice | None


def _identity(device_id: str) -> str:
    return re.sub(r"[^0-9A-Za-z]", "", device_id).casefold()


def _lan_capabilities() -> tuple[Capability, ...]:
    return (
        Capability("devices.capabilities.on_off", "powerSwitch", {}),
        Capability(
            "devices.capabilities.range",
            "brightness",
            {"range": {"min": 1, "max": 100}},
        ),
        Capability("devices.capabilities.color_setting", "colorRgb", {}),
        Capability(
            "devices.capabilities.color_setting",
            "colorTemperatureK",
            {"range": {"min": 2000, "max": 9000}},
        ),
    )


def _from_cloud(device: Device, lan: LanDevice | None) -> HybridDevice:
    return HybridDevice(
        device.sku,
        device.device_id,
        device.name,
        device.device_type,
        device.capabilities,
        device,
        lan,
    )


def _lan_name(device: LanDevice, same_sku_count: int) -> str:
    preferred = LAN_ONLY_NAMES.get(device.sku)
    if preferred and same_sku_count == 1:
        return preferred
    return f"LAN Lamp {device.sku}"


def _matching_lan(device: Device, lan_by_id: dict[str, LanDevice]) -> LanDevice | None:
    candidate = lan_by_id.get(_identity(device.device_id))
    return candidate if candidate is not None and candidate.sku == device.sku else None


def merge_devices(
    cloud_devices: Sequence[Device], lan_devices: Sequence[LanDevice]
) -> tuple[HybridDevice, ...]:
    unique_cloud: tuple[Device, ...] = ()
    cloud_ids: frozenset[str] = frozenset()
    for item in cloud_devices:
        identity = _identity(item.device_id)
        if identity not in cloud_ids:
            unique_cloud = unique_cloud + (item,)
            cloud_ids = cloud_ids | frozenset((identity,))

    lan_by_id: dict[str, LanDevice] = {}
    for item in lan_devices:
        identity = _identity(item.device_id)
        if identity not in lan_by_id:
            lan_by_id = {**lan_by_id, identity: item}

    merged = tuple(
        _from_cloud(item, _matching_lan(item, lan_by_id))
        for item in unique_cloud
    )
    unique_lan = tuple(lan_by_id.values())
    lan_only = tuple(
        item for item in unique_lan if _identity(item.device_id) not in cloud_ids
    )
    extra = tuple(
        HybridDevice(
            item.sku,
            item.device_id,
            _lan_name(item, sum(other.sku == item.sku for other in lan_only)),
            LIGHT_TYPE,
            _lan_capabilities(),
            None,
            item,
        )
        for item in lan_only
    )
    return tuple(
        sorted(merged + extra, key=lambda item: (item.name.casefold(), item.device_id))
    )


def lan_state_capabilities(status: LanStatus) -> tuple[dict, ...]:
    color = (status.color_r << 16) | (status.color_g << 8) | status.color_b
    return (
        {"instance": "online", "state": {"value": True}},
        {"instance": "powerSwitch", "state": {"value": 1 if status.on else 0}},
        {"instance": "brightness", "state": {"value": status.brightness}},
        {"instance": "colorRgb", "state": {"value": color}},
        {
            "instance": "colorTemperatureK",
            "state": {"value": status.color_temp_kelvin},
        },
    )
