#!/usr/bin/env bash
# nephos fleet state: jobs running and queued on the self-hosted cloud.
#
# Every external call in this bar is bounded, on purpose. An unbounded
# `aerospace list-workspaces` that blocked forever is what left the bar empty
# for three weeks -- it never failed, it just never returned, and took the whole
# config with it. The control plane lives across a tailnet, so it can go away
# mid-call in exactly the same way. There is no timeout(1) on macOS, hence the
# hand-rolled guard.
run_bounded() {
    local secs="$1" out="$2"; shift 2
    "$@" >"$out" 2>/dev/null &
    local pid=$! i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( i + 1 ))
        if [ "$i" -ge $(( secs * 10 )) ]; then kill -9 "$pid" 2>/dev/null; return 1; fi
        sleep 0.1
    done
    wait "$pid" 2>/dev/null
}

# The launch agent's PATH is /opt/homebrew/{bin,sbin} plus the system dirs -- it
# does NOT include ~/.local/bin, which is where the nephos binary actually lives.
# Without this the plugin silently reported an unreachable control plane when the
# CLI was simply not on the path it was looking down.
PATH="$HOME/.local/bin:$PATH"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if ! command -v nephos >/dev/null 2>&1 || ! run_bounded 4 "$TMP" nephos jobs --json; then
    # Control plane unreachable is a normal state (laptop off the tailnet), not
    # an error worth shouting about -- go grey rather than red.
    sketchybar --set "$NAME" \
        icon="FLEET" icon.color=0xff928374 icon.font="SF Pro:Bold:11.0" \
        label="--"
    exit 0
fi

read -r RUNNING QUEUED FAILED <<<"$(python3 -c '
import json, sys, datetime

try:
    rows = json.load(open(sys.argv[1])) or []
except Exception:
    print("0 0 0"); raise SystemExit
if isinstance(rows, dict):
    rows = rows.get("jobs", [])

states = [r.get("state") for r in rows]

# Count JOB NAMES whose most recent run failed -- not every failure in the
# window. A job that failed at 07:00 and succeeded at 09:00 is not broken, and
# counting the old failure would keep the bar red over something already fixed.
# Still bounded to 24h so a name that has not run since yesterday stops counting
# rather than accusing the fleet forever.
cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=24)


def when(r):
    return r.get("finishedAt") or r.get("submittedAt") or ""


latest = {}
for r in rows:
    if r.get("state") not in ("succeeded", "failed"):
        continue
    ts = when(r)
    if not ts:
        continue
    try:
        parsed = datetime.datetime.fromisoformat(ts)
    except ValueError:
        continue
    if parsed < cutoff:
        continue
    name = r.get("name")
    if name not in latest or parsed > latest[name][0]:
        latest[name] = (parsed, r.get("state"))

recent = sum(1 for _, state in latest.values() if state == "failed")

print(states.count("running"), states.count("queued"), recent)
' "$TMP")"

RUNNING="${RUNNING:-0}"; QUEUED="${QUEUED:-0}"; FAILED="${FAILED:-0}"

# A recent failure outranks everything else. "2 running" is not the headline when
# something died an hour ago -- and that was this item's blind spot on the day it
# shipped: it read "idle" while the only scheduled job on the fleet had failed
# its last run, with nothing anywhere saying so.
if   [ "$FAILED"  -gt 0 ]; then COLOR=0xffcc241d; LABEL="${FAILED} failed"
elif [ "$RUNNING" -gt 0 ] && [ "$QUEUED" -gt 0 ]; then COLOR=0xff98971a; LABEL="${RUNNING} run·${QUEUED} q"
elif [ "$RUNNING" -gt 0 ]; then COLOR=0xff98971a; LABEL="${RUNNING} run"
elif [ "$QUEUED"  -gt 0 ]; then COLOR=0xffd79921; LABEL="${QUEUED} q"
else                            COLOR=0xff928374; LABEL="idle"
fi

sketchybar --set "$NAME" \
    icon="FLEET" icon.color="$COLOR" icon.font="SF Pro:Bold:11.0" \
    label="$LABEL"
