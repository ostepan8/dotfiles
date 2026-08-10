#!/usr/bin/env bash
# sync.sh — bidirectional dotfiles sync for a multi-Mac setup.
#
# On each run:
#   1. fetch origin/main
#   2. if remote has new commits, rebase local on top (--autostash keeps any
#      uncommitted working-tree edits out of the way)
#   3. push any local commits back to origin
#   4. always run apply.sh to copy the repo's current configs into place and
#      reload services — regardless of whether this tick pulled anything, so
#      a commit made directly on this machine (without also hand-copying the
#      live file) can never drift from what's actually deployed
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
# 30-min ticks.
#
# This previously fell back to running UNGUARDED when neither timeout(1) nor
# gtimeout was installed — which is the default state of a stock macOS box, so
# in practice the guard was usually absent exactly where it was needed. Use the
# shared pure-bash implementation instead: always present, no coreutils needed.
# shellcheck source=lib/with-timeout.sh
. "$SCRIPT_DIR/lib/with-timeout.sh"
net() { with_timeout 120 "$@"; }

# From a launchd context the osxkeychain helper can't pop an interactive
# prompt, so a push needing credentials hangs until the timeout. The GitHub
# CLI ships a fully non-interactive credential helper backed by its stored
# token (scope: repo), so route git auth through it when available. Scoped to
# this script via `-c` — no change to the user's global git config.
GIT_CRED=()
if command -v gh >/dev/null 2>&1; then
  GIT_CRED=(-c "credential.https://github.com.helper=" -c "credential.https://github.com.helper=!gh auth git-credential")
fi

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
  if ! net git ${GIT_CRED[@]+"${GIT_CRED[@]}"} pull --rebase --autostash origin "$BRANCH" >>"$LOG" 2>&1; then
    notify "Rebase conflict in ~/dotfiles ($BEHIND remote / $AHEAD local). Resolve by hand."
    exit 1
  fi
  log "rebased $BEHIND remote commit(s)"
fi

# Push local commits back so the other machine can pull them.
AHEAD="$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)"
if [ "$AHEAD" -gt 0 ]; then
  if net git ${GIT_CRED[@]+"${GIT_CRED[@]}"} push origin "$BRANCH" >>"$LOG" 2>&1; then
    log "pushed $AHEAD local commit(s)"
  else
    notify "Push failed for ~/dotfiles ($AHEAD commits ahead). Check auth/network."
  fi
fi

# Always re-apply configs, not just when this tick pulled something. A commit
# made directly on this machine (edited the repo without also copying to the
# live file) would otherwise never get applied here — HEAD only "moves" on a
# pull, so gating on BEHIND>0 silently missed that case. apply.sh is cheap and
# idempotent, so running it every tick guarantees the live config always
# matches whatever HEAD currently is, regardless of how it got there.
NEW_HEAD="$(git rev-parse HEAD 2>/dev/null || echo none)"
if bash "$SCRIPT_DIR/apply.sh" >>"$LOG" 2>&1; then
  if [ "$NEW_HEAD" != "$OLD_HEAD" ] && [ "$BEHIND" -gt 0 ]; then
    notify "Applied $BEHIND dotfiles update(s) from your other Mac."
  fi
else
  notify "apply.sh failed — see dotfiles-sync.log."
fi

log "sync complete"
