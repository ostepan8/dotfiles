#!/bin/bash
# Surgically drop phantom windows from AeroSpace's tiling tree.
#
# Two classes of phantoms:
#   1. Dead-PID phantoms: app process is gone but AeroSpace still tracks
#      the windows. Detected by `kill -0 <pid>`.
#   2. Stale-window phantoms: app process is alive but the specific window
#      was closed without notifying AeroSpace. macOS Accessibility's
#      kAXUIElementDestroyedNotification is unreliable (esp. on macOS 15+),
#      so AeroSpace keeps the dead window in the tiling tree, shrinking
#      every other tile in the workspace. Detected by asking each PID
#      directly via the AX API how many windows it really has.
#
# Tracking issue: https://github.com/nikitabobko/AeroSpace/issues/1615
#
# Fix for both: `aerospace close --window-id <N>`. This drops the phantom
# from the tree without disturbing any live window or workspace mapping.
# Much less destructive than restarting AeroSpace (which loses every
# window-to-workspace mapping).

set -euo pipefail

LOG=/tmp/aerospace-cleanup.log
HELPER=~/.config/aerospace/list-real-windows
HELPER_SRC=~/.config/aerospace/list-real-windows.swift
ts() { date '+%Y-%m-%d %H:%M:%S'; }

if ! command -v aerospace >/dev/null 2>&1; then
  echo "$(ts) aerospace CLI not found, exiting" >>"$LOG"
  exit 0
fi

# Probe the AeroSpace server via its own CLI rather than pgrep — pgrep
# can briefly return empty during config reloads even though the daemon
# is alive, leading to spurious "not running" log spam. If the CLI gets
# a real response, the server is up.
if ! aerospace list-workspaces --focused >/dev/null 2>&1; then
  echo "$(ts) AeroSpace server not responding, exiting" >>"$LOG"
  exit 0
fi

# Always log invocation start so a hotkey press leaves a visible trace
# even when no phantoms exist.
echo "$(ts) running" >>"$LOG"

# Lazy-compile the AX-window-count helper if missing or out-of-date.
if [ ! -x "$HELPER" ] || [ "$HELPER_SRC" -nt "$HELPER" ]; then
  if command -v swiftc >/dev/null 2>&1 && [ -f "$HELPER_SRC" ]; then
    swiftc -O "$HELPER_SRC" -o "$HELPER" 2>>"$LOG" \
      && echo "$(ts) compiled $HELPER" >>"$LOG"
  fi
fi

# Snapshot AeroSpace's view: window-id <TAB> pid <TAB> app <TAB> title.
ae_snapshot=$(mktemp -t aerospace-cleanup-ae-XXXXXX) || exit 0
trap 'rm -f "$ae_snapshot" "$real_snapshot"' EXIT
real_snapshot=$(mktemp -t aerospace-cleanup-real-XXXXXX) || exit 0
aerospace list-windows --all --format '%{window-id}	%{app-pid}	%{app-name}	%{window-title}' \
  >"$ae_snapshot" 2>/dev/null || true

# Snapshot AX truth: pid <TAB> app <TAB> ax_window_count.
# Empty file if helper isn't available — script then runs in PID-only mode.
if [ -x "$HELPER" ]; then
  "$HELPER" >"$real_snapshot" 2>/dev/null || true
else
  : >"$real_snapshot"
fi

closed=0
failed=0

# --- Pass 1: dead-PID phantoms (entire window destroyed because process gone)
while IFS=$'\t' read -r wid pid app title; do
  [ -z "$wid" ] && continue
  [ -z "$pid" ] && continue
  if kill -0 "$pid" 2>/dev/null; then continue; fi
  if aerospace close --window-id "$wid" >/dev/null 2>&1; then
    closed=$((closed + 1))
    echo "$(ts) closed dead-pid phantom wid=$wid pid=$pid app=$app" >>"$LOG"
  else
    failed=$((failed + 1))
    echo "$(ts) FAILED to close wid=$wid pid=$pid app=$app" >>"$LOG"
  fi
done <"$ae_snapshot"

# --- Pass 2: stale-window phantoms (process alive, window invisible).
# AX snapshot is per-window: pid app title minimized hidden width height.
# A window is "visible" iff minimized=0, hidden=0, and size is non-trivial.
# If AeroSpace tracks more windows for a PID than AX considers visible,
# the excess are phantoms — gone, minimized, hidden behind Cmd+H, or
# zero-sized — but AeroSpace is still allocating tile space for them.
# Prefer to close empty-title rows first; a real, visible window almost
# always has a title.
if [ -s "$real_snapshot" ]; then
  excess_per_pid=$(awk -F'\t' '
    NR==FNR {
      pid=$1; min=$4; hid=$5; w=$6; h=$7
      if (min==0 && hid==0 && w > 100 && h > 100) ax_visible[pid]++
      seen[pid]=1
      next
    }
    seen[$2] { ae[$2]++ }
    END {
      for (pid in seen) {
        diff = ae[pid] - ax_visible[pid]
        if (diff > 0) print pid"\t"diff
      }
    }
  ' "$real_snapshot" "$ae_snapshot")

  if [ -n "$excess_per_pid" ]; then
    while IFS=$'\t' read -r target_pid excess; do
      [ -z "$target_pid" ] && continue
      [ -z "$excess" ] && continue
      # Pull AeroSpace rows for this PID, sort empty-title-first, take $excess.
      awk -F'\t' -v p="$target_pid" '$2==p { print ($4=="" ? 0 : 1)"\t"$1"\t"$3"\t"$4 }' \
        "$ae_snapshot" \
        | sort -n -k1,1 -s \
        | head -n "$excess" \
        | while IFS=$'\t' read -r emptyflag wid app title; do
            if aerospace close --window-id "$wid" >/dev/null 2>&1; then
              closed=$((closed + 1))
              echo "$(ts) closed stale-window phantom wid=$wid pid=$target_pid app=$app title='$title'" >>"$LOG"
            else
              failed=$((failed + 1))
              echo "$(ts) FAILED to close wid=$wid pid=$target_pid app=$app" >>"$LOG"
            fi
          done
    done <<<"$excess_per_pid"
  fi
fi

echo "$(ts) summary: closed=$closed failed=$failed" >>"$LOG"
