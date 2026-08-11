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
TOML="$SCRIPT_DIR/aerospace.toml"
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
    # grep -c prints "0" and exits 1 when there are no externals; `|| true`
    # swallows the non-zero exit WITHOUT emitting a second "0" (the old
    # `|| echo 0` produced "0\n0", which broke the notify `case` below).
    "$AERO" list-monitors 2>/dev/null \
        | awk -F'|' '{print $2}' \
        | grep -ivc "built-in\|built in" \
        || true
}

# Names of the external monitors attached right now (built-in excluded).
present_externals() {
    "$AERO" list-monitors 2>/dev/null \
        | awk -F'|' '{print $2}' \
        | sed 's/^ *//;s/ *$//' \
        | grep -iv "built-in\|built in"
}

# Level-triggered health check: is the [workspace-to-monitor-force-assignment]
# block CONSISTENT with the monitors attached right now? This is what makes the
# watcher self-healing — it catches the case where a reconcile ran mid-plug and
# wrote a stale/empty block that the edge-triggered logic would never revisit.
#   0 externals -> block must have NO 9/10 pins
#   >=1 external -> 9 and 10 must be pinned to an external that is present now
# Returns 0 (matches) or 1 (drifted). Errs toward "matches" if aerospace/TOML
# can't be read, so a transient read failure never triggers a spurious rewrite.
block_matches_monitors() {
    [ -r "$TOML" ] || return 0
    local ext; ext="$(count_externals)"
    if [ "${ext:-0}" -eq 0 ]; then
        # No external attached -> there must be no 9/10 pins.
        grep -qE '^(9|10)[[:space:]]*=' "$TOML" && return 1
        return 0
    fi
    # At least one external: 9 and 10 must both be pinned...
    grep -qE '^9[[:space:]]*='  "$TOML" || return 1
    grep -qE '^10[[:space:]]*=' "$TOML" || return 1
    # ...and to a monitor name that is actually connected right now.
    local name9
    name9="$(awk -F"'" '/^9[[:space:]]*=/{gsub(/^\^|\$$/,"",$2); print $2; exit}' "$TOML")"
    [ -n "$name9" ] || return 1
    present_externals | grep -qxF "$name9"
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

# Debounce: ripping out (or hot-plugging) several displays produces a burst
# of intermediate fingerprints. Acting on the first one runs set-main-display
# while macOS is still mid-reconfigure — displayplacer then reports no enabled
# displays and the script bails WITHOUT restarting the bar, leaving sketchybar
# stuck/hidden until the next plug event. So once we see a change, we wait for
# the layout to hold steady for SETTLE_READS consecutive polls before acting.
SETTLE_READS="${SETTLE_READS:-2}"
SETTLE_POLL="${SETTLE_POLL:-1}"
SETTLE_MAX="${SETTLE_MAX:-30}"  # hard cap so we can never loop forever

settle_fingerprint() {
    # Echoes the fingerprint only once it has been stable (and non-empty)
    # for SETTLE_READS consecutive reads. Echoes nothing if it never settles
    # within SETTLE_MAX iterations.
    local stable=0 settled="$1" cur i
    for (( i = 0; i < SETTLE_MAX; i++ )); do
        sleep "$SETTLE_POLL"
        cur="$(monitor_fingerprint)"
        if [ -n "$cur" ] && [ "$cur" = "$settled" ]; then
            stable=$((stable + 1))
            [ "$stable" -ge "$SETTLE_READS" ] && { printf '%s' "$settled"; return 0; }
        else
            stable=0
            settled="$cur"
        fi
    done
    printf '%s' "$settled"  # best effort after the cap
}

# Run set-main-display.sh auto, then FORCE an aerospace reload. The forced
# reload matters: set-main-display skips its OWN reload when it believes nothing
# changed — the exact stuck state that leaves 9/10 pinned to the laptop. quiet=1
# suppresses the desktop notification (used for silent background self-heals).
do_reconcile() {
    local ext="$1" quiet="$2"
    if "$SET_MAIN" auto 2>&1; then
        "$AERO" reload-config >/dev/null 2>&1 || true
        if [ -z "$quiet" ]; then
            case "$ext" in
                0) MSG="Laptop-only — pins refreshed." ;;
                1) MSG="1 external attached — pins refreshed." ;;
                *) MSG="$ext externals attached — pins refreshed." ;;
            esac
            notify "Aerospace: monitor layout" "$MSG"
        fi
        return 0
    fi
    log "set-main-display.sh auto failed; will retry on next tick"
    return 1
}

PREV_FP=""
last_reconcile=0
DRIFT_MIN_INTERVAL="${DRIFT_MIN_INTERVAL:-8}"

while true; do
    FP="$(monitor_fingerprint)"

    if [ -n "$FP" ]; then
        if [ "$FP" != "$PREV_FP" ]; then
            # EDGE: the monitor set changed. Let it settle, then reconcile.
            FP="$(settle_fingerprint "$FP")"
            if [ -z "$FP" ]; then
                log "layout never settled on a real monitor set — retrying next tick"
                sleep "$POLL_SECONDS"
                continue
            fi
            EXT="$(count_externals)"
            FIRST_ITER=""
            [ -z "$PREV_FP" ] && FIRST_ITER=1   # quiet on the first pass after (re)start
            log "layout fingerprint changed (externals=$EXT) — reconciling"
            do_reconcile "$EXT" "$FIRST_ITER"
            PREV_FP="$FP"
            last_reconcile="$(date +%s)"

        elif ! block_matches_monitors; then
            # LEVEL / self-heal: the monitor set is STABLE but the config has
            # drifted from reality (e.g. an earlier reconcile ran mid-plug and
            # wrote an empty block). Fix it silently, with a short backoff so a
            # persistently-failing reconcile can never hot-loop every tick.
            now="$(date +%s)"
            if [ "$(( now - last_reconcile ))" -ge "$DRIFT_MIN_INTERVAL" ]; then
                EXT="$(count_externals)"
                log "config drifted from monitors (externals=$EXT) — self-healing"
                do_reconcile "$EXT" 1
                last_reconcile="$now"
            fi
        fi
    fi

    sleep "$POLL_SECONDS"
done
