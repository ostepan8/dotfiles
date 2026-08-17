#!/usr/bin/env bash
# Highlights the current Aerospace workspace; hides empty unfocused ones.
# Called by sketchybar with $NAME = "space.<id>" and $1 = the workspace id.

BG1=0xff3c3836
ORANGE=0xffd65d0e
FG=0xffebdbb2
BLACK=0xff1d2021

FOCUSED=$(aerospace list-workspaces --focused)
WINDOW_COUNT=$(aerospace list-windows --workspace "$1" 2>/dev/null | wc -l | tr -d ' ')

if [ "$1" = "$FOCUSED" ]; then
    sketchybar --set "$NAME" \
        drawing=on \
        background.color="$ORANGE" \
        label.color="$BLACK"
elif [ "$WINDOW_COUNT" -gt 0 ]; then
    sketchybar --set "$NAME" \
        drawing=on \
        background.color="$BG1" \
        label.color="$FG"
else
    sketchybar --set "$NAME" drawing=off
fi
