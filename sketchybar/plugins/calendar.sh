#!/usr/bin/env bash
# Next upcoming macOS-Calendar event via icalBuddy, with a countdown.
# Hidden entirely when nothing is coming up (or icalBuddy isn't installed).
#
# NOTE: icalBuddy reads the macOS Calendar database only. Google/Exchange
# events show up here ONLY if that account is added under System Settings →
# Internet Accounts (so it syncs into Calendar.app). sketchybar also needs
# Calendar access granted (System Settings → Privacy & Security → Calendars).
# Click opens Calendar.app.

command -v icalBuddy >/dev/null 2>&1 || { sketchybar --set "$NAME" drawing=off; exit 0; }

# Future events only (-n), today + tomorrow, just the first one, time + title.
RAW=$(icalBuddy -n -nc -b "" -df "" -tf "%H:%M" -li 1 \
        -iep "datetime,title" -eep "notes,location,url,attendees" \
        eventsToday+1 2>/dev/null)

# Flatten to one line and normalize whitespace — icalBuddy's exact layout
# varies by version, so parse heuristically: first HH:MM token is the start
# time, everything else is the title.
FLAT=$(printf '%s' "$RAW" | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
if [ -z "$FLAT" ]; then
    sketchybar --set "$NAME" drawing=off
    exit 0
fi

TIME=$(printf '%s' "$FLAT" | grep -Eo '[0-9]{1,2}:[0-9]{2}' | head -1)
TITLE=$(printf '%s' "$FLAT" | sed -E 's/[0-9]{1,2}:[0-9]{2}//g; s/^[[:space:]-]*//; s/[[:space:]]*$//')
[ -z "$TITLE" ] && TITLE="(busy)"
[ "${#TITLE}" -gt 24 ] && TITLE="${TITLE:0:21}..."

# Countdown from the start time (assumes today; harmless if it's tomorrow —
# we simply omit the countdown when it doesn't compute cleanly).
COUNT=""
COLOR=0xff689d6a
if [ -n "$TIME" ]; then
    NOW=$(date +%s)
    EVT=$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) $TIME" +%s 2>/dev/null)
    if [ -n "$EVT" ]; then
        MINS=$(( (EVT - NOW) / 60 ))
        if [ "$MINS" -ge 0 ] && [ "$MINS" -lt 1440 ]; then
            if   [ "$MINS" -lt 60 ]; then COUNT="${MINS}m"
            else COUNT="$(( MINS / 60 ))h$(( MINS % 60 ))m"
            fi
            [ "$MINS" -lt 5 ] && COLOR=0xffcc241d   # red when imminent
        fi
    fi
fi

if [ -n "$COUNT" ]; then LABEL="$TITLE · $COUNT"; else LABEL="$TITLE · $TIME"; fi

sketchybar --set "$NAME" \
    icon="CAL" icon.font="SF Pro:Bold:11.0" icon.color=0xff689d6a \
    label="$LABEL" label.color="$COLOR" drawing=on
