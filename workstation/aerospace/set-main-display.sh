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
#   3. Rewrites `[workspace-to-monitor-force-assignment]` so workspaces 1-8
#      pin to the laptop and 9/10 pin to whatever external monitor names
#      actually exist (or no pins at all when laptop-only, so every workspace
#      lands on the laptop).
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

# STATUS_FILE lets the Python block tell the shell whether anything actually
# changed (a display was re-origined, or the toml was rewritten). When nothing
# changed we skip the aerospace reload + sketchybar restart below — that churn
# was flashing/closing the top bar on every no-op `auto` run.
STATUS_FILE="$(mktemp -t setmaindisplay)"

DP="$DP" \
AERO="$AERO" \
TARGET_ARG="$ARG" \
AEROSPACE_TOML="$AEROSPACE_TOML" \
STATUS_FILE="$STATUS_FILE" \
    /usr/bin/python3 <<'PY'
import os, re, subprocess, sys, time

dp = os.environ["DP"]
aero = os.environ["AERO"]
target_arg = os.environ["TARGET_ARG"]
aerospace_toml = os.environ["AEROSPACE_TOML"]
status_file = os.environ["STATUS_FILE"]

# ---------------------------------------------------------------------------
# 1. Enumerate displays via displayplacer (positions, ids, resolutions).
# ---------------------------------------------------------------------------
def enumerate_screens():
    text = subprocess.check_output([dp, "list"], text=True)
    blocks = [b for b in text.split("\n\n") if "Persistent screen id" in b]
    out = []
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
        out.append({
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
    return out

# Retry: when fired right after a plug/unplug, displayplacer can momentarily
# report no enabled displays while macOS finishes reconfiguring. Bailing then
# (the old behaviour) skipped the sketchybar restart and left the bar stuck.
# The watcher already debounces, but retry here too as defense in depth.
screens = []
for _attempt in range(8):
    try:
        screens = enumerate_screens()
    except subprocess.CalledProcessError:
        screens = []
    if screens:
        break
    time.sleep(0.5)

if not screens:
    print("no enabled displays detected after retries", file=sys.stderr)
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
moved = not (tx == 0 and ty == 0)
if moved:
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
    original = f.read()
content = original

# 5a. outer.top — clear sketchybar on the main monitor, 8px on the rest.
#
# Sketchybar is 32pt tall and draws in the top strip of whichever display is
# macOS-main. How much of that strip AeroSpace already skips depends on which
# display that is:
#   built-in (notched): macOS keeps the 32pt notch strip out of the usable area
#       (NSScreen.visibleFrame stays 32pt short even with the menu bar set to
#       always-hide) and that strip is exactly where sketchybar sits, so the bar
#       is already accounted for — add only the 8pt margin.
#   external (no notch): nothing is reserved up there, so the gap has to cover
#       the bar itself: 32pt bar + 8pt margin = 40.
# Getting this backwards costs every window 32pt of height and leaves a black
# band between the bar and the top row of windows.
main_top_gap = 8 if target["builtin"] else 40
new_outer_top = f"outer.top        = [{{ monitor.'{gap_pattern}' = {main_top_gap} }}, 8]"
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
#       1 external : both 9 and 10 → that one external, so Alt+9 / Alt+0
#                    flip between two workspaces on the external.
#       0 externals: empty block (no pins; 9/10 land on the laptop).
#     Whenever at least one external exists, 1-8 are additionally pinned to
#     the built-in display. Without that pin AeroSpace lets 1-8 drift onto
#     whichever monitor they were last used on, which breaks the intended
#     split: 8 workspaces on the laptop, 2 on the external.
#     If the laptop display isn't active (clamshell mode), the 1-8 pins are
#     omitted — a pin to a missing monitor would be dead weight.
if len(aero_externals) >= 2:
    pin_9 = aero_escape(aero_externals[-1])
    pin_10 = aero_escape(aero_externals[0])
    new_block_body = f"9  = '^{pin_9}$'\n10 = '^{pin_10}$'\n"
elif len(aero_externals) == 1:
    pin = aero_escape(aero_externals[0])
    new_block_body = f"9  = '^{pin}$'\n10 = '^{pin}$'\n"
else:
    new_block_body = ""

if new_block_body and aero_builtin_name:
    laptop_pin = aero_escape(aero_builtin_name)
    laptop_lines = "".join(
        f"{n:<2} = '^{laptop_pin}$'\n" for n in range(1, 9)
    )
    new_block_body = laptop_lines + new_block_body

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

# Only touch the file (and thus its mtime) when the content actually changed —
# a no-op rewrite would still make callers think something moved.
toml_changed = content != original
if toml_changed:
    with open(aerospace_toml, "w") as f:
        f.write(content)

# Tell the shell whether any real change happened. "changed" → reload aerospace
# + restart sketchybar below; "noop" → skip both (no bar flash on idle runs).
with open(status_file, "w") as f:
    f.write("changed" if (moved or toml_changed) else "noop")
PY

# Read the Python block's verdict; default to "changed" so an unexpected
# failure to write the status file still reloads (fail safe, not silent).
STATUS="changed"
[ -f "$STATUS_FILE" ] && STATUS="$(cat "$STATUS_FILE" 2>/dev/null || echo changed)"
rm -f "$STATUS_FILE"

if [ "$STATUS" = "noop" ]; then
    # Nothing changed — don't reload aerospace or restart sketchybar. Still run
    # the focus step below for explicit user-initiated laptop/left/right calls.
    case "$ARG" in
        laptop) "${HOME}/.config/aerospace/focus-home.sh" ;;
        left)   "${HOME}/.config/aerospace/focus-external.sh" left ;;
        right)  "${HOME}/.config/aerospace/focus-external.sh" right ;;
    esac
    exit 0
fi

# Reload aerospace so the new outer.top + workspace pins take effect.
/opt/homebrew/bin/aerospace reload-config >/dev/null 2>&1 || true

# Sketchybar sizes itself to the macOS main display *at startup*. `--reload`
# re-runs sketchybarrc but doesn't re-create the bar window, so a smaller
# laptop screen ends up with a bar still sized for the larger HP. Full
# daemon restart is the only reliable way to re-query the new geometry.
#
# Block the restart until the main-display resolution stops changing, rather
# than a fixed sleep that races a multi-display yank (the bar then queries a
# mid-reconfigure size and renders off-screen / hidden).
wait_for_display_stable() {
    local prev="" cur i
    for (( i = 0; i < 20; i++ )); do
        # Resolution of whichever display is now at origin (0,0) = the new main.
        cur="$("$DP" list 2>/dev/null | awk 'BEGIN{RS=""} /Origin: \(0,0\)/{for(j=1;j<=NF;j++) if($j=="Resolution:"){print $(j+1); exit}}')"
        if [ -n "$cur" ] && [ "$cur" = "$prev" ]; then
            return 0
        fi
        prev="$cur"
        sleep 0.3
    done
}

if command -v sketchybar >/dev/null 2>&1; then
    ( wait_for_display_stable
      # brew services restart fails when the tap is untrusted; use launchctl directly.
      launchctl kickstart -k gui/"$(id -u)"/homebrew.mxcl.sketchybar >/dev/null 2>&1 \
          || pkill -x sketchybar 2>/dev/null || true
    ) &
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
