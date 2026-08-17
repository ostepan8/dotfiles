#!/usr/bin/env bash
# with-timeout.sh — portable command timeout for macOS.
#
# macOS ships no timeout(1), and coreutils' gtimeout is not always installed,
# so any script that shells out to a daemon CLI needs its own guard.
#
# Why this matters more than it looks: when the caller is a launchd job,
# launchd will not fire the next StartInterval while the previous instance is
# still alive. So a single wedged daemon call doesn't just stall one run — it
# silently kills the entire schedule until someone notices by hand. That is
# exactly how a hung `aerospace reload-config` took dotfiles sync offline for
# two days.
#
# Note that `cmd 2>/dev/null || true` guards against a command *failing*. It
# does nothing whatsoever about a command that never returns.
#
# Usage:  with_timeout <seconds> <command> [args...]
# Returns the command's own exit status, or 124 on timeout (as timeout(1) does).

with_timeout() {
  local secs="$1"; shift
  [ "$#" -gt 0 ] || return 2

  "$@" &
  local cmd_pid=$!

  # Watchdog: wait out the budget, then escalate TERM -> KILL if still alive.
  (
    sleep "$secs"
    kill -0 "$cmd_pid" 2>/dev/null || exit 0
    kill -TERM "$cmd_pid" 2>/dev/null
    sleep 2
    kill -KILL "$cmd_pid" 2>/dev/null
  ) &
  local watch_pid=$!

  # Named cmd_status, not status: zsh makes $status a read-only alias for $?,
  # so `local status=` is a fatal error the moment this is sourced from zsh.
  local cmd_status=0
  wait "$cmd_pid" 2>/dev/null || cmd_status=$?

  # Command settled one way or the other — retire the watchdog so it can't
  # outlive this call and signal a recycled PID.
  kill -KILL "$watch_pid" 2>/dev/null
  wait "$watch_pid" 2>/dev/null || true

  # 143 = 128+SIGTERM, 137 = 128+SIGKILL: the watchdog fired. A command killed
  # by an outside signal is indistinguishable here, but for our callers (short
  # local daemon IPC) that is overwhelmingly a timeout, and both cases want the
  # same handling anyway.
  if [ "$cmd_status" -eq 143 ] || [ "$cmd_status" -eq 137 ]; then
    return 124
  fi
  return "$cmd_status"
}
