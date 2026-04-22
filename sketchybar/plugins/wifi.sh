#!/usr/bin/env bash
# Wi-Fi status + SSID.

SSID=$(system_profiler SPAirPortDataType 2>/dev/null | \
    awk '/Current Network Information:/ {getline; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", $0); print; exit}')

if [ -z "$SSID" ]; then
    ICON="􀙈"
    COLOR=0xff928374
    LABEL="off"
else
    ICON="􀙇"
    COLOR=0xff689d6a
    LABEL="$SSID"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL"
