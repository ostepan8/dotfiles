#!/bin/bash
# Detect and clear phantom windows in AeroSpace.
#
# Bug: when an app process dies (e.g. Ghostty crash, force-quit), AeroSpace
# can fail to GC its window from the tiling tree. Phantom windows shrink
# every other window in the workspace — a "new" terminal on a "blank"
# workspace ends up at 1/N of the screen.
#
# This script scans every tracked window's PID. If the PID is gone from
# the OS process table, AeroSpace is holding a phantom and we restart it
# to rebuild a clean window tree.

set -euo pipefail

LOG=/tmp/aerospace-cleanup.log
ts() { date '+%Y-%m-%d %H:%M:%S'; }

if ! command -v aerospace >/dev/null 2>&1; then
  echo "$(ts) aerospace CLI not found, exiting" >>"$LOG"
  exit 0
fi

if ! pgrep -x AeroSpace >/dev/null 2>&1; then
  echo "$(ts) AeroSpace not running, exiting" >>"$LOG"
  exit 0
fi

phantoms=0
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  if ! kill -0 "$pid" 2>/dev/null; then
    phantoms=$((phantoms + 1))
  fi
done < <(aerospace list-windows --all --format '%{app-pid}' 2>/dev/null | sort -u)

if [ "$phantoms" -eq 0 ]; then
  exit 0
fi

echo "$(ts) detected $phantoms phantom PID(s), restarting AeroSpace" >>"$LOG"

# Snapshot the focused workspace so we can restore focus after restart.
focused_ws=$(aerospace list-workspaces --focused 2>/dev/null || echo "")

pkill -x AeroSpace || true

# Wait for the process to actually exit before relaunching.
for _ in $(seq 1 20); do
  pgrep -x AeroSpace >/dev/null 2>&1 || break
  sleep 0.1
done

open -a AeroSpace

# Wait for AeroSpace to come back up before issuing commands.
for _ in $(seq 1 30); do
  if aerospace list-workspaces --focused >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

if [ -n "$focused_ws" ]; then
  aerospace workspace "$focused_ws" 2>/dev/null || true
fi

echo "$(ts) restart complete" >>"$LOG"
