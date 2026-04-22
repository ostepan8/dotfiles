#!/usr/bin/env bash
# Wi-Fi status + SSID.
# Uses system_profiler (modern macOS) since networksetup -getairportnetwork
# was disabled in macOS 14+.

SSID=$(system_profiler SPAirPortDataType 2>/dev/null | \
    awk '/Current Network Information:/ {getline; gsub(/^[[:space:]]+|:[[:space:]]*$/, "", $0); print; exit}')

if [ -z "$SSID" ]; then
    ICON=""
    LABEL="off"
    COLOR=0xffcc241d
else
    ICON=""
    LABEL="$SSID"
    COLOR=0xff689d6a
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$LABEL"
