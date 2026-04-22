#!/usr/bin/env bash
# macOS output volume + mute state.
# Subscribed to the built-in `volume_change` event so it updates instantly.

if [ "$SENDER" = "volume_change" ]; then
    VOL="$INFO"
else
    VOL=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
fi

MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)

if [ "$MUTED" = "true" ] || [ "$VOL" = "0" ] || [ -z "$VOL" ]; then
    ICON=""
elif [ "$VOL" -ge 60 ]; then
    ICON=""
elif [ "$VOL" -ge 30 ]; then
    ICON=""
else
    ICON=""
fi

sketchybar --set "$NAME" icon="$ICON" label="${VOL}%"
