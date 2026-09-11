#!/usr/bin/python3
"""Secure CLI for controlling Govee lights through cloud and LAN APIs."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import pwd
import stat
import subprocess
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
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
    validate_capability_value,
)
from govee_hybrid import HybridDevice, lan_state_capabilities, merge_devices
from govee_lan import LanClient, LanError

ACCOUNT_HOME = Path(pwd.getpwuid(os.getuid()).pw_dir)
VAULT_HOME = ACCOUNT_HOME / ".vault"
VAULT_BIN = VAULT_HOME / "bin"
VAULT_SECRET = "GOVEE_API_KEY"
VAULT_BINARY = str(VAULT_BIN / "vault")
AGE_BINARY = str(VAULT_BIN / "age")
VAULT_PATH = f"{VAULT_BIN}:/usr/bin:/bin:/usr/sbin:/sbin"
OFFICIAL_API_BASE = "https://openapi.api.govee.com/router/api/v1"
LIGHT_TYPE = "devices.types.light"
LAN_ENABLED_VALUES = frozenset(("1", "true", "yes", "on"))
LAN_DISABLED_VALUES = frozenset(("0", "false", "no", "off"))


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
    commands.add_parser("setup", help="save and verify an API key in the vault")
    commands.add_parser("devices", help="list devices and supported controls")
    status = commands.add_parser("status")
    _add_targets(status)
    status.add_argument("--json", action="store_true", dest="json_output")
    for name in ("on", "off"):
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


def _validated_vault_binary() -> str:
    owner = os.getuid()
    for directory in (ACCOUNT_HOME, VAULT_HOME, VAULT_BIN):
        try:
            metadata = os.lstat(directory)
        except OSError as error:
            raise InputError("Local secrets vault is unavailable") from error
        safe_directory = (
            stat.S_ISDIR(metadata.st_mode)
            and metadata.st_uid in {0, owner}
            and not bool(metadata.st_mode & 0o022)
        )
        if not safe_directory:
            raise InputError("Local secrets vault has unsafe parent permissions")
    for executable in (VAULT_BINARY, AGE_BINARY):
        try:
            metadata = os.lstat(executable)
        except OSError as error:
            raise InputError("Local secrets vault is unavailable") from error
        valid = (
            stat.S_ISREG(metadata.st_mode)
            and metadata.st_uid == owner
            and bool(metadata.st_mode & stat.S_IXUSR)
            and not bool(metadata.st_mode & 0o022)
        )
        if not valid:
            raise InputError("Local secrets vault has unsafe ownership or permissions")
    return VAULT_BINARY


def _vault_environment() -> Mapping[str, str]:
    return {
        "HOME": str(ACCOUNT_HOME),
        "VAULT_HOME": str(VAULT_HOME),
        "PATH": VAULT_PATH,
        "LANG": "C.UTF-8",
    }


def load_vault_key() -> str | None:
    vault_binary = _validated_vault_binary()
    try:
        result = subprocess.run(
            [sys.executable, "-I", vault_binary, "get", VAULT_SECRET],
            capture_output=True,
            text=True,
            check=False,
            env=_vault_environment(),
        )
    except OSError as error:
        raise InputError("Could not run the local secrets vault") from error
    if result.returncode == 0:
        return result.stdout.strip() or None
    if "no such secret" in result.stderr:
        return None
    raise InputError("Could not read GOVEE_API_KEY from the local secrets vault")


def save_vault_key(api_key: str) -> None:
    vault_binary = _validated_vault_binary()
    try:
        result = subprocess.run(
            [sys.executable, "-I", vault_binary, "store", VAULT_SECRET, "--replace"],
            input=f"{api_key}\n",
            capture_output=True,
            text=True,
            check=False,
            env=_vault_environment(),
        )
    except OSError as error:
        raise InputError("Could not run the local secrets vault") from error
    if result.returncode != 0:
        raise InputError("Could not save GOVEE_API_KEY in the local secrets vault")


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


def _api_key(env: Mapping[str, str], secret_loader, api_base: str) -> str:
    explicit_key = env.get("GOVEE_API_KEY")
    if explicit_key:
        return explicit_key
    if api_base != OFFICIAL_API_BASE:
        raise InputError("GOVEE_API_KEY is required for a loopback test server")
    api_key = secret_loader()
    if not api_key:
        raise InputError(
            "No Govee API key found; run `govee setup` or store GOVEE_API_KEY "
            "in the local secrets vault"
        )
    return api_key


def _integer(raw: str, label: str) -> int:
    try:
        return int(raw)
    except ValueError as error:
        raise InputError(f"{label} must be a whole number") from error


def _capability_words(device: Device | HybridDevice) -> str:
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


def _print_devices(devices: Sequence[Device | HybridDevice], stdout: TextIO) -> None:
    ordered = sorted(devices, key=lambda item: (item.name.casefold(), item.device_id))
    for item in ordered:
        print(f"{item.name} [{item.sku}]  {_capability_words(item)}", file=stdout)


def _light_devices(
    devices: Sequence[Device | HybridDevice],
) -> tuple[Device | HybridDevice, ...]:
    return tuple(item for item in devices if item.device_type == LIGHT_TYPE)


def _select(
    args, devices: Sequence[Device | HybridDevice]
) -> tuple[Device | HybridDevice, ...]:
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
    values = _state_values(capabilities)
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


def _state_values(capabilities: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    return {str(item.get("instance")): _state_value(item) for item in capabilities}


def _state_record(
    device: Device | HybridDevice, capabilities: Sequence[Mapping[str, Any]]
) -> dict[str, Any]:
    values = _state_values(capabilities)
    online = values.get("online")
    power = values.get("powerSwitch")
    if type(online) is not bool:
        raise ApiError("State did not include a valid online state")
    if type(power) is not int or power not in (0, 1):
        raise ApiError("State did not include a valid power state")
    record: dict[str, Any] = {
        "id": device.device_id,
        "name": device.name,
        "online": online,
        "power": "on" if power == 1 else "off",
    }
    if isinstance(values.get("brightness"), (int, float)):
        record["brightness"] = values["brightness"]
    if isinstance(values.get("colorRgb"), int):
        record["color"] = f"#{values['colorRgb']:06x}"
    if isinstance(values.get("colorTemperatureK"), (int, float)):
        record["temperature"] = values["colorTemperatureK"]
    return record


def _warn(warnings: Sequence[str], stderr: TextIO) -> None:
    for warning in warnings:
        print(f"Warning: {warning}", file=stderr)


def _run_status(
    client, lan_client, selected, stdout: TextIO, stderr: TextIO, *, json_output=False
) -> int:
    failures = 0
    records = []
    for device in selected:
        try:
            if device.lan is not None:
                try:
                    capabilities = lan_state_capabilities(lan_client.state(device.lan))
                except LanError:
                    if device.cloud is None or client is None:
                        raise
                    capabilities = client.state(device.cloud)
                    print(f"Warning: {device.name}: LAN failed; used cloud", file=stderr)
            elif device.cloud is not None and client is not None:
                capabilities = client.state(device.cloud)
            else:
                raise ApiError("No available connection")
            if json_output:
                records.append(_state_record(device, capabilities))
            else:
                print(f"{device.name}: {_state_summary(capabilities)}", file=stdout)
        except (ApiError, LanError) as error:
            failures += 1
            print(f"{device.name}: {error}", file=stderr)
    if json_output:
        print(json.dumps(records, separators=(",", ":")), file=stdout)
    return 1 if failures else 0


def _run_control(client, lan_client, selected, instance, value, stdout, stderr) -> int:
    for device in selected:
        capability = next(
            (item for item in device.capabilities if item.instance == instance), None
        )
        if capability is None:
            raise InputError(f"{device.name} does not support {instance}")
        validate_capability_value(capability, value)
        if device.cloud is not None and device.lan is None:
            build_control_payload(
                device.cloud, instance, value, request_id="validation"
            )
    failures = 0
    for device in selected:
        try:
            if device.lan is not None:
                try:
                    lan_client.control(device.lan, instance, value)
                    result = "sent via LAN"
                except LanError:
                    if device.cloud is None or client is None:
                        raise
                    client.control(device.cloud, instance, value)
                    result = "ok via cloud"
                    print(f"Warning: {device.name}: LAN failed; used cloud", file=stderr)
            elif device.cloud is not None and client is not None:
                client.control(device.cloud, instance, value)
                result = "ok via cloud"
            else:
                raise ApiError("No available connection")
            print(f"{device.name}: {result}", file=stdout)
        except (ApiError, LanError) as error:
            failures += 1
            print(f"{device.name}: {error}", file=stderr)
    return 1 if failures else 0


def _setup(env, stdout, client_factory, key_saver) -> int:
    _validated_vault_binary()
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


def _lan_enabled(env: Mapping[str, str]) -> bool:
    value = env.get("GOVEE_LAN_ENABLED", "true").strip().casefold()
    if value in LAN_ENABLED_VALUES:
        return True
    if value in LAN_DISABLED_VALUES:
        return False
    raise InputError("GOVEE_LAN_ENABLED must be true or false")


def _discover_lan(env, lan_client_factory) -> tuple[Any, tuple, tuple[str, ...]]:
    if not _lan_enabled(env):
        return None, (), ()
    client = lan_client_factory()
    try:
        return client, client.devices(), ()
    except LanError as error:
        return client, (), (f"LAN discovery failed: {error}",)


def _discover_cloud(env, secret_loader, client_factory, have_lan):
    api_base = _api_base(env)
    try:
        api_key = _api_key(env, secret_loader, api_base)
    except InputError as error:
        if have_lan and api_base == OFFICIAL_API_BASE:
            return None, (), (f"Cloud discovery unavailable: {error}",)
        raise
    client = client_factory(api_key, base_url=api_base)
    try:
        devices, warnings = client.devices()
        return client, devices, warnings
    except ApiError as error:
        if have_lan:
            return client, (), (f"Cloud discovery failed: {error}",)
        raise


def _run(
    args,
    env,
    stdout,
    stderr,
    client_factory,
    lan_client_factory,
    secret_loader,
    key_saver,
) -> int:
    if args.command == "setup":
        return _setup(env, stdout, client_factory, key_saver)
    lan_client, lan_devices, lan_warnings = _discover_lan(env, lan_client_factory)
    client, cloud_devices, cloud_warnings = _discover_cloud(
        env, secret_loader, client_factory, bool(lan_devices)
    )
    devices = merge_devices(cloud_devices, lan_devices)
    _warn(lan_warnings + cloud_warnings, stderr)
    if not devices:
        raise InputError("No Govee lights were found through cloud or LAN")
    if args.command == "devices":
        _print_devices(devices, stdout)
        return 0
    selected = _select(args, devices)
    if args.command == "status":
        return _run_status(
            client,
            lan_client,
            selected,
            stdout,
            stderr,
            json_output=args.json_output,
        )
    instance, value = _command_value(args)
    return _run_control(client, lan_client, selected, instance, value, stdout, stderr)


def main(
    argv: Sequence[str] | None = None,
    *,
    env: Mapping[str, str] | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
    client_factory=GoveeClient,
    lan_client_factory=LanClient,
    secret_loader=None,
    key_saver=save_vault_key,
) -> int:
    output, errors = stdout or sys.stdout, stderr or sys.stderr
    effective_env = os.environ if env is None else env
    loader = secret_loader or load_vault_key
    try:
        args = build_parser().parse_args(argv)
        return _run(
            args,
            effective_env,
            output,
            errors,
            client_factory,
            lan_client_factory,
            loader,
            key_saver,
        )
    except InputError as error:
        print(f"Error: {error}", file=errors)
        return 2
    except ApiError as error:
        print(f"Error: {error}", file=errors)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
