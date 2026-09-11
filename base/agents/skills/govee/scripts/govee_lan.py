"""Govee LAN protocol, validation, and UDP transport."""

from __future__ import annotations

import ipaddress
import json
import re
import select
import socket
import struct
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

DISCOVERY_PORT = 4001
LISTEN_PORT = 4002
CONTROL_PORT = 4003
MULTICAST_GROUP = "239.255.255.250"
GLOBAL_BROADCAST = "255.255.255.255"
DEFAULT_SCAN_TIMEOUT = 2.0
DEFAULT_COMMAND_TIMEOUT = 2.0
MAX_PACKET_SIZE = 4096
SKU_PATTERN = re.compile(r"H[0-9]{4}")
DEVICE_ID_PATTERN = re.compile(r"[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){3,7}")


class LanError(Exception):
    """A Govee LAN request or response failed validation."""


@dataclass(frozen=True)
class LanDevice:
    ip: str
    device_id: str
    sku: str


@dataclass(frozen=True)
class LanStatus:
    on: bool
    brightness: int
    color_r: int
    color_g: int
    color_b: int
    color_temp_kelvin: int


JsonObject = Mapping[str, Any]
Destination = tuple[str, int]
Response = tuple[bytes, str]


def _encode(command: str, data: JsonObject) -> bytes:
    return json.dumps(
        {"msg": {"cmd": command, "data": dict(data)}},
        separators=(",", ":"),
    ).encode("utf-8")


def build_scan_message() -> bytes:
    return _encode("scan", {"account_topic": "reserve"})


def _whole_number(value: Any, label: str, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise LanError(f"{label} must be a whole number")
    if value < minimum or value > maximum:
        raise LanError(f"{label} must be between {minimum} and {maximum}")
    return value


def build_control_message(instance: str, value: Any) -> bytes:
    if instance == "powerSwitch":
        checked = _whole_number(value, "Power", 0, 1)
        return _encode("turn", {"value": checked})
    if instance == "brightness":
        checked = _whole_number(value, "Brightness", 1, 100)
        return _encode("brightness", {"value": checked})
    if instance == "colorRgb":
        checked = _whole_number(value, "RGB color", 0, 0xFFFFFF)
        color = {
            "r": (checked >> 16) & 0xFF,
            "g": (checked >> 8) & 0xFF,
            "b": checked & 0xFF,
        }
        return _encode("colorwc", {"color": color, "colorTemInKelvin": 0})
    if instance == "colorTemperatureK":
        checked = _whole_number(value, "Temperature", 2000, 9000)
        return _encode(
            "colorwc",
            {"color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": checked},
        )
    raise LanError(f"LAN control does not support {instance}")


def build_status_message() -> bytes:
    return _encode("devStatus", {})


def _message(raw: bytes, expected_command: str) -> JsonObject:
    try:
        body = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LanError("Govee sent an invalid LAN response") from error
    if not isinstance(body, dict):
        raise LanError("Govee sent an invalid LAN response")
    message = body.get("msg")
    if not isinstance(message, dict) or message.get("cmd") != expected_command:
        raise LanError(f"Govee LAN response is not {expected_command}")
    data = message.get("data")
    if not isinstance(data, dict):
        raise LanError("Govee LAN response is missing data")
    return data


def _private_ipv4(raw: str) -> str:
    try:
        address = ipaddress.ip_address(raw)
    except ValueError as error:
        raise LanError("Govee LAN response contains an invalid IP address") from error
    unusable = (
        address.version != 4
        or address.is_global
        or address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_unspecified
        or address.packed[-1] in (0, 255)
    )
    if unusable:
        raise LanError("Govee LAN response contains a non-local IP address")
    return str(address)


def parse_scan_response(raw: bytes, source_ip: str) -> LanDevice:
    data = _message(raw, "scan")
    ip = _private_ipv4(source_ip)
    sku, device_id = data.get("sku"), data.get("device")
    if not isinstance(sku, str) or not SKU_PATTERN.fullmatch(sku):
        raise LanError("Govee LAN response contains an invalid model")
    if not isinstance(device_id, str) or not DEVICE_ID_PATTERN.fullmatch(device_id):
        raise LanError("Govee LAN response contains an invalid device ID")
    return LanDevice(ip=ip, device_id=device_id, sku=sku)


def parse_status_response(raw: bytes) -> LanStatus:
    data = _message(raw, "devStatus")
    color = data.get("color")
    if not isinstance(color, dict):
        raise LanError("Govee LAN status contains an invalid color")
    on_off = _whole_number(data.get("onOff"), "Power", 0, 1)
    brightness = _whole_number(data.get("brightness"), "Brightness", 0, 100)
    red = _whole_number(color.get("r"), "Red", 0, 255)
    green = _whole_number(color.get("g"), "Green", 0, 255)
    blue = _whole_number(color.get("b"), "Blue", 0, 255)
    kelvin = _whole_number(data.get("colorTemInKelvin"), "Temperature", 0, 9000)
    return LanStatus(on_off == 1, brightness, red, green, blue, kelvin)


def local_ip() -> str:
    probe = None
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("8.8.8.8", 80))
        return _private_ipv4(probe.getsockname()[0])
    except OSError as error:
        raise LanError("Could not determine the local network address") from error
    finally:
        if probe is not None:
            probe.close()


