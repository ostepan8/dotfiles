#!/usr/bin/env bash
# Focus the workspace currently visible on the OTHER monitor.
# Avoids focus-monitor's app-activation weirdness (which causes macOS to
# sometimes switch to a different workspace when the same app exists there).

AERO=/opt/homebrew/bin/aerospace

# Get the monitor the user is currently on (by id)
CURRENT=$("$AERO" list-monitors --focused 2>/dev/null | awk -F'|' '{print $1}' | tr -d ' ')

# Find another monitor and its currently-visible workspace
"$AERO" list-monitors 2>/dev/null | while IFS='|' read -r id _name; do
    id=$(echo "$id" | tr -d ' ')
    [ -z "$id" ] && continue
    [ "$id" = "$CURRENT" ] && continue
    ws=$("$AERO" list-workspaces --monitor "$id" --visible 2>/dev/null | head -1)
    if [ -n "$ws" ]; then
        "$AERO" workspace "$ws"
        exit 0
    fi
done
