#!/usr/bin/env bash
# repo-orient.sh — a SessionStart hook: say what has landed while you were away.
#
# The first question in a repo with several live branches is not "how do I
# build this", it is "does this already exist". On 2026-09-19 a session spent
# hours rebuilding a feature that had been merged to main that morning, because
# the checked-out branch predated it and nothing said so.
#
# Prints a few lines of stdout, which the session reads as context. Silent when
# there is nothing worth saying, and on any failure.
set -uo pipefail
quiet() { exit 0; }

if command -v timeout >/dev/null 2>&1; then   cap() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then cap() { gtimeout "$@"; }
else                                           cap() { shift; "$@"; }
fi

input=$(cat 2>/dev/null || true)
if command -v python3 >/dev/null 2>&1; then
    cwd=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd",""))
except Exception: print("")' 2>/dev/null)
    [ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null
fi

git rev-parse --git-dir >/dev/null 2>&1 || quiet
git remote get-url origin >/dev/null 2>&1 || quiet
cap 20 git fetch --quiet origin 2>/dev/null

base=origin/main
git rev-parse --verify --quiet "$base" >/dev/null 2>&1 || base=origin/master
git rev-parse --verify --quiet "$base" >/dev/null 2>&1 || quiet

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
behind=$(git rev-list --count HEAD.."$base" 2>/dev/null || echo 0)
ahead=$(git rev-list --count "$base"..HEAD 2>/dev/null || echo 0)

out=""
add() { out="${out}$1
"; }

if [ "${behind:-0}" -gt 0 ]; then
    add "This checkout (${branch}) is ${behind} commit(s) BEHIND ${base}. Landed while you were away:"
    add "$(git log --oneline "HEAD..$base" 2>/dev/null | head -8 | sed 's/^/    /')"
    add ""
    add "  Before building anything, check it is not already done. Branch from ${base}:"
    add "      git switch -c <name> ${base}"
    add "  Do not deploy from here — nephos deploy builds the working directory."
fi

# Filter on the FULL refname: refs/remotes/origin/HEAD shortens to plain
# "origin", so filtering the short name lets the symref through as noise.
recent=$(git for-each-ref --sort=-committerdate \
         --format='%(refname)|%(refname:short)|%(committerdate:relative)' \
         refs/remotes/origin/ 2>/dev/null \
         | grep -v '^refs/remotes/origin/HEAD|' | head -6 \
         | awk -F'|' '{printf "    %-46s %s\n", $2, $3}')
if [ -n "$recent" ]; then
    [ -n "$out" ] && add ""
    add "Branches in flight (newest first) — check these before starting work:"
    add "$recent"
fi

[ -n "$out" ] || quiet
printf '%s' "$out"