def scan_destinations(local_address: str) -> tuple[Destination, ...]:
    address = ipaddress.ip_address(_private_ipv4(local_address))
    network = ipaddress.ip_network(f"{address}/24", strict=False)
    special = (
        (MULTICAST_GROUP, DISCOVERY_PORT),
        (str(network.broadcast_address), DISCOVERY_PORT),
        (GLOBAL_BROADCAST, DISCOVERY_PORT),
    )
    hosts = tuple(
        (str(host), DISCOVERY_PORT) for host in network.hosts() if host != address
    )
    return special + hosts


class UdpTransport:
    """Send LAN packets and collect responses from Govee's fixed reply port."""

    def _listener(self) -> socket.socket:
        listener = None
        try:
            listener = socket.socket(
                socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP
            )
            listener.bind(("", LISTEN_PORT))
        except OSError as error:
            if listener is not None:
                listener.close()
            raise LanError("Could not listen for Govee LAN responses") from error
        listener.setblocking(False)
        return listener

    def _sender(self) -> socket.socket:
        sender = None
        try:
            sender = socket.socket(
                socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP
            )
            sender.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sender.setsockopt(
                socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, struct.pack("b", 2)
            )
            return sender
        except OSError as error:
            if sender is not None:
                sender.close()
            raise LanError("Could not create a Govee LAN sender") from error

    def send(self, payload: bytes, destinations: Sequence[Destination]) -> None:
        sender = self._sender()
        sent = 0
        last_error: OSError | None = None
        try:
            for destination in destinations:
                try:
                    sender.sendto(payload, destination)
                    sent += 1
                except OSError as error:
                    last_error = error
        finally:
            sender.close()
        if sent == 0:
            raise LanError("Could not send a Govee LAN request") from last_error

    def exchange(
        self, payload: bytes, destinations: Sequence[Destination], timeout: float
    ) -> tuple[Response, ...]:
        listener = self._listener()
        try:
            self.send(payload, destinations)
            return self._receive(listener, timeout)
        finally:
            listener.close()

    @staticmethod
    def _receive(listener: socket.socket, timeout: float) -> tuple[Response, ...]:
        responses: tuple[Response, ...] = ()
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return responses
            try:
                ready, _, _ = select.select((listener,), (), (), remaining)
            except OSError as error:
                raise LanError("Could not read Govee LAN responses") from error
            if not ready:
                return responses
            try:
                raw, address = listener.recvfrom(MAX_PACKET_SIZE)
            except OSError as error:
                raise LanError("Could not read a Govee LAN response") from error
            responses = responses + ((raw, address[0]),)


class LanClient:
    def __init__(
        self,
        *,
        transport: UdpTransport | None = None,
        local_ip_factory: Callable[[], str] = local_ip,
        scan_timeout: float = DEFAULT_SCAN_TIMEOUT,
        command_timeout: float = DEFAULT_COMMAND_TIMEOUT,
    ) -> None:
        self._transport = transport or UdpTransport()
        self._local_ip_factory = local_ip_factory
        self._scan_timeout = scan_timeout
        self._command_timeout = command_timeout

    def devices(self) -> tuple[LanDevice, ...]:
        local_address = self._local_ip_factory()
        responses = self._transport.exchange(
            build_scan_message(), scan_destinations(local_address), self._scan_timeout
        )
        devices: tuple[LanDevice, ...] = ()
        seen: frozenset[str] = frozenset()
        for raw, source_ip in responses:
            try:
                device = parse_scan_response(raw, source_ip)
            except LanError:
                continue
            identity = re.sub(r"[^0-9A-Za-z]", "", device.device_id).casefold()
            if identity not in seen:
                devices = devices + (device,)
                seen = seen | frozenset((identity,))
        return tuple(sorted(devices, key=lambda item: (item.sku, item.device_id)))

    def state(self, device: LanDevice) -> LanStatus:
        responses = self._transport.exchange(
            build_status_message(), ((device.ip, CONTROL_PORT),), self._command_timeout
        )
        for raw, source_ip in responses:
            if source_ip != device.ip:
                continue
            try:
                return parse_status_response(raw)
            except LanError:
                continue
        raise LanError(f"{device.sku} did not respond on the local network")

    def control(self, device: LanDevice, instance: str, value: Any) -> None:
        _private_ipv4(device.ip)
        self._transport.send(
            build_control_message(instance, value), ((device.ip, CONTROL_PORT),)
        )
