#!/usr/bin/env bash
# reloads.sh — change detection and service hot-reloads.
#
# Ported from mac/apply.sh rather than rewritten. Three details here are
# load-bearing and were each fixed in response to a real bug; they are preserved
# exactly. See the comments at each site before changing anything.

# with-timeout.sh still lives under mac/lib in Phase 1; it moves to lib/ in
# Phase 3, at which point this falls through to the second path.
for _wt in "$DOTFILES/mac/lib/with-timeout.sh" "$DOTFILES/lib/with-timeout.sh"; do
  [ -f "$_wt" ] && { . "$_wt"; break; }
done
unset _wt

# Budget for a single service hot-reload: local IPC round-trips that finish well
# under a second when healthy.
RELOAD_TIMEOUT=${RELOAD_TIMEOUT:-10}

# set-main-display.sh is not a simple IPC ping — it rewrites aerospace.toml,
# reloads aerospace, restarts sketchybar and polls for the bar to come back — so
# it gets a larger budget.
DISPLAY_RECONCILE_TIMEOUT=${DISPLAY_RECONCILE_TIMEOUT:-60}

# Per-source change detection. Copying files is cheap; *reloading services* is
# disruptive — it was flashing the top bar and re-firing the display-watcher on
# every 30-minute tick even when nothing had changed. `changed <tag> <file...>`
# is true only when a source's content hash has moved since the last apply.
# State is per-machine and untracked, so each machine detects its own pulls.
APPLY_STATE="${APPLY_STATE:-$HOME/.config/.dotfiles-apply}"

changed() {
  local tag="$1"; shift
  local sha store prev
  sha="$(cat "$@" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  # Tags become filenames, and some carry a path (copy:/Users/...). Flatten them
  # or the store path lands in a directory that does not exist, the write fails
  # silently, and the tag then looks changed on EVERY run — which for a `copy`
  # row means reverting the machine's live file on every 30-minute tick.
  store="$APPLY_STATE/$(printf '%s' "$tag" | tr '/:' '__').sha"
  prev="$(cat "$store" 2>/dev/null || true)"
  [ "$sha" = "$prev" ] && return 1
  [ "${DRY_RUN:-0}" = "1" ] || { mkdir -p "$APPLY_STATE"; printf '%s\n' "$sha" > "$store"; }
  return 0
}

_run_guarded() {
  local name="$1" budget="$2"; shift 2
  local rc=0
  with_timeout "$budget" "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "  WARN: $name reload timed out after ${budget}s — skipped (is $name wedged?)"
  fi
  return 0
}

# is_reload_available <tag>
#
# CRITICAL ORDERING: availability is tested BEFORE `changed`, never folded into
# the reload itself. `changed` records the new hash as a side effect, so
# consuming it for a tool that is not installed would mark the change applied and
# permanently suppress the reload that should happen once that tool does exist.
is_reload_available() {
  case "$1" in
    skhd)       command -v skhd       >/dev/null 2>&1 ;;
    sketchybar) command -v sketchybar >/dev/null 2>&1 ;;
    aerospace)  [ -x "$HOME/.config/aerospace/set-main-display.sh" ] ;;
    # tmux needs a liveness probe too: source-file against no running server is
    # an error, not a no-op. The probe precedes `changed` for the same
    # side-effect reason — with no server there is nothing to reload, so the
    # hash must not move.
    tmux)       command -v tmux >/dev/null 2>&1 \
                  && with_timeout "$RELOAD_TIMEOUT" tmux info >/dev/null 2>&1 ;;
    *)          return 1 ;;
  esac
}

run_reload() {
  case "$1" in
    skhd)       _run_guarded skhd       "$RELOAD_TIMEOUT" skhd --reload ;;
    sketchybar) _run_guarded sketchybar "$RELOAD_TIMEOUT" sketchybar --reload ;;
    tmux)       _run_guarded tmux       "$RELOAD_TIMEOUT" tmux source-file "$HOME/.tmux.conf" ;;
    # aerospace is not reloaded directly: its live toml carries this machine's
    # monitor pins, so reconciliation goes through set-main-display.sh, which
    # re-stamps them and reloads once. It is a no-op for side effects when
    # nothing effectively changed.
    aerospace)  _run_guarded aerospace  "$DISPLAY_RECONCILE_TIMEOUT" \
                  "$HOME/.config/aerospace/set-main-display.sh" auto ;;
  esac
}
