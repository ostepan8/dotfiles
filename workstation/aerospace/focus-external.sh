#!/usr/bin/env bash
# Focus an external monitor's workspace, degrading gracefully when fewer than
# two externals are connected.
#
# Usage: focus-external.sh <left|right>
#
# Behavior matrix:
#   2+ externals — left  → workspace 10 (pinned to leftmost external)
#                  right → workspace 9  (pinned to rightmost external)
#   1 external   — both args → workspace 9 (single external workspace)
#   0 externals  — fall back to focus-home.sh (laptop)
#
# Pairs with move-external.sh (move + follow) and the dynamic workspace pins
# set up by set-main-display.sh.

set -euo pipefail

AERO=/opt/homebrew/bin/aerospace
DIR="${1:-left}"

# Count non-built-in monitors.
EXTERNAL_COUNT=$(
    "$AERO" list-monitors 2>/dev/null \
        | awk -F'|' '{print $2}' \
        | grep -vi -c "built-in\|built in" || true
)

case "$EXTERNAL_COUNT" in
    0)
        exec "$(dirname "$0")/focus-home.sh"
        ;;
    1)
        "$AERO" workspace 9
        "$AERO" move-mouse monitor-lazy-center
        ;;
    *)
        case "$DIR" in
            left)  "$AERO" workspace 10 ;;
            right) "$AERO" workspace 9  ;;
            *)     echo "usage: $0 <left|right>" >&2; exit 1 ;;
        esac
        "$AERO" move-mouse monitor-lazy-center
        ;;
esac
