#!/usr/bin/env bash
# Battery percentage + charging state (SF Symbols battery icons).

PERCENT=$(pmset -g batt | grep -Eo '[0-9]+%' | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENT" = "" ]; then
    sketchybar --set "$NAME" icon="􀋦" icon.color=0xff928374 label="--"
    exit 0
fi

if [ "$CHARGING" != "" ]; then
    ICON="􀢋"             # battery.100.bolt
    COLOR=0xff98971a
elif [ "$PERCENT" -gt 75 ]; then
    ICON="􀛨"             # battery.100
    COLOR=0xffebdbb2
elif [ "$PERCENT" -gt 50 ]; then
    ICON="􀺶"             # battery.75
    COLOR=0xffebdbb2
elif [ "$PERCENT" -gt 25 ]; then
    ICON="􀛩"             # battery.50
    COLOR=0xffd79921
elif [ "$PERCENT" -gt 10 ]; then
    ICON="􀛪"             # battery.25
    COLOR=0xffd65d0e
else
    ICON="􀛫"             # battery.0
    COLOR=0xffcc241d
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="${PERCENT}%"
