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
import time
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any, TextIO
from urllib.parse import urlparse

from govee_api import (
    JsonValue,
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
from govee_lan import LanClient, LanDevice, LanError

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


LAN_CACHE_RELATIVE = Path(".cache") / "govee" / "lan-devices.json"
LAN_CACHE_TTL_DEFAULT = 600.0


def _lan_cache_path(env: Mapping[str, str]) -> Path | None:
    """Where the remembered LAN addresses live, or None for no cache.

    Derived strictly from the CALLER'S environment. env is already the source
    of truth for the API key and whether LAN is enabled; reaching past it to
    the process account for this one value was wrong, and it showed — unit
    tests that pass env={} read the real cache and picked up the actual lamps
    on this network instead of their fakes.

    No HOME and no explicit path means the caller has given us nowhere to
    cache, so we do not. Slower, never surprising.
    """
    override = env.get("GOVEE_LAN_CACHE_PATH", "").strip()
    if override:
        return Path(override)
    home = env.get("HOME", "").strip()
    if not home:
        return None
    return Path(home) / LAN_CACHE_RELATIVE


def _lan_cache_ttl(env: Mapping[str, str]) -> float:
    """Seconds a remembered LAN address list stays usable. 0 disables it."""
    raw = env.get("GOVEE_LAN_CACHE_TTL", "").strip()
    if not raw:
        return LAN_CACHE_TTL_DEFAULT
    try:
        value = float(raw)
    except ValueError:
        raise InputError("GOVEE_LAN_CACHE_TTL must be a number of seconds")
    return max(value, 0.0)


def _read_lan_cache(path: Path | None, ttl: float) -> tuple[LanDevice, ...] | None:
    if path is None or ttl <= 0:
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if time.time() - float(raw["at"]) > ttl:
            return None
        return tuple(
            LanDevice(ip=str(d["ip"]), device_id=str(d["device_id"]), sku=str(d["sku"]))
            for d in raw["devices"]
        )
    except (OSError, ValueError, KeyError, TypeError):
        return None


def _write_lan_cache(path: Path | None, devices: Sequence[LanDevice]) -> None:
    if path is None:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        payload = {
            "at": time.time(),
            "devices": [
                {"ip": d.ip, "device_id": d.device_id, "sku": d.sku} for d in devices
            ],
        }
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(payload), encoding="utf-8")
        temporary.chmod(0o600)
        temporary.replace(path)
    except OSError:
        pass  # a cache that cannot be written is not an error, just a slow path


def _discover_lan(env, lan_client_factory) -> tuple[Any, tuple, tuple[str, ...]]:
    """Find the lamps on the LAN, remembering where they were last seen.

    Discovery is a multicast scan that MUST wait out its whole window, because
    nothing says how many lamps should answer — a fixed ~2s on every invocation,
    which dominated every status read and every control. Addresses are stable
    between DHCP leases, so they are cached and the scan is skipped. A caller
    that then cannot reach a remembered address falls back to the cloud exactly
    as it already did, and the next scan refreshes the file.
    """
    if not _lan_enabled(env):
        return None, (), ()
    client = lan_client_factory()
    ttl = _lan_cache_ttl(env)
    cache_path = _lan_cache_path(env)
    cached = _read_lan_cache(cache_path, ttl)
    if cached:
        return client, cached, ()
    try:
        devices = client.devices()
    except LanError as error:
        return client, (), (f"LAN discovery failed: {error}",)
    if devices:
        _write_lan_cache(cache_path, devices)
    return client, devices, ()


CLOUD_CACHE_RELATIVE = Path(".cache") / "govee" / "cloud-devices.json"
CLOUD_CACHE_TTL_DEFAULT = 86400.0


def _cloud_cache_path(env: Mapping[str, str]) -> Path | None:
    override = env.get("GOVEE_CLOUD_CACHE_PATH", "").strip()
    if override:
        return Path(override)
    home = env.get("HOME", "").strip()
    if not home:
        return None
    return Path(home) / CLOUD_CACHE_RELATIVE


def _cloud_cache_ttl(env: Mapping[str, str]) -> float:
    """Seconds the device LIST stays usable. 0 disables it."""
    raw = env.get("GOVEE_CLOUD_CACHE_TTL", "").strip()
    if not raw:
        return CLOUD_CACHE_TTL_DEFAULT
    try:
        value = float(raw)
    except ValueError:
        raise InputError("GOVEE_CLOUD_CACHE_TTL must be a number of seconds")
    return max(value, 0.0)


def _read_cloud_cache(path: Path | None, ttl: float, api_base: str) -> JsonValue | None:
    """The cached device list, if it is fresh AND from this same API base.

    Keying on api_base is not paranoia: the end-to-end test points the CLI at a
    local fake server while inheriting the real HOME, and without this it read
    the cache written from the live Govee account and went looking for the real
    lamps. A cache from one server must never answer for another.
    """
    if path is None or ttl <= 0:
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if raw.get("api_base") != api_base:
            return None
        if time.time() - float(raw["at"]) > ttl:
            return None
        return raw["body"]
    except (OSError, ValueError, KeyError, TypeError):
        return None


def _write_cloud_cache(path: Path | None, body: JsonValue, api_base: str) -> None:
    if path is None:
        return
    try:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({"at": time.time(), "api_base": api_base, "body": body}),
            encoding="utf-8",
        )
        temporary.chmod(0o600)
        temporary.replace(path)
    except OSError:
        pass


def _discover_cloud(env, secret_loader, client_factory, have_lan):
    """Get the device list, from cache when possible.

    GET /user/devices is metadata — names, SKUs, capabilities — that changes
    only when a lamp is added or removed, but it was fetched on EVERY status
    read and every control. Govee's documented allowance is 10,000 requests a
    day, so anything that reads often (a phone page, a poller) burns quota on a
    list that has not changed, and gets rate-limited exactly when it matters.
    The raw response body is cached and re-parsed, so nothing is lost.

    A lamp added or renamed appears when the cache expires, or immediately with
    GOVEE_CLOUD_CACHE_TTL=0.
    """
    api_base = _api_base(env)
    try:
        api_key = _api_key(env, secret_loader, api_base)
    except InputError as error:
        if have_lan and api_base == OFFICIAL_API_BASE:
            return None, (), (f"Cloud discovery unavailable: {error}",)
        raise
    client = client_factory(api_key, base_url=api_base)
    cache_path = _cloud_cache_path(env)
    ttl = _cloud_cache_ttl(env)
    # Prefer a cached body, but only when the client can parse one back. A test
    # double or an alternative client need only implement devices(); the cache
    # is transparent to them rather than something every caller must support.
    parse = getattr(client, "parse_device_response", None)
    cached = _read_cloud_cache(cache_path, ttl, api_base) if parse else None
    if cached is not None:
        try:
            devices, warnings = parse(cached)
            return client, devices, warnings
        except ApiError:
            pass  # a cache we cannot parse is simply not a cache
    try:
        body_of = getattr(client, "devices_body", None)
        if body_of and parse:
            body = body_of()
            devices, warnings = parse(body)
            _write_cloud_cache(cache_path, body, api_base)
        else:
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
