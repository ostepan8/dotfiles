#!/usr/bin/env bash
# Detect current monitor persistent IDs by physical position and rewrite displays.env.
#
# Heuristic:
#   LAPTOP_ID   = the built-in Retina display
#   LEFT_HP_ID  = non-built-in display with the smallest (most negative) x origin
#   RIGHT_HP_ID = non-built-in display with the largest (most positive) x origin
#
# Run this any time a monitor ID stops matching (cable swap, dock reconnect, etc.)
# Bind to Cmd+Opt+Shift+R in aerospace.toml.

set -euo pipefail

DP=/opt/homebrew/bin/displayplacer
CONFIG="${HOME}/.config/aerospace/displays.env"

if ! command -v "$DP" >/dev/null 2>&1; then
    osascript -e 'display notification "displayplacer not installed" with title "refresh-display-ids"'
    exit 1
fi

/usr/bin/python3 - "$DP" "$CONFIG" <<'PY'
import sys, re, subprocess

dp, config_path = sys.argv[1], sys.argv[2]
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
    m = re.match(r"\((-?\d+),(-?\d+)\)", fields.get("Origin", ""))
    if not m:
        continue
    screens.append({
        "id":      fields["Persistent screen id"],
        "type":    fields.get("Type", ""),
        "ox":      int(m.group(1)),
        "oy":      int(m.group(2)),
    })

if not screens:
    print("No enabled screens found", file=sys.stderr)
    sys.exit(1)

built_in = [s for s in screens if s["type"] == "built-in"]
external = sorted([s for s in screens if s["type"] != "built-in"], key=lambda s: s["ox"])

laptop_id = built_in[0]["id"] if built_in else ""
left_id   = external[0]["id"] if len(external) >= 1 else ""
right_id  = external[-1]["id"] if len(external) >= 2 else ""

content = f"""\
# Persistent display IDs captured from `displayplacer list`.
# Regenerate on a new machine: run `displayplacer list` and update these.
# Or press Cmd+Opt+Shift+R to auto-detect by monitor position.
#
# Layout (left → right based on origin x):
#   LEFT_HP_ID  : leftmost external monitor
#   LAPTOP_ID   : built-in Retina display
#   RIGHT_HP_ID : rightmost external monitor
LEFT_HP_ID={left_id}
LAPTOP_ID={laptop_id}
RIGHT_HP_ID={right_id}
"""

with open(config_path, "w") as f:
    f.write(content)

print(f"LEFT  → {left_id or '(none)'}")
print(f"LAPTOP→ {laptop_id or '(none)'}")
print(f"RIGHT → {right_id or '(none)'}")
PY

# Mirror to dotfiles if present
DOTFILES_ENV="${HOME}/dotfiles/aerospace/displays.env"
if [ -f "$DOTFILES_ENV" ]; then
    cp "$CONFIG" "$DOTFILES_ENV"
fi

osascript -e 'display notification "Display IDs refreshed — Cmd+Opt+[ / ] / \\ now active" with title "Aerospace Displays"'
