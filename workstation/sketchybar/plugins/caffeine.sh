#!/usr/bin/env bash
# Keep-awake toggle. Runs `caffeinate -di` (blocks display + idle sleep) while
# active. Click flips it; periodic/manual runs just re-render current state.
#   caffeine.sh          → render only
#   caffeine.sh toggle   → flip on/off, then render (wired to click_script)

PIDFILE="$HOME/.cache/sketchybar-caffeinate.pid"
mkdir -p "$HOME/.cache"

is_awake() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

if [ "${1:-}" = "toggle" ]; then
    if is_awake; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$PIDFILE"
    else
        # nohup+& detaches caffeinate so it outlives this script; $! is its PID.
        nohup caffeinate -di >/dev/null 2>&1 &
        echo $! > "$PIDFILE"
    fi
fi

if is_awake; then
    sketchybar --set "$NAME" icon="AWAKE" icon.font="SF Pro:Bold:11.0" \
        icon.color=0xff98971a label="ON"  label.color=0xff98971a
else
    sketchybar --set "$NAME" icon="AWAKE" icon.font="SF Pro:Bold:11.0" \
        icon.color=0xff928374 label="OFF" label.color=0xff928374
fi
