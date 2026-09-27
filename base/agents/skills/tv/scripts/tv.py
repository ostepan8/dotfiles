#!/usr/bin/env python3
"""tv — drive Owen's Roku TVs from a Claude session: wake, keys, apps, text,
where-to-watch, and a camera snapshot to check what happened.

    tv.py status [tv]                 power, open app, player state
    tv.py on [tv] | off [tv]          wakes an off TV (Wake-on-LAN) first
    tv.py key [--tv T] KEY [KEY ...]  e.g. key Left Up Select   (--gap secs)
    tv.py type [--tv T] TEXT          types into the focused search box
    tv.py apps [tv]                   installed apps and inputs, with ids
    tv.py launch [--tv T] APP         APP is a name ("hbo max") or an id ("61322")
                 [--content-id ID --media-type series|movie|episode]
    tv.py where TITLE                 which services stream it, marked have / unknown
    tv.py snap [--room] [out.jpg]     camera frame of the 75" (Studio only)

A TV is picked by serial, name or alias from ~/.config/praxis/tvs.json; the
default TV is used when none is given. The file also remembers each TV's MAC
(what wakes it) and last address; a TV that moved address is found again by
sweeping the subnet, and the file is updated. Standard library only.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

CONFIG = Path(os.environ.get("TV_CONFIG", "~/.config/praxis/tvs.json")).expanduser()
SERVICES = Path(os.environ.get("TV_SERVICES", "~/.config/praxis/services.json")).expanduser()
TVCAM = Path(os.environ.get("TVCAM", "~/projects/praxis/scripts/tvcam")).expanduser()
VAULT = Path("~/.vault/bin/vault").expanduser()

ECP_TIMEOUT = 2.5
WAKE_BUDGET = 45.0
REWAKE_EVERY = 8.0
KEY_GAP = 0.35
TYPE_GAP = 0.1


def die(msg: str) -> None:
    print(f"tv: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------- config ----------

def load_config() -> dict:
    if not CONFIG.exists():
        die(f"no TV list at {CONFIG}; see the tv skill's SKILL.md for its shape")
    return json.loads(CONFIG.read_text())


def save_config(cfg: dict) -> None:
    tmp = CONFIG.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, indent=2) + "\n")
    tmp.replace(CONFIG)


def pick(cfg: dict, name: str | None) -> tuple[str, dict]:
    tvs = cfg["tvs"]
    if not name:
        serial = cfg.get("default") or next(iter(tvs))
        return serial, tvs[serial]
    wanted = name.lower().strip()
    for serial, tv in tvs.items():
        names = [serial.lower(), tv.get("name", "").lower(), *[a.lower() for a in tv.get("aliases", [])]]
        if wanted in names or any(wanted in n for n in names if n):
            return serial, tv
    die(f"no TV called {name!r}; known: " + ", ".join(t.get("name", s) for s, t in tvs.items()))
    raise AssertionError


# ---------- ECP ----------

def ecp(addr: str, method: str, path: str, timeout: float = ECP_TIMEOUT) -> bytes:
    req = urllib.request.Request(f"http://{addr}{path}", method=method, data=b"" if method == "POST" else None)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def info(addr: str, timeout: float = ECP_TIMEOUT) -> dict | None:
    try:
        root = ET.fromstring(ecp(addr, "GET", "/query/device-info", timeout))
    except (OSError, ET.ParseError, urllib.error.URLError):
        return None
    return {child.tag: (child.text or "").strip() for child in root}


def sweep(subnet: str, serial: str) -> str | None:
    """Find a TV by serial anywhere on the subnet (it may have a new lease)."""
    hosts = [f"{ip}:8060" for ip in ipaddress.ip_network(subnet).hosts()]
    with concurrent.futures.ThreadPoolExecutor(128) as pool:
        for addr, found in zip(hosts, pool.map(lambda a: info(a, 1.0), hosts)):
            if found and found.get("serial-number") == serial:
                return addr
    return None


def resolve(cfg: dict, serial: str, tv: dict, look_hard: bool = True) -> tuple[str | None, dict]:
    """The TV's current address and device-info, or (None, None) if it is off the network."""
    found = info(tv["addr"]) if tv.get("addr") else None
    if found and found.get("serial-number") == serial:
        return tv["addr"], found
    if not look_hard:
        return None, {}
    addr = sweep(cfg.get("subnet", "10.0.0.0/24"), serial)
    if not addr:
        return None, {}
    tv["addr"] = addr
    save_config(cfg)
    return addr, info(addr) or {}


