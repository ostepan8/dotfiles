#!/bin/bash
# Surgically drop phantom windows from AeroSpace's tiling tree.
#
# Bug: AeroSpace 0.20.x relies on the macOS Accessibility
# kAXUIElementDestroyedNotification to GC closed windows. The notification
# is unreliable (more so on macOS 15+) — when an app process dies abruptly
# (Ghostty force-quit, crash, hung Mail.app, etc.), the dead window stays
# in the tiling tree forever. Each phantom shrinks every other tile in the
# workspace, so a "new" terminal on a "blank" workspace ends up at 1/N.
# Tracking issue: https://github.com/nikitabobko/AeroSpace/issues/1615
#
# Fix: for every tracked window whose backing PID no longer exists in the
# OS process table, call `aerospace close --window-id <N>`. This drops the
# phantom from the tree without disturbing any live window or workspace
# assignment — much less destructive than restarting AeroSpace (which
# loses every window-to-workspace mapping).

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

# Snapshot tracked windows once, then probe PIDs locally. Portable across
# macOS's stock bash 3.2 (no `mapfile`) — read a temp file line by line.
snapshot=$(mktemp -t aerospace-cleanup-XXXXXX) || exit 0
trap 'rm -f "$snapshot"' EXIT
aerospace list-windows --all --format '%{window-id} %{app-pid} %{app-name}' >"$snapshot" 2>/dev/null || true

closed=0
failed=0
while IFS= read -r row; do
  [ -z "$row" ] && continue
  wid=$(awk '{print $1}' <<<"$row")
  pid=$(awk '{print $2}' <<<"$row")
  app=$(cut -d' ' -f3- <<<"$row")
  [ -z "$wid" ] && continue
  [ -z "$pid" ] && continue
  if kill -0 "$pid" 2>/dev/null; then
    continue
  fi
  if aerospace close --window-id "$wid" >/dev/null 2>&1; then
    closed=$((closed + 1))
    echo "$(ts) closed phantom window-id=$wid pid=$pid app=$app" >>"$LOG"
  else
    failed=$((failed + 1))
    echo "$(ts) FAILED to close window-id=$wid pid=$pid app=$app" >>"$LOG"
  fi
done <"$snapshot"

if [ "$closed" -gt 0 ] || [ "$failed" -gt 0 ]; then
  echo "$(ts) summary: closed=$closed failed=$failed" >>"$LOG"
fi
