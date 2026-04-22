#!/usr/bin/env bash
# CPU usage percentage (5-second average).

CPU=$(top -l 2 -n 0 -s 1 | grep "CPU usage" | tail -1 | awk -F': ' '{print $2}' | awk '{print int($1 + $3)}')

# Color-code by load
if [ "$CPU" -gt 70 ]; then
    COLOR=0xffcc241d
elif [ "$CPU" -gt 40 ]; then
    COLOR=0xffd79921
else
    COLOR=0xff689d6a
fi

sketchybar --set "$NAME" icon="􀫥" icon.color="$COLOR" label="${CPU}%"
