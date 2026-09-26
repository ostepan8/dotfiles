#!/usr/bin/env bash
# pr-deslop-gate.sh — a PreToolUse hook: no `gh pr create` until the pr-deslop
# subagent has stripped verbose comments from the branch and written the PR text.
#
# The agent records the HEAD it reviewed in $GIT_DIR/pr-deslop-ok. A new commit
# after that moves HEAD and the gate closes again, so the review always covers
# what ships.
#
# Fails OPEN on anything unexpected. To skip, put PR_DESLOP=off in the command.
set -uo pipefail

allow() { exit 0; }
block() { echo "$1" >&2; exit 2; }

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
printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || allow
printf '%s' "$cmd" | grep -q 'PR_DESLOP=off' && allow

[ -n "${cwd:-}" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null
git_dir=$(git rev-parse --git-dir 2>/dev/null) || allow
head=$(git rev-parse HEAD 2>/dev/null) || allow

marker="$git_dir/pr-deslop-ok"
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$head" ] && allow

block "PR NOT CREATED: this branch has not been through pr-deslop at HEAD ${head:0:7}.

Spawn the \`pr-deslop\` subagent (Agent tool, subagent_type: \"pr-deslop\") before
opening the PR. It removes verbose/narrating comments the branch added, commits
that, writes a short spam-free title and body, and marks HEAD as reviewed.
Pass it the attribution footer the PR body must end with.

Then push if it committed, and rerun \`gh pr create\` with the title and body it
returns. To skip for this PR only, add PR_DESLOP=off to the command."
