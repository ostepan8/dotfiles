#!/usr/bin/env bash
# deploy-gate.sh — a PreToolUse hook: refuse a deploy that would roll main back.
#
# `nephos deploy` builds the WORKING DIRECTORY, not a git ref. Two consequences
# that are invisible at the command line:
#
#   - deploying from a branch behind origin/main removes from production
#     everything main has and the branch lacks;
#   - uncommitted changes in the tree go into the image.
#
# Both happened on 2026-09-19: a deploy from a branch two commits behind main
# replaced a working feature with a duplicate and shipped an unmerged commit.
#
# Fails OPEN on anything unexpected. To deploy anyway, put DEPLOY_GATE=off in
# the command itself (the hook reads the command text, not its environment).
set -uo pipefail

allow() { exit 0; }
block() { echo "$1" >&2; exit 2; }

if command -v timeout >/dev/null 2>&1; then   cap() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then cap() { gtimeout "$@"; }
else                                           cap() { shift; "$@"; }
fi

input=$(cat 2>/dev/null || true)
command -v python3 >/dev/null 2>&1 || allow
eval "$(printf '%s' "$input" | python3 -c '
import json,sys,shlex
try: d=json.load(sys.stdin)
except Exception: sys.exit()
if d.get("tool_name") != "Bash": sys.exit()
cmd = (d.get("tool_input") or {}).get("command","")
print("cwd=%s" % shlex.quote(d.get("cwd","")))
print("cmd=%s" % shlex.quote(cmd))
' 2>/dev/null)"

[ -n "${cmd:-}" ] || allow
# Only deploys. Not `nephos ps`, not `nephos logs`.
printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])nephos[[:space:]]+deploy([[:space:]]|$)' || allow
printf '%s' "$cmd" | grep -q 'DEPLOY_GATE=off' && allow

[ -n "${cwd:-}" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null
git rev-parse --git-dir >/dev/null 2>&1 || allow
git remote get-url origin >/dev/null 2>&1 || allow

cap 20 git fetch --quiet origin 2>/dev/null
git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || allow

behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
if [ "${behind:-0}" -gt 0 ]; then
    block "REFUSING TO DEPLOY: this checkout is $behind commit(s) behind origin/main.

\`nephos deploy\` builds the working directory, so deploying now REMOVES those
commits from production:

$(git log --oneline HEAD..origin/main 2>/dev/null | sed 's/^/  /' | head -10)

Merge or rebase first, or deploy from a clean checkout of origin/main:
  git worktree add --detach /tmp/deploy origin/main && cd /tmp/deploy

To deploy anyway, add DEPLOY_GATE=off to the command."
fi

dirty=$(git status --porcelain --untracked-files=no 2>/dev/null)
if [ -n "$dirty" ]; then
    block "REFUSING TO DEPLOY: uncommitted changes would go into the image.

\`nephos deploy\` builds the working directory, so whatever is below ships
whether or not it was reviewed:

$(printf '%s' "$dirty" | sed 's/^/  /' | head -12)

Commit or stash first. To deploy anyway, add DEPLOY_GATE=off to the command."
fi
allow
