#!/usr/bin/env bash
# Battery percentage + charge state, colored by level (mirrors the covered
# native menu-bar battery). "+" suffix means plugged in / charging.
INFO=$(pmset -g batt 2>/dev/null)
PCT=$(printf '%s' "$INFO" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
[ -z "$PCT" ] && exit 0

if   [ "$PCT" -le 20 ]; then COLOR=0xffcc241d   # red
elif [ "$PCT" -le 40 ]; then COLOR=0xffd79921   # yellow
else COLOR=0xff689d6a                           # green
fi

# "AC Power" in pmset means plugged in.
printf '%s' "$INFO" | grep -q "AC Power" && SUFFIX="+" || SUFFIX=""

sketchybar --set "$NAME" \
    icon="BAT" icon.font="SF Pro:Bold:11.0" icon.color="$COLOR" \
    label="${PCT}%${SUFFIX}"
