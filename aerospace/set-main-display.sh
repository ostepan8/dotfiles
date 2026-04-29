#!/usr/bin/env bash
# Make a named monitor the macOS "main display" (the one with the menu bar
# and sketchybar). Works by shifting every screen's origin so the target lands
# at (0,0) — macOS treats the (0,0) screen as main.
#
# Usage: set-main-display.sh <laptop|left|right>
#
# IDs come from displays.env. Regenerate that file on a new machine via
# `displayplacer list`.

set -euo pipefail

CONFIG="${HOME}/.config/aerospace/displays.env"
if [ ! -f "$CONFIG" ]; then
    echo "missing $CONFIG — run 'displayplacer list' and populate it" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"

case "${1:-}" in
    laptop) TARGET_ID="${LAPTOP_ID:-}";  GAP_PATTERN='built-in' ;;
    left)   TARGET_ID="${LEFT_HP_ID:-}"; GAP_PATTERN='HP 327se \(2\)' ;;
    right)  TARGET_ID="${RIGHT_HP_ID:-}"; GAP_PATTERN='HP 327se \(1\)' ;;
    *)      echo "usage: $0 <laptop|left|right>" >&2; exit 1 ;;
esac

if [ -z "$TARGET_ID" ]; then
    echo "no id configured for '$1' in $CONFIG" >&2
    exit 1
fi

DP=/opt/homebrew/bin/displayplacer
if ! command -v "$DP" >/dev/null 2>&1; then
    echo "displayplacer not installed (brew install jakehilborn/jakehilborn/displayplacer)" >&2
    exit 1
fi

# Pass dp path + target id + gap pattern + config path as env vars; Python
# runs displayplacer itself to avoid the "stdin already consumed by heredoc" trap.
DP="$DP" \
TARGET_ID="$TARGET_ID" \
GAP_PATTERN="$GAP_PATTERN" \
AEROSPACE_TOML="${HOME}/.config/aerospace/aerospace.toml" \
    /usr/bin/python3 <<'PY'
import os, re, subprocess, sys

dp = os.environ["DP"]
target_id = os.environ["TARGET_ID"]
gap_pattern = os.environ["GAP_PATTERN"]
aerospace_toml = os.environ["AEROSPACE_TOML"]

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
    m = re.match(r"\((-?\d+),(-?\d+)\)", fields["Origin"].split(" ")[0])
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
    })

target = next((s for s in screens if s["id"] == target_id), None)
if not target:
    # Target not connected right now — graceful no-op so a binding press doesn't error.
    print(f"target {target_id} not currently enabled — skipping", file=sys.stderr)
    sys.exit(0)

tx, ty = target["ox"], target["oy"]
already_main = (tx == 0 and ty == 0)

if not already_main:
    parts = [
        f'id:{s["id"]} res:{s["res"]} hz:{s["hz"]} color_depth:{s["depth"]} '
        f'enabled:true scaling:{s["scaling"]} origin:({s["ox"]-tx},{s["oy"]-ty}) degree:{s["rotation"]}'
        for s in screens
    ]
    subprocess.run([dp, *parts], check=True)

# Rewrite outer.top in aerospace.toml so 40px is reserved ONLY on the new
# main display (other monitors get 8px since no bar lives there). Aerospace's
# gap config is static at parse time, so the only way to get per-main gaps
# is to mutate the file and reload. We always rewrite — even on the no-op
# "already main" path — to recover from out-of-band main-display changes
# (e.g. user dragged the white bar in System Settings).
new_line = f"outer.top        = [{{ monitor.'{gap_pattern}' = 40 }}, 8]"
with open(aerospace_toml) as f:
    content = f.read()
new_content = re.sub(
    r"^outer\.top\s*=.*$",
    new_line,
    content,
    count=1,
    flags=re.MULTILINE,
)
if new_content != content:
    with open(aerospace_toml, "w") as f:
        f.write(new_content)
PY

# Reload aerospace so the new gap config takes effect immediately.
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
