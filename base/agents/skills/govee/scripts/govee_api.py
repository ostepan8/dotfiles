"""Immutable Govee API models, validation, and request construction."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from types import MappingProxyType
from typing import Any, Protocol, TypeVar
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4


class GoveeError(Exception):
    """Base error for user-facing Govee failures."""


class InputError(GoveeError):
    """Configuration, selection, or command input is invalid."""


class ApiError(GoveeError):
    """The Govee API rejected or returned an invalid response."""


JsonValue = Any


class SelectableDevice(Protocol):
    @property
    def device_id(self) -> str: ...

    @property
    def name(self) -> str: ...


Selectable = TypeVar("Selectable", bound=SelectableDevice)


@dataclass(frozen=True)
class Capability:
    type: str
    instance: str
    parameters: Mapping[str, JsonValue]


@dataclass(frozen=True)
class Device:
    sku: str
    device_id: str
    name: str
    device_type: str
    capabilities: tuple[Capability, ...]


def _freeze(value: JsonValue) -> JsonValue:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


def parse_color(raw: str) -> tuple[int, int, int]:
    """Parse RRGGBB/#RRGGBB or decimal r,g,b into a validated tuple."""
    value = raw.strip()
    if "," in value:
        parts = value.split(",")
        if len(parts) != 3:
            raise InputError("Color must have exactly three RGB components")
        try:
            rgb = tuple(int(part.strip()) for part in parts)
        except ValueError as error:
            raise InputError("RGB components must be whole numbers") from error
    else:
        digits = value.removeprefix("#")
        if len(digits) != 6:
            raise InputError("Hex color must contain exactly six digits")
        try:
            rgb = tuple(int(digits[index : index + 2], 16) for index in (0, 2, 4))
        except ValueError as error:
            raise InputError("Hex color contains invalid digits") from error
    if any(component < 0 or component > 255 for component in rgb):
        raise InputError("RGB components must be between 0 and 255")
    return rgb  # type: ignore[return-value]


def pack_rgb(rgb: tuple[int, int, int]) -> int:
    red, green, blue = rgb
    return (red << 16) | (green << 8) | blue


def _api_message(body: Mapping[str, JsonValue], fallback: str) -> str:
    message = body.get("message") or body.get("msg")
    return str(message) if message else fallback


def _validate_success_envelope(body: JsonValue) -> Mapping[str, JsonValue]:
    if not isinstance(body, dict):
        raise ApiError("Govee returned an invalid JSON response")
    code = body.get("code")
    if code != 200:
        raise ApiError(_api_message(body, f"Govee API error {code!r}"))
    return body


def _parse_capability(raw: JsonValue) -> Capability:
    if not isinstance(raw, dict):
        raise TypeError("capability is not an object")
    cap_type = raw.get("type")
    instance = raw.get("instance")
    parameters = raw.get("parameters", {})
    if not isinstance(cap_type, str) or not isinstance(instance, str):
        raise TypeError("capability is missing type or instance")
    if not isinstance(parameters, dict):
        raise TypeError("capability parameters are not an object")
    return Capability(cap_type, instance, _freeze(parameters))


def _parse_device(raw: JsonValue) -> tuple[Device, tuple[str, ...]]:
    if not isinstance(raw, dict):
        raise TypeError("device is not an object")
    sku, device_id = raw.get("sku"), raw.get("device")
    if not isinstance(sku, str) or not isinstance(device_id, str):
        raise TypeError("device is missing sku or device id")
    name = raw.get("deviceName")
    display_name = name if isinstance(name, str) and name.strip() else device_id
    raw_type = raw.get("type")
    device_type = raw_type if isinstance(raw_type, str) else ""
    raw_capabilities = raw.get("capabilities", [])
    if not isinstance(raw_capabilities, list):
        raise TypeError("device capabilities are not a list")
    capabilities: tuple[Capability, ...] = ()
    warnings: tuple[str, ...] = ()
    for index, item in enumerate(raw_capabilities):
        try:
            capabilities = capabilities + (_parse_capability(item),)
        except TypeError as error:
            warnings = warnings + (
                f"Skipped capability {index} on {display_name}: {error}",
            )
    return (
        Device(sku, device_id, display_name, device_type, capabilities),
        warnings,
    )