def magic_packet(mac: str) -> None:
    raw = bytes.fromhex(mac.replace(":", ""))
    packet = b"\xff" * 6 + raw * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for dst in ("255.255.255.255", "10.0.0.255"):
            for port in (9, 7):
                try:
                    s.sendto(packet, (dst, port))
                except OSError:
                    pass


def ensure_awake(cfg: dict, serial: str, tv: dict) -> tuple[str, dict]:
    """Wake an off TV and wait until it answers. Returns (addr, device-info)."""
    addr, found = resolve(cfg, serial, tv, look_hard=False)
    if addr:
        return addr, found
    if not tv.get("mac"):
        die(f"{tv.get('name', serial)} is not answering and has no MAC to wake it by")
    start, last_wake, swept = time.monotonic(), 0.0, False
    while time.monotonic() - start < WAKE_BUDGET:
        if time.monotonic() - last_wake >= REWAKE_EVERY:
            magic_packet(tv["mac"])
            last_wake = time.monotonic()
            print(f"tv: wake packet sent to {tv.get('name', serial)}", file=sys.stderr)
        time.sleep(1)
        # after ~10s, look everywhere once: it may have come back on a new lease
        look_hard = not swept and time.monotonic() - start > 10
        swept = swept or look_hard
        addr, found = resolve(cfg, serial, tv, look_hard=look_hard)
        if addr:
            return addr, found
    die(f"{tv.get('name', serial)} did not come back after {WAKE_BUDGET:.0f}s: unplugged, or wake-on-LAN is off")
    raise AssertionError


def press(addr: str, key: str) -> None:
    ecp(addr, "POST", "/keypress/" + urllib.parse.quote(key, safe="_"))


def power_on(addr: str, found: dict) -> None:
    if found.get("power-mode") != "PowerOn":
        press(addr, "PowerOn")
        time.sleep(1.5)


# ---------- commands ----------

