#!/usr/bin/env bash
# Highlights the current Aerospace workspace.
# Called by sketchybar with $NAME = "space.<id>" and $1 = the workspace id.

BG1=0xff3c3836
ORANGE=0xffd65d0e
FG=0xffebdbb2
BLACK=0xff1d2021

FOCUSED=$(aerospace list-workspaces --focused)

if [ "$1" = "$FOCUSED" ]; then
    sketchybar --set "$NAME" \
        background.color="$ORANGE" \
        label.color="$BLACK"
else
    sketchybar --set "$NAME" \
        background.color="$BG1" \
        label.color="$FG"
fi
