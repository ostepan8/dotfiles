#!/usr/bin/env python3
"""
remote.py - Vim-inspired Tkinter GUI remote for Roku devices.

Every button shows its hotkey prefix (like a vim cheat sheet).
hjkl move the d-pad. Space toggles play/pause. ':' opens command prompt.
Shells out to roku.py for each action. Stdlib only.

Usage:
    python3 remote.py [--device NAME] [--cli /path/to/roku.py]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import font as tkfont
from typing import Callable, Optional

DEFAULT_CLI = Path(
    "/Users/ostepan/Desktop/projects/claude-code/claude-code-living-directory/roku.py"
)

BG        = "#1d1f21"
BG_ALT    = "#282a2e"
FG        = "#c5c8c6"
FG_DIM    = "#6b7280"
ACCENT    = "#81a2be"
YELLOW    = "#f0c674"
GREEN     = "#b5bd68"
RED       = "#cc6666"
MAGENTA   = "#b294bb"
BTN_ACTIVE = "#373b41"


def run_cli(cli: Path, args: tuple[str, ...], device: Optional[str], count: int = 1) -> tuple[bool, str]:
    cmd = [sys.executable, str(cli), *args]
    if count > 1:
        cmd += ["--count", str(count)]
    if device:
        cmd += ["--device", device]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except (subprocess.TimeoutExpired, OSError) as exc:
        return False, f"error: {exc}"
    ok = result.returncode == 0
    out = (result.stdout or result.stderr or "").strip().splitlines()
    msg = out[-1] if out else ("ok" if ok else "failed")
    return ok, msg


def load_device_names(cli: Path) -> list[str]:
    reg = cli.parent / "roku_devices.json"
    if not reg.exists():
        return []
    try:
        data = json.loads(reg.read_text())
    except (json.JSONDecodeError, OSError):
        return []
    names: list[str] = []
    for dev in data.get("devices", {}).values():
        name = dev.get("friendly_name") or dev.get("device_name") or dev.get("serial_number")
        if name:
            names.append(name)
    return names


@dataclass(frozen=True)
class Bind:
    key_label: str           # shown in UI, e.g. "h", "SPC", "P"
    name: str                # shown in UI, e.g. "Left"
    args: tuple[str, ...]
    count: int = 1
    color: str = YELLOW


# Grid sections ------------------------------------------------------------
SECTIONS: list[tuple[str, list[Bind]]] = [
    ("Navigation", [
        Bind("h",  "Left",         ("left",)),
        Bind("j",  "Down",         ("down",)),
        Bind("k",  "Up",           ("up",)),
        Bind("l",  "Right",        ("right",)),
        Bind("o",  "OK / Select",  ("select",), color=GREEN),
        Bind("u",  "Back",         ("back",)),
        Bind("gg", "Home",         ("home",), color=MAGENTA),
    ]),
    ("Playback", [
        Bind("SPC", "Play / Pause",  ("key", "Play"), color=GREEN),
        Bind("H",   "Rewind",        ("rewind",)),
        Bind("L",   "Fast-forward",  ("fast-forward",)),
        Bind("r",   "Instant replay",("instant-replay",)),
    ]),
    ("Audio", [
        Bind("=",   "Volume up",     ("volume-up",),   count=2),
        Bind("-",   "Volume down",   ("volume-down",), count=2),
        Bind("m",   "Mute",          ("mute",)),
    ]),
    ("Power", [
        Bind("P",   "Power on",      ("power-on",),  color=GREEN),
        Bind("Q",   "Power off",     ("power-off",), color=RED),
    ]),
    ("Apps", [
        Bind("an",  "Netflix",       ("launch", "Netflix"), color=MAGENTA),
        Bind("ay",  "YouTube",       ("launch", "YouTube"), color=MAGENTA),
        Bind("au",  "Hulu",          ("launch", "Hulu"),    color=MAGENTA),
    ]),
    ("Input", [
        Bind("1",   "HDMI 1",        ("switch-input", "HDMI1")),
        Bind("2",   "HDMI 2",        ("switch-input", "HDMI2")),
        Bind("3",   "HDMI 3",        ("switch-input", "HDMI3")),
        Bind("4",   "HDMI 4",        ("switch-input", "HDMI4")),
    ]),
    ("Info", [
        Bind("i",   "Now playing",   ("now-playing",)),
        Bind("R",   "Re-discover",   ("discover",)),
    ]),
    ("Prompts", [
        Bind("/",   "Search",        (), color=ACCENT),
        Bind("t",   "Type text",     (), color=ACCENT),
        Bind(":",   "Command",       (), color=ACCENT),
        Bind("d",   "Switch device", (), color=ACCENT),
        Bind("?",   "Help",          (), color=ACCENT),
        Bind("ZZ",  "Quit",          (), color=RED),
    ]),
]


class RemoteApp:
    def __init__(self, cli: Path, device: Optional[str]) -> None:
        self.cli = cli
        self.pending_prefix = ""          # for multi-char bindings like "gg", "an"
        self.root = tk.Tk()
        self.root.title("roku-remote")
        self.root.geometry("540x720")
        self.root.minsize(480, 640)
        self.root.configure(bg=BG)

        self.mono = tkfont.Font(family="Menlo", size=13)
        self.mono_bold = tkfont.Font(family="Menlo", size=13, weight="bold")
        self.mono_small = tkfont.Font(family="Menlo", size=11)
        self.mono_title = tkfont.Font(family="Menlo", size=11, weight="bold")

        devices = load_device_names(self.cli)
        self.device = device or (devices[0] if devices else None)

        self.status_var = tk.StringVar(value="-- NORMAL --")
        self.cmd_var = tk.StringVar(value="")
        self.mode_cmd = False             # True while `:` or `/` prompt is open
        self.cmd_kind = ""                # "cmd" | "search" | "type" | "device"

        self._build_ui()
        self._bind_keys()
        self.root.bind("<FocusIn>", lambda _e: self._refocus())
        self._refocus()

    # UI -------------------------------------------------------------------
    def _build_ui(self) -> None:
        # Modeline (top)
        self.modeline = tk.Label(
            self.root,
            anchor="w",
            padx=10, pady=4,
            bg=ACCENT, fg="#1d1f21",
            font=self.mono_bold,
            text=self._modeline_text(),
        )
        self.modeline.pack(fill="x")

        # Main scrollable-ish area as a plain frame (grid fits in window).
        body = tk.Frame(self.root, bg=BG)
        body.pack(fill="both", expand=True, padx=8, pady=6)

        # Two columns of sections.
        left = tk.Frame(body, bg=BG)
        right = tk.Frame(body, bg=BG)
        left.pack(side="left", fill="both", expand=True, padx=(0, 4))
        right.pack(side="left", fill="both", expand=True, padx=(4, 0))

        # Distribute sections: first half left, second half right.
        half = (len(SECTIONS) + 1) // 2
        for title, binds in SECTIONS[:half]:
            self._section(left, title, binds)
        for title, binds in SECTIONS[half:]:
            self._section(right, title, binds)

        # Command line (bottom) — hidden until : or / or t or d
        self.cmd_frame = tk.Frame(self.root, bg=BG_ALT)
        self.cmd_prompt = tk.Label(self.cmd_frame, text=":", bg=BG_ALT, fg=YELLOW, font=self.mono_bold, padx=6)
        self.cmd_prompt.pack(side="left")
        self.cmd_entry = tk.Entry(
            self.cmd_frame,
            textvariable=self.cmd_var,
            bg=BG_ALT, fg=FG,
            insertbackground=FG,
            relief="flat",
            font=self.mono,
            highlightthickness=0,
        )
        self.cmd_entry.pack(side="left", fill="x", expand=True, padx=(0, 8), pady=4)
        self.cmd_entry.bind("<Return>", self._on_cmd_submit)
        self.cmd_entry.bind("<Escape>", self._on_cmd_cancel)

        # Status line (bottom-most)
        self.status_label = tk.Label(
            self.root,
            textvariable=self.status_var,
            anchor="w",
            padx=10, pady=4,
            bg=BG_ALT, fg=GREEN,
            font=self.mono_small,
        )
        self.status_label.pack(fill="x", side="bottom")

    def _section(self, parent: tk.Frame, title: str, binds: list[Bind]) -> None:
        header = tk.Label(
            parent, text=f"-- {title} --",
            anchor="w", bg=BG, fg=FG_DIM, font=self.mono_title,
            padx=4, pady=2,
        )
        header.pack(fill="x", pady=(6, 2))
        for b in binds:
            self._bind_row(parent, b)

    def _bind_row(self, parent: tk.Frame, b: Bind) -> None:
        row = tk.Frame(parent, bg=BG)
        row.pack(fill="x", padx=2, pady=1)
        key = tk.Label(
            row, text=f"{b.key_label:>4}",
            bg=BG, fg=b.color, font=self.mono_bold,
            width=5, anchor="e", padx=4,
        )
        key.pack(side="left")
        name = tk.Label(
            row, text=f"  {b.name}",
            bg=BG, fg=FG, font=self.mono, anchor="w", padx=2,
        )
        name.pack(side="left", fill="x", expand=True)

        def on_click(_e=None, b=b):
            self._invoke(b)
        for w in (row, key, name):
            w.bind("<Button-1>", on_click)
            w.bind("<Enter>", lambda _e, ws=(row, key, name): [x.configure(bg=BTN_ACTIVE) for x in ws])
            w.bind("<Leave>", lambda _e, ws=(row, key, name): [x.configure(bg=BG) for x in ws])

    # Key handling ---------------------------------------------------------
    def _bind_keys(self) -> None:
        self.root.bind("<Key>", self._on_key)

    def _on_key(self, event: tk.Event) -> None:
        if self.mode_cmd:
            return
        keysym = event.keysym
        char = event.char

        # Special keys first
        if keysym == "Escape":
            self.pending_prefix = ""
            self._set_status("-- NORMAL --", GREEN)
            return
        if keysym == "Return":
            self._invoke(Bind("CR", "Select", ("select",)))
            return
        if keysym == "BackSpace":
            self._invoke(Bind("BS", "Back", ("back",)))
            return
        if keysym in ("Up",):
            self._invoke(Bind("k", "Up", ("up",)))
            return
        if keysym in ("Down",):
            self._invoke(Bind("j", "Down", ("down",)))
            return
        if keysym in ("Left",):
            self._invoke(Bind("h", "Left", ("left",)))
            return
        if keysym in ("Right",):
            self._invoke(Bind("l", "Right", ("right",)))
            return
        if keysym == "space":
            self._invoke(Bind("SPC", "Play/Pause", ("key", "Play")))
            return

        if not char:
            return

        # Prompt-opening keys (only when no prefix)
        if not self.pending_prefix:
            if char == "/":
                self._open_prompt("search", "/")
                return
            if char == ":":
                self._open_prompt("cmd", ":")
                return

        seq = self.pending_prefix + char
        handled = self._try_bind(seq)
        if handled:
            self.pending_prefix = ""
            self._set_status("-- NORMAL --", GREEN)
            return

        # Could still be a prefix of a longer bind?
        if any(self._all_keys_starting_with(seq)):
            self.pending_prefix = seq
            self._set_status(f"(pending) {seq}_", YELLOW)
            return

        # Unknown
        self.pending_prefix = ""
        self._set_status(f"not a binding: {seq}", RED)

    def _all_keys_starting_with(self, prefix: str) -> list[Bind]:
        found: list[Bind] = []
        for _title, binds in SECTIONS:
            for b in binds:
                if b.key_label.startswith(prefix) and b.key_label != prefix:
                    found.append(b)
        return found

    def _try_bind(self, seq: str) -> bool:
        # Built-in sequences with prompt behavior
        if seq == "t":
            self._open_prompt("type", "type: ")
            return True
        if seq == "d":
            self._open_prompt("device", "device: ")
            return True
        if seq == "?":
            self._set_status("(all bindings visible above)", ACCENT)
            return True
        if seq == "ZZ":
            self.root.destroy()
            return True
        for _title, binds in SECTIONS:
            for b in binds:
                if b.key_label == seq:
                    if b.args:
                        self._invoke(b)
                    else:
                        # Prompt-style bindings already handled above; treat others as no-op
                        self._set_status(f"(noop) {b.key_label}", FG_DIM)
                    return True
        return False

    # Command prompt -------------------------------------------------------
    def _open_prompt(self, kind: str, label: str) -> None:
        self.cmd_kind = kind
        self.mode_cmd = True
        self.cmd_prompt.configure(text=label)
        self.cmd_var.set("")
        self.cmd_frame.pack(fill="x", before=self.status_label)
        self.cmd_entry.focus_set()
        self._set_status(f"-- {kind.upper()} --", YELLOW)

    def _on_cmd_submit(self, _e=None) -> None:
        text = self.cmd_var.get().strip()
        kind = self.cmd_kind
        self._close_prompt()
        if not text:
            self._set_status("cancelled", FG_DIM)
            return
        if kind == "search":
            self._invoke_raw(("search", text), f"search {text!r}")
        elif kind == "type":
            self._invoke_raw(("type", text), f"type {text!r}")
        elif kind == "device":
            self.device = text
            self.modeline.configure(text=self._modeline_text())
            self._set_status(f"device -> {text}", GREEN)
        elif kind == "cmd":
            # free-form roku.py args
            parts = tuple(text.split())
            self._invoke_raw(parts, f":{text}")

    def _on_cmd_cancel(self, _e=None) -> None:
        self._close_prompt()
        self._set_status("-- NORMAL --", GREEN)

    def _close_prompt(self) -> None:
        self.mode_cmd = False
        self.cmd_kind = ""
        self.cmd_frame.pack_forget()
        self._refocus()

    # Actions --------------------------------------------------------------
    def _invoke(self, b: Bind) -> None:
        if not b.args:
            return
        self._invoke_raw(b.args, b.name, count=b.count)

    def _invoke_raw(self, args: tuple[str, ...], label: str, count: int = 1) -> None:
        self._set_status(f"... {label}", YELLOW)
        self.root.update_idletasks()
        ok, msg = run_cli(self.cli, args, self.device, count=count)
        self._set_status(f"{label} - {msg}", GREEN if ok else RED)
        if args and args[0] == "discover":
            names = load_device_names(self.cli)
            if names and self.device not in names:
                self.device = names[0]
                self.modeline.configure(text=self._modeline_text())

    def _set_status(self, text: str, color: str) -> None:
        self.status_var.set(text)
        self.status_label.configure(fg=color)

    def _modeline_text(self) -> str:
        return f"  roku-remote   device: {self.device or '<none>'}   hjkl=move  SPC=play  P=on  Q=off  :=cmd"

    def _refocus(self) -> None:
        self.root.focus_set()

    def run(self) -> None:
        self.root.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(description="Vim-style Roku remote GUI")
    parser.add_argument("--device", help="Friendly device name")
    parser.add_argument("--cli", type=Path, default=DEFAULT_CLI, help="Path to roku.py")
    args = parser.parse_args()

    if not args.cli.is_file():
        print(f"error: roku.py not found at {args.cli}", file=sys.stderr)
        return 2

    RemoteApp(cli=args.cli, device=args.device).run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
