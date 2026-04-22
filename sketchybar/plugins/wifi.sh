#!/usr/bin/env bash
# Wi-Fi status + SSID.

SSID=$(system_profiler SPAirPortDataType 2>/dev/null | \
    awk '/Current Network Information:/ {getline; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", $0); print; exit}')

if [ -z "$SSID" ]; then
    ICON="❌"
    LABEL="off"
else
    ICON="📶"
    LABEL="$SSID"
fi

sketchybar --set "$NAME" icon="$ICON" label="$LABEL"
