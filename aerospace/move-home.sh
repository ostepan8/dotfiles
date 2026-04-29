#!/usr/bin/env bash
# Move the focused window to the laptop's currently-visible workspace, then
# follow it there. Mirror of focus-home.sh but for the alt-shift-\ binding.
# Laptop has no fixed workspace number (workspaces 9/10 are pinned to the
# externals), so we have to discover its current workspace at runtime.

AERO=/opt/homebrew/bin/aerospace
BUILT_IN_ID=$("$AERO" list-monitors 2>/dev/null | grep -i "built-in" | awk -F'|' '{print $1}' | tr -d ' ')

if [ -z "$BUILT_IN_ID" ]; then
    exit 0
fi

WS=$("$AERO" list-workspaces --monitor "$BUILT_IN_ID" --visible 2>/dev/null | head -1)

if [ -n "$WS" ]; then
    "$AERO" move-node-to-workspace "$WS"
    "$AERO" workspace "$WS"
fi
