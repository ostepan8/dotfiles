#!/usr/bin/env bash
# Make a named monitor the macOS "main display" (the one with the menu bar
# and sketchybar). Works by shifting every screen's origin so the target lands
# at (0,0) — macOS treats the (0,0) screen as main.
#
# Usage: set-main-display.sh <laptop|left|right|auto>
#   laptop  built-in Retina display
#   left    leftmost external (origin-x order); falls back to the only external
#           if just one is connected
#   right   rightmost external; falls back to the only external if just one
#   auto    pick the leftmost external if any; else laptop. Fired by the
#           display-watcher LaunchAgent on plug/unplug.
#
# Side effects on every invocation:
#   1. (Maybe) shifts display origins via displayplacer to make target main.
#   2. Rewrites `outer.top` in aerospace.toml so the 40px sketchybar gap is
#      reserved on whichever monitor is now main.
#   3. Rewrites `[workspace-to-monitor-force-assignment]` so workspaces 9/10
#      pin to whatever external monitor names actually exist (or no pin when
#      laptop-only, so 9/10 land on the laptop).
#   4. Reloads aerospace and restarts sketchybar so the new geometry sticks.
#
# Requires `displayplacer` (brew install jakehilborn/jakehilborn/displayplacer)
# and `aerospace`.

set -euo pipefail

ARG="${1:-auto}"
case "$ARG" in
    laptop|left|right|auto) ;;
    *) echo "usage: $0 <laptop|left|right|auto>" >&2; exit 1 ;;
esac

DP=/opt/homebrew/bin/displayplacer
AERO=/opt/homebrew/bin/aerospace
AEROSPACE_TOML="${HOME}/.config/aerospace/aerospace.toml"

if ! command -v "$DP" >/dev/null 2>&1; then
    echo "displayplacer not installed (brew install jakehilborn/jakehilborn/displayplacer)" >&2
    exit 1
fi

DP="$DP" \
AERO="$AERO" \
TARGET_ARG="$ARG" \
AEROSPACE_TOML="$AEROSPACE_TOML" \
    /usr/bin/python3 <<'PY'
import os, re, subprocess, sys

dp = os.environ["DP"]
aero = os.environ["AERO"]
target_arg = os.environ["TARGET_ARG"]
aerospace_toml = os.environ["AEROSPACE_TOML"]

# ---------------------------------------------------------------------------
# 1. Enumerate displays via displayplacer (positions, ids, resolutions).
# ---------------------------------------------------------------------------
text = subprocess.check_output([dp, "list"], text=True)
blocks = [b for b in text.split("\n\n") if "Persistent screen id" in b]
screens = []
for blk in blocks:
    fields = {}
    for line in blk.splitlines():
        if ":" in line and not line.startswith("  "):
            k, _, v = line.partition(":")
            fields[k.strip()] = v.strip()
    if fields.get("Enabled") != "true":
        continue
    m = re.match(r"\((-?\d+),(-?\d+)\)", fields.get("Origin", "").split(" ")[0])
    if not m:
        continue
    screens.append({
        "id":       fields["Persistent screen id"],
        "res":      fields["Resolution"],
        "hz":       fields.get("Hertz", "60"),
        "depth":    fields.get("Color Depth", fields.get("Color depth", "8")),
        "scaling":  fields.get("Scaling", "on"),
        "rotation": fields.get("Rotation", "0").split(" ")[0],
        "ox":       int(m.group(1)),
        "oy":       int(m.group(2)),
        "builtin":  "built in" in fields.get("Type", "").lower(),
    })

if not screens:
    print("no enabled displays detected", file=sys.stderr)
    sys.exit(0)

built_in = next((s for s in screens if s["builtin"]), None)
externals = sorted([s for s in screens if not s["builtin"]], key=lambda s: s["ox"])

# ---------------------------------------------------------------------------
# 2. Pick the target screen.
# ---------------------------------------------------------------------------
def pick():
    if target_arg == "laptop":
        return built_in
    if target_arg == "left":
        return externals[0] if externals else None
    if target_arg == "right":
        # Falls back to the only external if just one is connected.
        return externals[-1] if externals else None
    if target_arg == "auto":
        # `auto` reconciles aerospace state (pins, gaps, sketchybar) to the
        # current monitor set — it must NOT override the user's manual main
        # display choice. If something is already at (0,0), keep it main.
        # Only fall back to "leftmost external or laptop" if no screen sits
        # at the origin (shouldn't happen in practice, but defensive).
        current_main = next(
            (s for s in screens if s["ox"] == 0 and s["oy"] == 0), None
        )
        if current_main:
            return current_main
        return externals[0] if externals else built_in
    return None

target = pick()
if not target:
    print(f"no display matches '{target_arg}' — skipping", file=sys.stderr)
    sys.exit(0)

