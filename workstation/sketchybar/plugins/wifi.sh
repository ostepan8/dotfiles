#!/usr/bin/env bash
# Wi-Fi status (mirrors the covered native menu-bar Wi-Fi). Shows the SSID when
# associated (truncated), else on/off by whether the default interface has an
# IP. Green = connected, dim = off.
IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
[ -z "$IFACE" ] && IFACE=en0

# networksetup returns the SSID on many macOS versions; on newer ones it may be
# withheld for privacy, so we fall back to an IP-presence check.
SSID=$(networksetup -getairportnetwork "$IFACE" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')

if [ -n "$SSID" ]; then
    [ "${#SSID}" -gt 12 ] && SSID="${SSID:0:11}…"
    sketchybar --set "$NAME" icon="WIFI" icon.font="SF Pro:Bold:11.0" \
        icon.color=0xff689d6a label="$SSID"
elif ipconfig getifaddr "$IFACE" >/dev/null 2>&1; then
    sketchybar --set "$NAME" icon="WIFI" icon.font="SF Pro:Bold:11.0" \
        icon.color=0xff689d6a label="on"
else
    sketchybar --set "$NAME" icon="WIFI" icon.font="SF Pro:Bold:11.0" \
        icon.color=0xff928374 label="off"
fi
