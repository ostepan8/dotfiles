#!/usr/bin/env bash
SSID=$(system_profiler SPAirPortDataType 2>/dev/null | \
    awk '/Current Network Information:/ {getline; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", $0); print; exit}')
if [ -z "$SSID" ]; then
    sketchybar --set "$NAME" icon="WIFI" icon.font="SF Pro:Bold:11.0" icon.color=0xff928374 label="off"
else
    sketchybar --set "$NAME" icon="WIFI" icon.font="SF Pro:Bold:11.0" icon.color=0xff689d6a label="$SSID"
fi
