#!/usr/bin/env bash
# Currently playing Spotify track. Hidden when not running or paused.

IS_RUNNING=$(osascript -e 'application "Spotify" is running' 2>/dev/null)

if [ "$IS_RUNNING" != "true" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

STATE=$(osascript -e 'tell application "Spotify" to player state as string' 2>/dev/null)

if [ "$STATE" != "playing" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

TRACK=$(osascript -e 'tell application "Spotify" to name of current track as string' 2>/dev/null)
ARTIST=$(osascript -e 'tell application "Spotify" to artist of current track as string' 2>/dev/null)

COMBINED="$ARTIST — $TRACK"
if [ "${#COMBINED}" -gt 42 ]; then
    COMBINED="${COMBINED:0:39}..."
fi

sketchybar --set "$NAME" \
    drawing=on \
    icon="􀑪" \
    icon.color=0xff98971a \
    label="$COMBINED"
