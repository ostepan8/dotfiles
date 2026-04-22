#!/usr/bin/env bash
# CPU usage percentage (5-second average).

CPU=$(top -l 2 -n 0 -s 1 | grep "CPU usage" | tail -1 | awk -F': ' '{print $2}' | awk '{print int($1 + $3)}')

sketchybar --set "$NAME" icon="🔥" label="${CPU}%"