def parse_devices(body: JsonValue) -> tuple[tuple[Device, ...], tuple[str, ...]]:
    envelope = _validate_success_envelope(body)
    raw_devices = envelope.get("data")
    if not isinstance(raw_devices, list):
        raise ApiError("Govee device response is missing a data list")
    devices: tuple[Device, ...] = ()
    warnings: tuple[str, ...] = ()
    for index, raw in enumerate(raw_devices):
        try:
            device, device_warnings = _parse_device(raw)
            devices = devices + (device,)
            warnings = warnings + device_warnings
        except TypeError as error:
            warnings = warnings + (f"Skipped device {index}: {error}",)
    if raw_devices and not devices:
        raise ApiError("Govee returned no usable devices: " + "; ".join(warnings))
    return devices, warnings


def _resolve_one(devices: Sequence[Selectable], selector: str) -> Selectable:
    exact_ids = tuple(item for item in devices if item.device_id == selector)
    if len(exact_ids) == 1:
        return exact_ids[0]
    normalized = selector.casefold()
    names = tuple(item for item in devices if item.name.casefold() == normalized)
    if len(names) == 1:
        return names[0]
    if len(names) > 1:
        ids = ", ".join(item.device_id for item in names)
        raise InputError(f"Multiple Govee devices are named {selector!r}: {ids}")
    raise InputError(f"No Govee device matches {selector!r}")


def select_devices(
    devices: Sequence[Selectable],
    selectors: Sequence[str],
    *,
    all_devices: bool = False,
) -> tuple[Selectable, ...]:
    if all_devices and selectors:
        raise InputError("Use either --device or --all, not both")
    if all_devices:
        return tuple(
            sorted(devices, key=lambda item: (item.name.casefold(), item.device_id))
        )
    if not selectors:
        if len(devices) == 1:
            return (devices[0],)
        raise InputError("Choose a lamp with --device or use --all")
    resolved = tuple(_resolve_one(devices, selector) for selector in selectors)
    seen: frozenset[str] = frozenset()
    unique: tuple[Selectable, ...] = ()
    for item in resolved:
        if item.device_id not in seen:
            unique = unique + (item,)
            seen = seen | frozenset((item.device_id,))
    return unique


def find_capability(device: Device, instance: str) -> Capability:
    for item in device.capabilities:
        if item.instance == instance:
            return item
    raise InputError(f"{device.name} does not support {instance}")


def validate_capability_value(capability: Capability, value: JsonValue) -> JsonValue:
    range_spec = capability.parameters.get("range")
    if not isinstance(range_spec, Mapping):
        return value
    minimum, maximum = range_spec.get("min"), range_spec.get("max")
    if isinstance(value, bool) or not isinstance(value, int):
        raise InputError(f"{capability.instance} must be a whole number")
    if not isinstance(minimum, (int, float)) or not isinstance(maximum, (int, float)):
        raise InputError(f"{capability.instance} has an invalid advertised range")
    if value < minimum or value > maximum:
        raise InputError(
            f"{capability.instance} must be between {minimum} and {maximum}"
        )
    return value


def build_control_payload(
    device: Device,
    instance: str,
    value: JsonValue,
    *,
    request_id: str,
) -> dict[str, JsonValue]:
    capability = find_capability(device, instance)
    checked_value = validate_capability_value(capability, value)
    return {
        "requestId": request_id,
        "payload": {
            "sku": device.sku,
            "device": device.device_id,
            "capability": {
                "type": capability.type,
                "instance": capability.instance,
                "value": checked_value,
            },
        },
    }


