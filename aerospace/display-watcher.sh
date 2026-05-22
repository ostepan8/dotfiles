#!/usr/bin/env bash
# Poll the connected-monitor set and run set-main-display.sh auto whenever it
# changes. Replaces the earlier CGDisplayRegisterReconfigurationCallback Swift
# watcher, which silently missed plug events when launched from launchd (CG
# display callbacks are unreliable from a non-foreground launchd context).
#
# This loop is the source of truth for "the monitor layout changed, reconcile
# aerospace.toml + sketchybar." Polling cost is one `aerospace list-monitors`
# call every POLL_SECONDS — well under 0.1% CPU.
#
# Lifecycle: started by the com.ostepan.display-watcher LaunchAgent with
# KeepAlive=true. The loop runs forever; only launchctl unload stops it.

set -u  # `-e` would kill the watcher on the first transient aerospace error

AERO=/opt/homebrew/bin/aerospace
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_MAIN="$SCRIPT_DIR/set-main-display.sh"
POLL_SECONDS="${POLL_SECONDS:-3}"

# Sleep briefly at boot so we don't race aerospace coming up.
sleep 2

# Returns a deterministic fingerprint of the connected-monitor *set* — just
# the names, sorted. We deliberately do NOT hash origins or "which one is
# main": those change every time the user presses ctrl-alt-[/]/\ to swap
# the main display, and reacting to them caused this watcher to fight the
# user (it would fire `set-main-display.sh auto` immediately after a
# manual swap, picking a different display and undoing the change).
#
# Trade-off: this means dragging the white bar in System Settings does
# NOT trigger an aerospace.toml reconcile. If you do that manually, press
# ctrl-alt-[/]/\ (or run `set-main-display.sh auto` directly) to refresh
# gaps and pins. Plug/unplug — the primary use case — still fires.
monitor_fingerprint() {
    "$AERO" list-monitors 2>/dev/null \
        | awk -F'|' '{print $2}' \
        | sed 's/^ *//;s/ *$//' \
        | sort \
        | shasum -a 1 \
        | awk '{print $1}'
}

count_externals() {
    "$AERO" list-monitors 2>/dev/null \
        | awk -F'|' '{print $2}' \
        | grep -ivc "built-in\|built in" \
        || echo 0
}

notify() {
    local title="$1"
    local body="$2"
    # `display notification` will silently no-op if osascript isn't permitted,
    # which is fine — the layout reconcile still happened.
    /usr/bin/osascript -e "display notification \"$body\" with title \"$title\"" \
        >/dev/null 2>&1 || true
}

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

PREV_FP=""

while true; do
    FP="$(monitor_fingerprint)"

    if [ -n "$FP" ] && [ "$FP" != "$PREV_FP" ]; then
        EXT="$(count_externals)"
        FIRST_ITER=""
        [ -z "$PREV_FP" ] && FIRST_ITER=1

        log "layout fingerprint changed (externals=$EXT) — running set-main-display.sh auto"
        if "$SET_MAIN" auto 2>&1; then
            if [ -z "$FIRST_ITER" ]; then
                # Skip the very first iteration after watcher (re)start — it
                # would notify on every login, which is noisy.
                # `auto` respects the current main display, so the bar
                # only moves if macOS itself flipped it (e.g. unplugging
                # the current main). Messages reflect that.
                case "$EXT" in
                    0) MSG="Laptop-only — pins refreshed." ;;
                    1) MSG="1 external attached — pins refreshed." ;;
                    *) MSG="$EXT externals attached — pins refreshed." ;;
                esac
                notify "Aerospace: monitor layout" "$MSG"
            fi
        else
            log "set-main-display.sh auto failed; will retry on next tick"
        fi
        PREV_FP="$FP"
    fi

    sleep "$POLL_SECONDS"
done
