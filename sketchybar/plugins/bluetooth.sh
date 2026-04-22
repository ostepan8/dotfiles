#!/usr/bin/env bash
# Bluetooth power state.

STATUS=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null)

if [ "$STATUS" = "1" ]; then
    sketchybar --set "$NAME" icon="🔵" label="on"
else
    sketchybar --set "$NAME" icon="⚫" label="off"
fi