def validate_control_response(body: JsonValue) -> None:
    envelope = _validate_success_envelope(body)
    capability = envelope.get("capability")
    if not isinstance(capability, dict):
        payload = envelope.get("payload")
        capability = payload.get("capability") if isinstance(payload, dict) else None
    state = capability.get("state") if isinstance(capability, dict) else None
    if isinstance(state, dict) and str(state.get("status", "")).casefold() == "failure":
        message = state.get("errorMsg") or _api_message(
            envelope, "Govee device refused the command"
        )
        raise ApiError(str(message))


class GoveeClient:
    """Small synchronous client for Govee's capability-based cloud API."""

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = "https://openapi.api.govee.com/router/api/v1",
        timeout: int = 10,
        opener=urlopen,
        request_id_factory=lambda: str(uuid4()),
    ) -> None:
        if not api_key.strip():
            raise InputError("Govee API key is empty")
        self._api_key = api_key.strip()
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout
        self._opener = opener
        self._request_id_factory = request_id_factory

    def _headers(self) -> dict[str, str]:
        return {
            "Content-Type": "application/json",
            "Govee-API-Key": self._api_key,
        }

    def _http_error(self, error: HTTPError) -> ApiError:
        if error.code in (401, 403):
            return ApiError("Govee API key was rejected; run `govee setup` again")
        if error.code == 429:
            retry_after = error.headers.get("Retry-After") if error.headers else None
            suffix = f"; retry after {retry_after} seconds" if retry_after else ""
            return ApiError(f"Govee API rate limit reached{suffix}")
        if error.code >= 500:
            return ApiError(f"Govee service is temporarily unavailable ({error.code})")
        return ApiError(f"Govee API request failed with HTTP {error.code}")

    def _request(
        self, method: str, path: str, body: Mapping[str, JsonValue] | None = None
    ) -> JsonValue:
        encoded = json.dumps(body).encode() if body is not None else None
        request = Request(
            f"{self._base_url}{path}",
            data=encoded,
            headers=self._headers(),
            method=method,
        )
        try:
            with self._opener(request, timeout=self._timeout) as response:
                raw = response.read()
        except HTTPError as error:
            api_error = self._http_error(error)
            error.close()
            raise api_error from error
        except (URLError, TimeoutError, OSError) as error:
            raise ApiError("Could not connect to the Govee API") from error
        try:
            return json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ApiError("Govee returned an invalid JSON response") from error

    def _safe(self, operation):
        try:
            return operation()
        except ApiError as error:
            message = str(error).replace(self._api_key, "[redacted]")
            raise ApiError(message) from error

    def parse_device_response(
        self, body: JsonValue
    ) -> tuple[tuple[Device, ...], tuple[str, ...]]:
        return self._safe(lambda: parse_devices(body))

    def devices(self) -> tuple[tuple[Device, ...], tuple[str, ...]]:
        body = self._request("GET", "/user/devices")
        return self.parse_device_response(body)

    def state(self, device: Device) -> tuple[Mapping[str, JsonValue], ...]:
        body = self._request(
            "POST",
            "/device/state",
            {
                "requestId": self._request_id_factory(),
                "payload": {"sku": device.sku, "device": device.device_id},
            },
        )

        def parse_state() -> tuple[Mapping[str, JsonValue], ...]:
            envelope = _validate_success_envelope(body)
            payload = envelope.get("payload", envelope.get("data"))
            capabilities = (
                payload.get("capabilities") if isinstance(payload, dict) else None
            )
            if not isinstance(capabilities, list):
                raise ApiError("Govee state response is missing capabilities")
            if not all(isinstance(item, dict) for item in capabilities):
                raise ApiError("Govee state response contains an invalid capability")
            return tuple(_freeze(item) for item in capabilities)

        return self._safe(parse_state)

    def control(self, device: Device, instance: str, value: JsonValue) -> None:
        body = build_control_payload(
            device,
            instance,
            value,
            request_id=self._request_id_factory(),
        )
        response = self._request("POST", "/device/control", body)
        self._safe(lambda: validate_control_response(response))
