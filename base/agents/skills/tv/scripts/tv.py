#!/usr/bin/env python3
"""tv — drive Owen's TVs through praxis, from any Claude session.

    tv.py status [tv]                 power, open app, player state
    tv.py devices                     every TV and lamp praxis knows, with health
    tv.py on [tv] | off [tv]          `on` wakes an off TV (Wake-on-LAN) first
    tv.py key [--tv T] KEY [KEY ...]  e.g. key Left Up Select   (--gap secs)
    tv.py type [--tv T] TEXT          types into the focused search box
    tv.py apps [tv]                   installed apps and inputs, with ids
    tv.py launch [--tv T] APP         APP is a name ("hbo max") or an id ("61322")
                 [--content-id ID --media-type series|movie|episode]
    tv.py where TITLE                 which services stream it, marked have / dont_have / unknown
    tv.py have SERVICE yes|no         record Owen's answer about a service
    tv.py snap [--room] [out.jpg]     camera frame of the TV the camera sees

praxis is the one service that talks to the TVs; it holds the network and
camera permissions, wakes TVs, and retries. This script only calls its
API, so it works the same from a terminal, from atlas's agent, from workq
under launchd, or from another machine over the tailnet.

Config (machine-local, never in dotfiles):
    ~/.config/praxis/api-key   a praxis API key (scopes tv,read,lights), 0600
    PRAXIS_URL                 default http://127.0.0.1:8097 (the Studio);
                               elsewhere, the Studio's tailnet name, port 8097
    ~/.config/praxis/tvs.json  optional: {"default": serial, "tvs": {serial: {"aliases": [...]}}}
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

URL = os.environ.get("PRAXIS_URL", "http://127.0.0.1:8097").rstrip("/")
KEY_FILE = Path(os.environ.get("PRAXIS_KEY_FILE", "~/.config/praxis/api-key")).expanduser()
TVS = Path(os.environ.get("TV_CONFIG", "~/.config/praxis/tvs.json")).expanduser()
KEY_GAP = 0.35
# A command may wake a TV that is off: praxis allows it ~60s.
COMMAND_TIMEOUT = 75


def die(msg: str) -> None:
    print(f"tv: {msg}", file=sys.stderr)
    sys.exit(1)


def key() -> str:
    try:
        return KEY_FILE.read_text().strip()
    except OSError:
        die(f"no praxis API key at {KEY_FILE} (praxisd keys create <name> tv,read,lights)")
        raise


def call(method: str, path: str, body: dict | None = None, timeout: float = 20, raw: bool = False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + key())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = resp.read()
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read()).get("error") or e.reason
        except (ValueError, AttributeError):
            msg = e.reason
        die(f"praxis said {e.code}: {msg}")
        raise
    except (urllib.error.URLError, TimeoutError) as e:
        die(f"could not reach praxis at {URL}: {getattr(e, 'reason', e)}")
        raise
    if raw:
        return payload
    return json.loads(payload).get("data")


def tvs() -> list[dict]:
    return [d for d in call("GET", "/devices") or [] if d.get("kind") == "tv"]


def local_config() -> dict:
    try:
        return json.loads(TVS.read_text())
    except (OSError, ValueError):
        return {}


def pick(name: str | None) -> dict:
    """A TV by serial, name, room or alias; the configured default when none."""
    devices = tvs()
    if not devices:
        die("praxis knows no TVs right now")
    cfg = local_config()
    if not name:
        wanted = cfg.get("default")
        for d in devices:
            if d["id"] == wanted:
                return d
        return devices[0]
    n = name.lower().strip()
    aliases = {s: [a.lower() for a in t.get("aliases", [])] for s, t in cfg.get("tvs", {}).items()}
    for d in devices:
        names = [d["id"].lower(), d.get("name", "").lower(), d.get("room", "").lower(), *aliases.get(d["id"], [])]
        if n in names or any(n in x for x in names if x):
            return d
    die(f"no TV called {name!r}; known: " + ", ".join(d.get("name", d["id"]) for d in devices))
    raise AssertionError


def label(d: dict) -> str:
    return d.get("name") or d["id"]


def command(tv: dict, action: str, body: dict) -> dict:
    return call("POST", f"/devices/{tv['id']}/{action}", body, timeout=COMMAND_TIMEOUT) or {}


def cmd_status(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    if tv["health"] != "reachable":
        print(f"{label(tv)}: {tv['health']}" + (" (`on` wakes it)" if tv.get("can_wake") else "")
              + (f"; last error: {tv['last_error']}" if tv.get("last_error") else ""))
        return
    st = call("GET", f"/devices/{tv['id']}/status") or {}
    print(f"{label(tv)}: power={tv.get('power_mode')} app={st.get('app') or 'home'} ({st.get('app_id', '')}) player={st.get('player', '')}")


def cmd_devices(a: argparse.Namespace) -> None:
    for d in call("GET", "/devices") or []:
        print(f"{d.get('kind', ''):5} {d['health']:10} {label(d)} [{d['id']}]" + (f" room={d['room']}" if d.get("room") else ""))


def cmd_on(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    r = command(tv, "power", {"state": "on"})
    print(f"{label(tv)}: on" + (" (woken)" if r.get("woke") else ""))


def cmd_off(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    r = command(tv, "power", {"state": "off"})
    print(f"{label(tv)}: " + ("already off" if r.get("status") == "already_off" else "off"))


def cmd_key(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    for i, k in enumerate(a.keys):
        if i:
            time.sleep(a.gap)
        command(tv, "key", {"key": k})
    print("sent " + " ".join(a.keys))


def cmd_type(a: argparse.Namespace) -> None:
    command(pick(a.tv), "text", {"text": a.text})
    print(f"typed {a.text!r}")


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower().replace("+", " plus")).strip()


def cmd_apps(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    for app in call("GET", f"/devices/{tv['id']}/apps") or []:
        print(f"{app['id']:>16}  {app['name']}{'  [input]' if app.get('kind') == 'input' else ''}")


def cmd_launch(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    app_id = a.app
    if not (re.fullmatch(r"[A-Za-z0-9._-]+", app_id) and any(c.isdigit() for c in app_id)):
        if tv["health"] != "reachable":
            command(tv, "power", {"state": "on"})  # the app list needs the TV awake
        wanted = norm(a.app)
        apps = call("GET", f"/devices/{tv['id']}/apps") or []
        matches = [x for x in apps if wanted == norm(x["name"]) or wanted in norm(x["name"])]
        if not matches:
            die(f"no app matching {a.app!r} on {label(tv)}; try `apps`")
        app_id = min(matches, key=lambda x: len(x["name"]))["id"]
    body = {"app": app_id}
    if a.content_id:
        body.update(content_id=a.content_id, media_type=a.media_type or "series")
    r = command(tv, "launch", body)
    print(f"launched {app_id}" + (f" with content {a.content_id}" if a.content_id else "") + (" (woke the TV)" if r.get("woke") else ""))


def cmd_where(a: argparse.Namespace) -> None:
    for t in call("GET", "/watch?" + urllib.parse.urlencode({"title": a.title}), timeout=30) or []:
        stream = ", ".join(f"{s['id']}[{s['status']}]" for s in t.get("stream") or []) or "none"
        rent = ", ".join(t.get("rent") or [])
        print(f"{t['title']} ({t.get('year', '')}, {t['kind']}): stream {stream}" + (f"; rent {rent}" if rent else ""))
        for s in t.get("stream") or []:
            if s.get("question"):
                print(f"   ask Owen: {s['question']}  → then: tv.py have {s['id']} yes|no")


def cmd_have(a: argparse.Namespace) -> None:
    ans = a.answer.lower() in ("yes", "y", "true", "1")
    r = call("PUT", "/services/" + urllib.parse.quote(a.service, safe=""), {"have": ans}) or {}
    print(f"{r.get('name', a.service)}: {r.get('status', 'saved')}")


def cmd_snap(a: argparse.Namespace) -> None:
    tv = pick(a.tv)
    img = call("GET", f"/devices/{tv['id']}/snapshot" + ("?room=1" if a.room else ""), timeout=25, raw=True)
    out = a.out or os.path.join(tempfile.gettempdir(), time.strftime("tvcam-%Y%m%d-%H%M%S.jpg"))
    Path(out).write_bytes(img)
    print(out)


def main() -> None:
    p = argparse.ArgumentParser(prog="tv", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("status", cmd_status), ("on", cmd_on), ("off", cmd_off), ("apps", cmd_apps)):
        s = sub.add_parser(name)
        s.add_argument("tv", nargs="?")
        s.set_defaults(fn=fn)
    sub.add_parser("devices").set_defaults(fn=cmd_devices)
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
    s = sub.add_parser("have")
    s.add_argument("service")
    s.add_argument("answer", choices=["yes", "no", "y", "n"])
    s.set_defaults(fn=cmd_have)
    s = sub.add_parser("snap")
    s.add_argument("--tv")
    s.add_argument("--room", action="store_true")
    s.add_argument("out", nargs="?")
    s.set_defaults(fn=cmd_snap)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
