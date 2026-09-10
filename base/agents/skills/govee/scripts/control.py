#!/usr/bin/env python3
"""Secure CLI for controlling Govee lights through the official cloud API."""

from __future__ import annotations

import argparse
import getpass
import os
import sys
from collections.abc import Mapping, Sequence
from typing import Any, TextIO
from urllib.parse import urlparse

from govee_api import (
    ApiError,
    Device,
    GoveeClient,
    InputError,
    build_control_payload,
    pack_rgb,
    parse_color,
    select_devices,
)
from keychain import KeychainError, load_password, save_password

KEYCHAIN_SERVICE = "codex-govee"
OFFICIAL_API_BASE = "https://openapi.api.govee.com/router/api/v1"
LIGHT_TYPE = "devices.types.light"


class ArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise InputError(message)


def _add_targets(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--device", action="append", default=[], help="Govee name or ID"
    )
    parser.add_argument("--all", action="store_true", dest="all_devices")


def build_parser() -> argparse.ArgumentParser:
    parser = ArgumentParser(prog="govee", description="Control Govee lights")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("setup", help="save and verify an API key in Keychain")
    commands.add_parser("devices", help="list devices and supported controls")
    for name in ("status", "on", "off"):
        _add_targets(commands.add_parser(name))
    brightness = commands.add_parser("brightness")
    brightness.add_argument("value")
    _add_targets(brightness)
    color = commands.add_parser("color")
    color.add_argument("value")
    _add_targets(color)
    temperature = commands.add_parser("temperature")
    temperature.add_argument("kelvin")
    _add_targets(temperature)
    return parser


def _keychain_account() -> str:
    return getpass.getuser()


def load_keychain_key() -> str | None:
    if sys.platform != "darwin":
        return None
    try:
        return load_password(KEYCHAIN_SERVICE, _keychain_account())
    except KeychainError as error:
        raise InputError(
            "Could not read the Govee API key from macOS Keychain"
        ) from error


def save_keychain_key(api_key: str) -> None:
    if sys.platform != "darwin":
        raise InputError(
            "macOS Keychain is unavailable; provide GOVEE_API_KEY through a secret manager"
        )
    try:
        save_password(KEYCHAIN_SERVICE, _keychain_account(), api_key)
    except (KeychainError, ValueError) as error:
        raise InputError(
            "Could not save the Govee API key in macOS Keychain"
        ) from error


def _api_base(env: Mapping[str, str]) -> str:
    base = env.get("GOVEE_API_BASE", OFFICIAL_API_BASE).rstrip("/")
    parsed = urlparse(base)
    official = base == OFFICIAL_API_BASE
    loopback = parsed.scheme == "http" and parsed.hostname in {
        "127.0.0.1",
        "localhost",
        "::1",
    }
    if not official and not loopback:
        raise InputError(
            "GOVEE_API_BASE must be the official API or a loopback test server"
        )
    return base


def _api_key(env: Mapping[str, str], keychain_loader, api_base: str) -> str:
    explicit_key = env.get("GOVEE_API_KEY")
    if explicit_key:
        return explicit_key
    if api_base != OFFICIAL_API_BASE:
        raise InputError("GOVEE_API_KEY is required for a loopback test server")
    api_key = keychain_loader()
    if not api_key:
        raise InputError(
            "No Govee API key found; run `govee setup` on macOS or provide "
            "GOVEE_API_KEY through a secret manager"
        )
    return api_key


def _integer(raw: str, label: str) -> int:
    try:
        return int(raw)
    except ValueError as error:
        raise InputError(f"{label} must be a whole number") from error


def _capability_words(device: Device) -> str:
    names = {item.instance for item in device.capabilities}
    supported = (
        ("power", "powerSwitch"),
        ("brightness", "brightness"),
        ("color", "colorRgb"),
        ("temperature", "colorTemperatureK"),
    )
    return (
        " ".join(label for label, instance in supported if instance in names) or "none"
    )


def _print_devices(devices: Sequence[Device], stdout: TextIO) -> None:
    ordered = sorted(devices, key=lambda item: (item.name.casefold(), item.device_id))
    for item in ordered:
        print(f"{item.name} [{item.sku}]  {_capability_words(item)}", file=stdout)


def _light_devices(devices: Sequence[Device]) -> tuple[Device, ...]:
    return tuple(item for item in devices if item.device_type == LIGHT_TYPE)


def _select(args, devices: Sequence[Device]) -> tuple[Device, ...]:
    candidates = _light_devices(devices)
    if not candidates:
        raise InputError("No Govee lights were found")
    return select_devices(candidates, tuple(args.device), all_devices=args.all_devices)


