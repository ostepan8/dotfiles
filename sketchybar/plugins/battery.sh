#!/usr/bin/env bash
# Battery percentage + charging state.

PERCENT=$(pmset -g batt | grep -Eo '[0-9]+%' | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENT" = "" ]; then
    sketchybar --set "$NAME" icon="🔌" label="--"
    exit 0
fi

if [ "$CHARGING" != "" ]; then
    ICON="⚡"
elif [ "$PERCENT" -gt 75 ]; then
    ICON="🔋"
elif [ "$PERCENT" -gt 50 ]; then
    ICON="🔋"
elif [ "$PERCENT" -gt 25 ]; then
    ICON="🪫"
else
    ICON="🪫"
fi

sketchybar --set "$NAME" \
    icon="$ICON" \
    label="${PERCENT}%"
