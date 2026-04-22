#!/usr/bin/env bash
# Bluetooth power state.

STATUS=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null)

if [ "$STATUS" = "1" ]; then
    sketchybar --set "$NAME" icon="" icon.color=0xff458588
else
    sketchybar --set "$NAME" icon="" icon.color=0xffa89984
fi