def _command_value(args) -> tuple[str, Any]:
    if args.command == "on":
        return "powerSwitch", 1
    if args.command == "off":
        return "powerSwitch", 0
    if args.command == "brightness":
        return "brightness", _integer(args.value, "Brightness")
    if args.command == "color":
        return "colorRgb", pack_rgb(parse_color(args.value))
    if args.command == "temperature":
        return "colorTemperatureK", _integer(args.kelvin, "Temperature")
    raise InputError(f"Unsupported command {args.command!r}")


def _state_value(capability: Mapping[str, Any]) -> Any:
    state = capability.get("state")
    return state.get("value") if isinstance(state, Mapping) else None


def _state_summary(capabilities: Sequence[Mapping[str, Any]]) -> str:
    values = {item.get("instance"): _state_value(item) for item in capabilities}
    parts: tuple[str, ...] = ()
    if "online" in values:
        parts = parts + (f"online={'yes' if values['online'] else 'no'}",)
    if "powerSwitch" in values:
        parts = parts + (f"power={'on' if values['powerSwitch'] == 1 else 'off'}",)
    if isinstance(values.get("brightness"), (int, float)):
        parts = parts + (f"brightness={values['brightness']}%",)
    if isinstance(values.get("colorRgb"), int):
        parts = parts + (f"color=#{values['colorRgb']:06x}",)
    if isinstance(values.get("colorTemperatureK"), (int, float)):
        parts = parts + (f"temperature={values['colorTemperatureK']}K",)
    return " ".join(parts) or "state unavailable"


def _warn(warnings: Sequence[str], stderr: TextIO) -> None:
    for warning in warnings:
        print(f"Warning: {warning}", file=stderr)


def _run_status(
    client, selected: Sequence[Device], stdout: TextIO, stderr: TextIO
) -> int:
    failures = 0
    for device in selected:
        try:
            print(f"{device.name}: {_state_summary(client.state(device))}", file=stdout)
        except ApiError as error:
            failures += 1
            print(f"{device.name}: {error}", file=stderr)
    return 1 if failures else 0


def _run_control(client, selected, instance, value, stdout, stderr) -> int:
    for device in selected:
        build_control_payload(device, instance, value, request_id="validation")
    failures = 0
    for device in selected:
        try:
            client.control(device, instance, value)
            print(f"{device.name}: ok", file=stdout)
        except ApiError as error:
            failures += 1
            print(f"{device.name}: {error}", file=stderr)
    return 1 if failures else 0


def _setup(env, stdout, client_factory, key_saver) -> int:
    if sys.platform != "darwin":
        raise InputError(
            "macOS Keychain is unavailable; provide GOVEE_API_KEY through a secret manager"
        )
    api_base = _api_base(env)
    if api_base != OFFICIAL_API_BASE:
        raise InputError("Govee setup only connects to the official API")
    api_key = getpass.getpass("Govee API key: ").strip()
    if not api_key:
        raise InputError("Govee API key cannot be empty")
    client = client_factory(api_key, base_url=api_base)
    devices, _warnings = client.devices()
    key_saver(api_key)
    print(f"Govee API key saved; found {len(devices)} device(s)", file=stdout)
    return 0


def _run(args, env, stdout, stderr, client_factory, keychain_loader, key_saver) -> int:
    if args.command == "setup":
        return _setup(env, stdout, client_factory, key_saver)
    api_base = _api_base(env)
    client = client_factory(
        _api_key(env, keychain_loader, api_base),
        base_url=api_base,
    )
    devices, warnings = client.devices()
    _warn(warnings, stderr)
    if args.command == "devices":
        _print_devices(devices, stdout)
        return 0
    selected = _select(args, devices)
    if args.command == "status":
        return _run_status(client, selected, stdout, stderr)
    instance, value = _command_value(args)
    return _run_control(client, selected, instance, value, stdout, stderr)


def main(
    argv: Sequence[str] | None = None,
    *,
    env: Mapping[str, str] | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    client_factory=GoveeClient,
    keychain_loader=None,
    key_saver=save_keychain_key,
) -> int:
    output, errors = stdout or sys.stdout, stderr or sys.stderr
    effective_env = os.environ if env is None else env
    loader = keychain_loader or load_keychain_key
    try:
        args = build_parser().parse_args(argv)
        return _run(
            args, effective_env, output, errors, client_factory, loader, key_saver
        )
    except InputError as error:
        print(f"Error: {error}", file=errors)
        return 2
    except ApiError as error:
        print(f"Error: {error}", file=errors)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
