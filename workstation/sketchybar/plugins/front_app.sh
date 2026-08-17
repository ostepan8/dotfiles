#!/usr/bin/env bash
# Shows the frontmost app name.

if [ "$SENDER" = "front_app_switched" ]; then
    sketchybar --set "$NAME" label="$INFO"
fi
