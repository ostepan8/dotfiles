#!/usr/bin/env bash
# Battery percentage + charging state.

PERCENT=$(pmset -g batt | grep -Eo '[0-9]+%' | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENT" = "" ]; then
    sketchybar --set "$NAME" icon="" label="--"
    exit 0
fi

# Color-code by level
if [ "$CHARGING" != "" ]; then
    ICON="󰂄"   # charging bolt
    COLOR=0xff98971a  # green
elif [ "$PERCENT" -gt 75 ]; then
    ICON=""
    COLOR=0xff98971a
elif [ "$PERCENT" -gt 50 ]; then
    ICON=""
    COLOR=0xffd79921
elif [ "$PERCENT" -gt 25 ]; then
    ICON=""
    COLOR=0xffd65d0e
else
    ICON=""
    COLOR=0xffcc241d
fi

sketchybar --set "$NAME" \
    icon="$ICON" \
    icon.color="$COLOR" \
    label="${PERCENT}%"
