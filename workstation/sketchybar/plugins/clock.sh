#!/usr/bin/env bash
# Full date + time, e.g. "Sun Sep 13  11:50 PM". Rightmost item — mirrors the
# native menu-bar clock that sketchybar now covers (bar topmost=on), which is
# why it carries the whole date rather than just the weekday: with the menu bar
# hidden there is nowhere else to read it.
sketchybar --set "$NAME" \
    icon.drawing=off \
    label="$(date '+%a %b %-d  %-I:%M %p')" \
    label.color=0xffebdbb2
