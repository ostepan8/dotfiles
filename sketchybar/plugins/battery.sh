#!/usr/bin/env bash
PERCENT=$(pmset -g batt | grep -Eo '[0-9]+%' | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')
if [ "$PERCENT" = "" ]; then
    sketchybar --set "$NAME" icon="BAT" icon.font="SF Pro:Bold:11.0" icon.color=0xff928374 label="--"
    exit 0
fi
if [ "$CHARGING" != "" ]; then COLOR=0xff98971a; LABEL_ICON="CHG"
elif [ "$PERCENT" -gt 75 ]; then COLOR=0xff98971a; LABEL_ICON="BAT"
elif [ "$PERCENT" -gt 25 ]; then COLOR=0xffd79921; LABEL_ICON="BAT"
else COLOR=0xffcc241d; LABEL_ICON="BAT"
fi
sketchybar --set "$NAME" icon="$LABEL_ICON" icon.font="SF Pro:Bold:11.0" icon.color="$COLOR" label="${PERCENT}%"
