#!/usr/bin/env bash
# sync.sh — bidirectional dotfiles sync for a multi-Mac setup.
#
# On each run:
#   1. fetch origin/main
#   2. if remote has new commits, rebase local on top (--autostash keeps any
#      uncommitted working-tree edits out of the way)
#   3. push any local commits back to origin
#   4. if HEAD moved (we pulled real changes), run apply.sh to copy the new
#      configs into place and reload services
#
# Conflicts are LEFT IN PLACE (repo stays in rebasing state) and a macOS
# notification fires so they can be resolved by hand. Until resolved, later
# runs no-op so nothing is clobbered.
#
# Designed to run from launchd (com.ostepan.dotfiles-sync) on login + every
# 30 min, and is safe to run by hand any time.
set -uo pipefail

# launchd gives a minimal PATH — make sure git/brew tools are findable.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRANCH="main"
LOG="$HOME/Library/Logs/dotfiles-sync.log"
LOCK="$HOME/Library/Caches/dotfiles-sync.lock"   # directory used as an atomic lock

mkdir -p "$(dirname "$LOG")"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

# Run a command with a hard timeout so a hung network call (fetch/pull/push
# blocking on a credential prompt or dead connection) can never pile up across
# 30-min ticks. Uses timeout/gtimeout if present, else runs unguarded.
if command -v timeout >/dev/null 2>&1; then TIMEOUT=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT=gtimeout
else TIMEOUT=""; fi
net() { if [ -n "$TIMEOUT" ]; then "$TIMEOUT" 120 "$@"; else "$@"; fi; }

notify() {
  log "NOTIFY: $*"
  osascript -e "display notification \"$1\" with title \"dotfiles sync\" sound name \"Basso\"" 2>/dev/null || true
}

# Prevent overlapping runs (manual run + interval timer can collide).
# macOS has no flock(1), so use an atomic mkdir lock. Steal a lock older than
# 30 min — a healthy run finishes in seconds, so that can only be a stale lock
# left by a crashed/killed run.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -d "$LOCK" ] && [ -z "$(find "$LOCK" -prune -mmin +30 2>/dev/null)" ]; then
    log "another sync is running; skipping"
    exit 0
  fi
  log "stealing stale lock"
  rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || { log "could not acquire lock"; exit 1; }
fi
trap 'rm -rf "$LOCK"' EXIT

cd "$REPO_DIR" || { log "cannot cd to $REPO_DIR"; exit 1; }

# If a previous run left an unresolved rebase, do nothing destructive.
if [ -d "$REPO_DIR/.git/rebase-merge" ] || [ -d "$REPO_DIR/.git/rebase-apply" ]; then
  notify "Unresolved rebase in ~/dotfiles — resolve it, then sync resumes."
  exit 1
fi

OLD_HEAD="$(git rev-parse HEAD 2>/dev/null || echo none)"

# Fetch. If offline, fail quietly (no notification spam every 30 min).
if ! net git fetch origin "$BRANCH" >>"$LOG" 2>&1; then
  log "fetch failed (likely offline or timed out); skipping"
  exit 0
fi

BEHIND="$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)"
AHEAD="$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)"
log "state: behind=$BEHIND ahead=$AHEAD"

# Pull remote changes via rebase if there are any.
if [ "$BEHIND" -gt 0 ]; then
  if ! net git pull --rebase --autostash origin "$BRANCH" >>"$LOG" 2>&1; then
    notify "Rebase conflict in ~/dotfiles ($BEHIND remote / $AHEAD local). Resolve by hand."
    exit 1
  fi
  log "rebased $BEHIND remote commit(s)"
fi

# Push local commits back so the other machine can pull them.
AHEAD="$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)"
if [ "$AHEAD" -gt 0 ]; then
  if net git push origin "$BRANCH" >>"$LOG" 2>&1; then
    log "pushed $AHEAD local commit(s)"
  else
    notify "Push failed for ~/dotfiles ($AHEAD commits ahead). Check auth/network."
  fi
fi

# Only re-apply configs if HEAD actually moved (i.e. we pulled something).
NEW_HEAD="$(git rev-parse HEAD 2>/dev/null || echo none)"
if [ "$NEW_HEAD" != "$OLD_HEAD" ] && [ "$BEHIND" -gt 0 ]; then
  log "HEAD moved $OLD_HEAD -> $NEW_HEAD; applying configs"
  if bash "$SCRIPT_DIR/apply.sh" >>"$LOG" 2>&1; then
    notify "Applied $BEHIND dotfiles update(s) from your other Mac."
  else
    notify "apply.sh failed after pulling updates — see dotfiles-sync.log."
  fi
fi

log "sync complete"
