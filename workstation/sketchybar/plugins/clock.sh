#!/usr/bin/env bash
# Day + time, e.g. "Mon 4:54 PM". Rightmost item — mirrors the native menu-bar
# clock that sketchybar now covers (bar topmost=on).
sketchybar --set "$NAME" \
    icon.drawing=off \
    label="$(date '+%a %-I:%M %p')" \
    label.color=0xffebdbb2
