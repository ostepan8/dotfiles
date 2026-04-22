#!/usr/bin/env bash
if [ "$SENDER" = "volume_change" ]; then VOL="$INFO"
else VOL=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
fi
MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
if [ "$MUTED" = "true" ] || [ "$VOL" = "0" ] || [ -z "$VOL" ]; then
    sketchybar --set "$NAME" icon="VOL" icon.font="SF Pro:Bold:11.0" icon.color=0xff928374 label="muted"
else
    sketchybar --set "$NAME" icon="VOL" icon.font="SF Pro:Bold:11.0" icon.color=0xffebdbb2 label="${VOL}%"
fi