# ---------------------------------------------------------------------------
# 3. Map screens to the names aerospace uses (`aerospace list-monitors`).
#    aerospace's list-monitors doesn't expose persistent IDs, so we map by
#    sorted order: built-in is unambiguous; externals are ordered the same
#    way (origin x) in both lists in practice.
# ---------------------------------------------------------------------------
mons = subprocess.check_output([aero, "list-monitors"], text=True).strip().splitlines()
aero_builtin_name = None
aero_externals = []  # in aerospace's listing order
for line in mons:
    if "|" not in line:
        continue
    _, _, name = line.partition("|")
    name = name.strip()
    lname = name.lower()
    if "built-in" in lname or "built in" in lname:
        aero_builtin_name = name
    else:
        aero_externals.append(name)

def aero_escape(name):
    """Escape regex metacharacters for an aerospace monitor-name regex."""
    return re.sub(r"([(){}\[\].*+?|^$\\])", r"\\\1", name)

def aero_name_for_target():
    if target["builtin"]:
        return aero_builtin_name or "built-in"
    if not aero_externals:
        return None
    if len(aero_externals) == 1:
        return aero_externals[0]
    idx = externals.index(target)
    return aero_externals[idx] if idx < len(aero_externals) else aero_externals[-1]

target_aero_name = aero_name_for_target()
gap_pattern = aero_escape(target_aero_name) if target_aero_name else "built-in"

# ---------------------------------------------------------------------------
# 4. Shift origins so target lands at (0,0) (no-op if already main).
# ---------------------------------------------------------------------------
tx, ty = target["ox"], target["oy"]
if not (tx == 0 and ty == 0):
    parts = [
        f'id:{s["id"]} res:{s["res"]} hz:{s["hz"]} color_depth:{s["depth"]} '
        f'enabled:true scaling:{s["scaling"]} origin:({s["ox"]-tx},{s["oy"]-ty}) degree:{s["rotation"]}'
        for s in screens
    ]
    subprocess.run([dp, *parts], check=True)

# ---------------------------------------------------------------------------
# 5. Rewrite aerospace.toml: outer.top + workspace-to-monitor-force-assignment.
# ---------------------------------------------------------------------------
with open(aerospace_toml) as f:
    content = f.read()

# 5a. outer.top — 40px gap on main, 8px on the rest.
new_outer_top = f"outer.top        = [{{ monitor.'{gap_pattern}' = 40 }}, 8]"
content = re.sub(
    r"^outer\.top\s*=.*$",
    new_outer_top.replace("\\", "\\\\"),  # protect backrefs in re.sub replacement
    content,
    count=1,
    flags=re.MULTILINE,
)

# 5b. workspace-to-monitor-force-assignment block. Strategy:
#       2+ externals: 9 → rightmost, 10 → leftmost (preserves the
#                     original "alt-] = right, alt-[ = left" intent).
#       1 external : both 9 and 10 → that one external.
#       0 externals: empty block (no pins; 9/10 land on the laptop).
if len(aero_externals) >= 2:
    pin_9 = aero_escape(aero_externals[-1])
    pin_10 = aero_escape(aero_externals[0])
    new_block_body = f"9  = '^{pin_9}$'\n10 = '^{pin_10}$'\n"
elif len(aero_externals) == 1:
    pin = aero_escape(aero_externals[0])
    new_block_body = f"9  = '^{pin}$'\n10 = '^{pin}$'\n"
else:
    new_block_body = ""

# Trailing blank line keeps the section visually separated from whatever
# table follows (e.g. [key-mapping]).
new_block = "[workspace-to-monitor-force-assignment]\n" + new_block_body + "\n"

# Match the section header + every following non-section line (until next
# `^[` table header, or end of file). DOTALL is intentionally not used —
# we want `.` to stop at newlines so the lookahead per line works.
content = re.sub(
    r"\[workspace-to-monitor-force-assignment\]\n(?:(?!\[)[^\n]*\n)*",
    new_block.replace("\\", "\\\\"),
    content,
    count=1,
)

with open(aerospace_toml, "w") as f:
    f.write(content)
PY

# Reload aerospace so the new outer.top + workspace pins take effect.
/opt/homebrew/bin/aerospace reload-config >/dev/null 2>&1 || true

# Sketchybar sizes itself to the macOS main display *at startup*. `--reload`
# re-runs sketchybarrc but doesn't re-create the bar window, so a smaller
# laptop screen ends up with a bar still sized for the larger HP. Full
# daemon restart is the only reliable way to re-query the new geometry.
if command -v sketchybar >/dev/null 2>&1; then
    # Give macOS a moment to finish reconfiguring displays before sketchybar
    # asks for the main-display dimensions.
    ( sleep 0.6 && brew services restart sketchybar >/dev/null 2>&1 ) &
fi

# Focus the workspace on the newly-promoted main monitor so the user's
# focus follows the bar. Skipped for `auto` because that path is fired by
# the display-watcher LaunchAgent on plug/unplug — stealing focus from
# whatever app the user is in would be hostile.
case "$ARG" in
    laptop) "${HOME}/.config/aerospace/focus-home.sh" ;;
    left)   "${HOME}/.config/aerospace/focus-external.sh" left ;;
    right)  "${HOME}/.config/aerospace/focus-external.sh" right ;;
esac
