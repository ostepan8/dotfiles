#!/usr/bin/env bash
# Date + time, updated every 10 seconds.

sketchybar --set "$NAME" icon.font="SF Pro:Bold:11.0" label="$(date '+%a %b %d  %H:%M')"
