#!/usr/bin/env bash
# Keep-awake indicator + toggle.
#
# The item used to answer "did I click this button?" while its label read AWAKE,
# which is a different question from "is this machine staying awake?" -- and on
# the Studio the two disagree permanently. Measured there: four caffeinate
# processes held PreventUserIdleSystemSleep (three spawned by Claude Code at
# `caffeinate -i -t 300`, one by a long-running Python job) and the item still
# read OFF, because none of them were the one it started. The machine had not
# slept in weeks.
#
# So state comes from pmset, which knows about every assertion regardless of who
# holds it. The toggle still owns only its own caffeinate, because that is all it
# can own -- you cannot un-assert someone else's. The two cases are coloured
# differently so the distinction is visible:
#
#   ON   green   this item is holding it awake; clicking turns it off
#   ON   amber   something else is (Claude, a job); clicking will NOT stop it
#   OFF  grey    nothing is preventing idle sleep
#
#   caffeine.sh          → render only
#   caffeine.sh toggle   → flip our own caffeinate, then render
PIDFILE="$HOME/.cache/sketchybar-caffeinate.pid"
mkdir -p "$HOME/.cache"

ours_awake() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

# Any holder, ours or not. The summary line is "PreventUserIdleSystemSleep  1".
system_awake() {
    [ "$(pmset -g assertions 2>/dev/null \
        | awk '/^ *PreventUserIdleSystemSleep/ {print $2; exit}')" = "1" ]
}

if [ "${1:-}" = "toggle" ]; then
    if ours_awake; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$PIDFILE"
    else
        # nohup+& detaches caffeinate so it outlives this script; $! is its PID.
        nohup caffeinate -di >/dev/null 2>&1 &
        echo $! > "$PIDFILE"
    fi
fi

if ours_awake;      then COLOR=0xff98971a; LABEL="ON"
elif system_awake;  then COLOR=0xffd79921; LABEL="ON"
else                     COLOR=0xff928374; LABEL="OFF"
fi

sketchybar --set "$NAME" \
    icon="AWAKE" icon.font="SF Pro:Bold:11.0" icon.color="$COLOR" \
    label="$LABEL" label.color="$COLOR"
