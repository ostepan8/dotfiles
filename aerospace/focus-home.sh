#!/usr/bin/env bash
# Switch to whatever workspace is currently visible on the built-in laptop display.
# Always goes "home" — does not toggle.

AERO=/opt/homebrew/bin/aerospace
BUILT_IN_ID=$("$AERO" list-monitors 2>/dev/null | grep -i "built-in" | awk -F'|' '{print $1}' | tr -d ' ')

if [ -z "$BUILT_IN_ID" ]; then
    exit 0
fi

WS=$("$AERO" list-workspaces --monitor "$BUILT_IN_ID" --visible 2>/dev/null | head -1)

if [ -n "$WS" ]; then
    "$AERO" workspace "$WS"
fi