def cmd_status(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr, found = resolve(cfg, serial, tv)
    if not addr:
        print(f"{tv.get('name', serial)}: off the network (asleep; `on` wakes it)")
        return
    app = player = ""
    try:
        el = ET.fromstring(ecp(addr, "GET", "/query/active-app")).find("app")
        app = f"{(el.text or '').strip()} ({el.get('id')})" if el is not None else ""
        pl = ET.fromstring(ecp(addr, "GET", "/query/media-player"))
        player = pl.get("state", "")
    except (OSError, ET.ParseError):
        pass
    print(f"{tv.get('name', serial)} at {addr}: power={found.get('power-mode')} app={app} player={player}")


def cmd_on(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr, found = ensure_awake(cfg, serial, tv)
    power_on(addr, found)
    print(f"{tv.get('name', serial)}: on")


def cmd_off(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr, found = resolve(cfg, serial, tv, look_hard=False)
    if not addr or found.get("power-mode") != "PowerOn":
        print(f"{tv.get('name', serial)}: already off")
        return
    press(addr, "PowerOff")
    print(f"{tv.get('name', serial)}: off")


def cmd_key(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr = ensure_awake(cfg, serial, tv)[0]
    for i, key in enumerate(a.keys):
        if i:
            time.sleep(a.gap)
        press(addr, key)
    print("sent " + " ".join(a.keys))


def cmd_type(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr = ensure_awake(cfg, serial, tv)[0]
    for ch in a.text:
        press(addr, "Lit_" + urllib.parse.quote(ch, safe=""))
        time.sleep(TYPE_GAP)
    print(f"typed {a.text!r}")


def list_apps(addr: str) -> list[tuple[str, str, str]]:
    root = ET.fromstring(ecp(addr, "GET", "/query/apps"))
    return [(el.get("id", ""), (el.text or "").strip(), el.get("type", "")) for el in root.findall("app")]


def cmd_apps(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr, _ = ensure_awake(cfg, serial, tv)
    for app_id, name, kind in list_apps(addr):
        print(f"{app_id:>16}  {name}{'  [input]' if kind == 'tvin' else ''}")


def norm(s: str) -> str:
    s = s.lower().replace("+", " plus")
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def cmd_launch(cfg: dict, a: argparse.Namespace) -> None:
    serial, tv = pick(cfg, a.tv)
    addr, found = ensure_awake(cfg, serial, tv)
    power_on(addr, found)
    app_id = a.app
    if not re.fullmatch(r"[A-Za-z0-9._-]+", app_id) or not any(c.isdigit() for c in app_id):
        wanted = norm(a.app)
        matches = [(i, n) for i, n, _ in list_apps(addr) if wanted == norm(n) or wanted in norm(n)]
        if not matches:
            die(f"no app matching {a.app!r} on {tv.get('name', serial)}; try `apps`")
        app_id = min(matches, key=lambda m: len(m[1]))[0]
    q = {}
    if a.content_id:
        q = {"contentId": a.content_id, "mediaType": a.media_type or "series"}
    ecp(addr, "POST", f"/launch/{app_id}" + ("?" + urllib.parse.urlencode(q) if q else ""), timeout=6)
    print(f"launched {app_id}" + (f" with content {a.content_id}" if q else ""))


def vault_get(name: str) -> str:
    out = subprocess.run([str(VAULT), "get", name], capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        die(f"{name} is not in the vault")
    return out.stdout.strip()


SERVICE_ALIASES = {
    "hbo max": "max", "hbo max amazon channel": "max", "amazon prime video": "prime_video",
    "amazon prime video with ads": "prime_video", "paramount plus": "paramount_plus",
    "paramount plus premium": "paramount_plus", "paramount plus essential": "paramount_plus",
    "peacock premium": "peacock", "peacock premium plus": "peacock", "espn plus": "espn",
    "netflix standard with ads": "netflix", "netflix basic with ads": "netflix",
    "disney plus": "disney_plus", "apple tv plus": "apple_tv_plus",
}


def service_id(name: str) -> str:
    n = norm(name)
    return SERVICE_ALIASES.get(n, n.replace(" ", "_"))


def cmd_where(cfg: dict, a: argparse.Namespace) -> None:
    key = vault_get("TMDB_API_KEY")
    have = {k: v for k, v in json.loads(SERVICES.read_text()).items() if not k.startswith("_")} if SERVICES.exists() else {}

    def get(path: str, **q: str) -> dict:
        q["api_key"] = key
        with urllib.request.urlopen("https://api.themoviedb.org/3" + path + "?" + urllib.parse.urlencode(q), timeout=10) as r:
            return json.load(r)

    results = [r for r in get("/search/multi", query=a.title)["results"] if r.get("media_type") in ("movie", "tv")][:3]
    if not results:
        die(f"nothing called {a.title!r} on TMDB")
    for r in results:
        title = r.get("title") or r.get("name")
        year = (r.get("release_date") or r.get("first_air_date") or "")[:4]
        us = get(f"/{r['media_type']}/{r['id']}/watch/providers")["results"].get("US", {})
        stream = []
        for p in us.get("flatrate", []) + us.get("free", []) + us.get("ads", []):
            sid = service_id(p["provider_name"])
            if sid not in [s for s, _ in stream]:
                known = have.get(sid)
                stream.append((sid, "UNKNOWN-ask Owen" if known is None else ("have" if known else "dont_have")))
        rent = sorted({service_id(p["provider_name"]) for p in us.get("rent", [])})
        print(f"{title} ({year}, {r['media_type']}): stream " + (", ".join(f"{s}[{st}]" for s, st in stream) or "none")
              + (f"; rent {', '.join(rent)}" if rent else ""))


def cmd_snap(cfg: dict, a: argparse.Namespace) -> None:
    if not TVCAM.exists():
        die(f"no camera script at {TVCAM}; the camera is on the Mac Studio only")
    args = [str(TVCAM)] + (["--room"] if a.room else []) + ([a.out] if a.out else [])
    out = subprocess.run(args, capture_output=True, text=True)
    if out.returncode != 0:
        die(out.stderr.strip() or "camera failed")
    print(out.stdout.strip())


def main() -> None:
    p = argparse.ArgumentParser(prog="tv", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("status", cmd_status), ("on", cmd_on), ("off", cmd_off), ("apps", cmd_apps)):
        s = sub.add_parser(name)
        s.add_argument("tv", nargs="?")
        s.set_defaults(fn=fn)
    s = sub.add_parser("key")
    s.add_argument("--tv")
    s.add_argument("--gap", type=float, default=KEY_GAP)
    s.add_argument("keys", nargs="+")
    s.set_defaults(fn=cmd_key)
    s = sub.add_parser("type")
    s.add_argument("--tv")
    s.add_argument("text")
    s.set_defaults(fn=cmd_type)
    s = sub.add_parser("launch")
    s.add_argument("--tv")
    s.add_argument("app")
    s.add_argument("--content-id")
    s.add_argument("--media-type")
    s.set_defaults(fn=cmd_launch)
    s = sub.add_parser("where")
    s.add_argument("title")
    s.set_defaults(fn=cmd_where)
    s = sub.add_parser("snap")
    s.add_argument("--room", action="store_true")
    s.add_argument("out", nargs="?")
    s.set_defaults(fn=cmd_snap)
    a = p.parse_args()
    try:
        a.fn(load_config(), a)
    except urllib.error.URLError as e:
        die(f"the TV did not answer: {e.reason}")


if __name__ == "__main__":
    main()
