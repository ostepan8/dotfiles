#!/usr/bin/env bash
# Focus the workspace currently visible on the built-in laptop display.
# Uses workspace-switching (not focus-monitor) to avoid macOS activating
# an app that has windows on other workspaces.

AERO=/opt/homebrew/bin/aerospace

# Find the built-in monitor's id
BUILT_IN=$("$AERO" list-monitors 2>/dev/null | grep -i "built-in" | awk -F'|' '{print $1}' | tr -d ' ')

if [ -z "$BUILT_IN" ]; then
    echo "no built-in display found" >&2
    exit 1
fi

ws=$("$AERO" list-workspaces --monitor "$BUILT_IN" --visible 2>/dev/null | head -1)
if [ -n "$ws" ]; then
    "$AERO" workspace "$ws"
fi
