#!/usr/bin/env bash
# Send the focused window to an external monitor's workspace, then follow it.
# Same monitor-count degradation as focus-external.sh.
#
# Usage: move-external.sh <left|right>
#
# Behavior matrix:
#   2+ externals — left  → workspace 10  (pinned to leftmost external)
#                  right → workspace 9   (pinned to rightmost external)
#   1 external   — both args → workspace 9 (single external workspace)
#   0 externals  — fall back to move-home.sh (laptop)

set -euo pipefail

AERO=/opt/homebrew/bin/aerospace
DIR="${1:-left}"

EXTERNAL_COUNT=$(
    "$AERO" list-monitors 2>/dev/null \
        | awk -F'|' '{print $2}' \
        | grep -vi -c "built-in\|built in" || true
)

move_and_follow() {
    local ws="$1"
    "$AERO" move-node-to-workspace "$ws"
    "$AERO" workspace "$ws"
    "$AERO" move-mouse monitor-lazy-center
}

case "$EXTERNAL_COUNT" in
    0)
        exec "$(dirname "$0")/move-home.sh"
        ;;
    1)
        move_and_follow 9
        ;;
    *)
        case "$DIR" in
            left)  move_and_follow 10 ;;
            right) move_and_follow 9  ;;
            *)     echo "usage: $0 <left|right>" >&2; exit 1 ;;
        esac
        ;;
esac
