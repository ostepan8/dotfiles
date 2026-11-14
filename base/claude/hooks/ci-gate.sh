#!/usr/bin/env bash
# ci-gate.sh — a Stop hook: do not let a session finish on a red or unfinished CI run.
#
# Pushing is not finishing. A branch left red is broken work handed to someone
# else, and the user should not be the one who discovers it. Docs asking an
# agent to wait are only as good as the agent's willingness to read them; this
# is the same rule, enforced.
#
# Blocks (exit 2, message to stderr) when the commit at HEAD has a CI run that
# is still going or has failed. Silent in every other case — and it fails OPEN
# on anything unexpected, because a hook that wedges a session over its own bug
# is worse than a red branch.
#
# Two sources, in this order:
#   1. A `local-ci` commit status: CI that runs on the user's own machines and
#      posts to the statuses API (listhalo-monorepo: ci/local/README.md). When it
#      exists, it decides: pending = wait, failure/error = block, success = allow.
#      If the repo has ci/local/check.sh and the commit should get a run (main,
#      hub/*, or an open PR) but has no status yet, wait up to
#      CI_GATE_LOCAL_WAIT seconds (default 900) after the push, then allow.
#   2. GitHub Actions runs. A run that ended in `startup_failure` with 0 jobs
#      (billing, not the code) is allowed with a note, so it never blocks forever.
#
# Escape hatch: CI_GATE=off
set -uo pipefail

allow() { exit 0; }
block() { echo "$1" >&2; exit 2; }

# macOS has no coreutils `timeout`. Use it when present (Linux, or brew
# coreutils as gtimeout), otherwise just run the command. Without this shim
# every gh call failed "command not found" and the gate silently allowed
# everything — a guard that always passes is worse than no guard.
if command -v timeout >/dev/null 2>&1; then   cap() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then cap() { gtimeout "$@"; }
else                                           cap() { shift; "$@"; }
fi

[ "${CI_GATE:-on}" = "off" ] && allow

input=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd",""))
except Exception: print("")' 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null

git rev-parse --git-dir >/dev/null 2>&1 || allow
top=$(git rev-parse --show-toplevel)
[ -d "$top/.github/workflows" ] || [ -f "$top/ci/local/check.sh" ] || allow
command -v gh >/dev/null 2>&1 || allow
command -v python3 >/dev/null 2>&1 || allow
gh auth status >/dev/null 2>&1 || allow

sha=$(git rev-parse HEAD 2>/dev/null) || allow
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$branch" = "HEAD" ] && allow   # detached: a throwaway checkout, not work being handed over

# Only care once the commit is actually pushed; local work is the user's business.
git branch -r --contains "$sha" 2>/dev/null | grep -q . || allow

# --- 1. local-ci commit status -------------------------------------------------
now=$(date +%s)
to_epoch() { date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo 0; }
local_ci=$(cap 25 gh api "repos/{owner}/{repo}/commits/$sha/status" 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit()
for s in d.get("statuses") or []:
    if s.get("context") == "local-ci":
        print("\t".join([s.get("state") or "", s.get("updated_at") or "", s.get("target_url") or "-", (s.get("description") or "").replace("\t"," ")]))
        break' 2>/dev/null)
if [ -n "$local_ci" ]; then
    IFS=$'\t' read -r lstate lupdated lurl ldesc <<<"$local_ci"
    case "$lstate" in
    success) allow ;;
    pending)
        age=$(( now - $(to_epoch "$lupdated") ))
        if [ "$age" -lt "$now" ] && [ "$age" -gt "${CI_GATE_MAX_WAIT:-2400}" ]; then
            echo "note: local-ci for ${sha:0:8} has been pending over $((age / 60)) minutes; not blocking on it." >&2
            allow
        fi
        block "local CI is still running for ${sha:0:8} on branch '$branch' ($ldesc).

Wait for it and deal with the result before finishing:
  gh api repos/{owner}/{repo}/commits/$sha/status --jq '.statuses[] | select(.context==\"local-ci\")'

A push is not a finished change until the run is green." ;;
    failure|error)
        link=""; [ "$lurl" != "-" ] && link="
  full log: $lurl"
        block "local CI FAILED for ${sha:0:8} on branch '$branch': $ldesc

Do not hand this over. Fix it and push again.${link}" ;;
    esac
elif [ -f "$top/ci/local/check.sh" ]; then
    # No status yet. Wait for the local runner to pick the commit up, but not forever.
    expected=0
    case "$branch" in main|hub/*) expected=1 ;; esac
    if [ "$expected" = 0 ]; then
        prs=$(cap 15 gh pr list --head "$branch" --state open --json number --jq length 2>/dev/null)
        [ "${prs:-0}" -gt 0 ] 2>/dev/null && expected=1
    fi
    if [ "$expected" = 1 ]; then
        # When this clone saw the push (the remote-tracking reflog), else the commit time.
        seen=$(git log -g -1 --format=%gd --date=unix "refs/remotes/origin/$branch" 2>/dev/null | sed -n 's/.*@{\([0-9]*\)}.*/\1/p')
        made=$(git show -s --format=%ct "$sha" 2>/dev/null)
        pushed=${seen:-0}; [ "${made:-0}" -gt "$pushed" ] && pushed=$made
        if [ "$pushed" -gt 0 ] && [ $((now - pushed)) -lt "${CI_GATE_LOCAL_WAIT:-900}" ]; then
            block "local CI has not reported on ${sha:0:8} yet (branch '$branch'). Its poller runs every 2 minutes.

Wait for the \`local-ci\` status before finishing:
  gh api repos/{owner}/{repo}/commits/$sha/status --jq '.statuses[] | select(.context==\"local-ci\")'"
        fi
        echo "note: no local-ci status for ${sha:0:8} after $(( (now - pushed) / 60 )) minutes; going on to Actions." >&2
    fi
fi

# --- 2. GitHub Actions --------------------------------------------------------
run=$(cap 25 gh run list --commit "$sha" --limit 1 \
        --json databaseId,status,conclusion,workflowName 2>/dev/null) || allow
[ -n "$run" ] || allow

read -r id status conclusion name <<<"$(printf '%s' "$run" | python3 -c 'import json,sys
try: r=json.load(sys.stdin)
except Exception: sys.exit()
if not r: sys.exit()
r=r[0]
print(r.get("databaseId",""), r.get("status",""), r.get("conclusion") or "-", (r.get("workflowName") or "ci").replace(" ","_"))' 2>/dev/null)"
[ -n "${id:-}" ] || allow

case "$status" in
completed)
    case "$conclusion" in
    success|skipped|neutral) allow ;;
    startup_failure)
        jobs=$(cap 15 gh run view "$id" --json jobs --jq '.jobs | length' 2>/dev/null)
        if [ "${jobs:-0}" = 0 ]; then
            echo "note: Actions run $id for ${sha:0:8} ended in startup_failure with 0 jobs and there is no local-ci status; not blocking." >&2
            allow
        fi
        block "CI for ${sha:0:8} ended in startup_failure ($name, $jobs jobs). Look at it: gh run view $id" ;;
    cancelled)
        block "CI for ${sha:0:8} was cancelled ($name). Re-run it and confirm it is green before finishing:
  gh run rerun $id && ./scripts/wait-for-ci.sh
To finish anyway, tell the user CI never passed on this commit." ;;
    *)
        detail=$(cap 25 gh run view "$id" --log-failed 2>/dev/null | tail -25)
        block "CI FAILED for ${sha:0:8} on branch '$branch' ($name, conclusion: $conclusion).

Do not hand this over. Fix it and push again.

${detail:-  (no failing log available)}

  full log: gh run view $id --log-failed" ;;
    esac
    ;;
queued|in_progress|waiting|requested|pending)
    # A run that has been going a very long time is more likely a stuck runner
    # than work in flight; do not hold the session hostage to it.
    started=$(cap 15 gh run view "$id" --json startedAt --jq '.startedAt' 2>/dev/null)
    if [ -n "$started" ] && command -v date >/dev/null 2>&1; then
        began=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s 2>/dev/null \
                || date -d "$started" +%s 2>/dev/null || echo 0)
        now=$(date +%s)
        if [ "$began" -gt 0 ] && [ $((now - began)) -gt "${CI_GATE_MAX_WAIT:-2400}" ]; then
            echo "note: CI run $id has been running over 40 minutes; not blocking on it." >&2
            allow
        fi
    fi
    block "CI is still running for ${sha:0:8} on branch '$branch' ($name).

Wait for it and deal with the result before finishing:
  ./scripts/wait-for-ci.sh     # or: gh run watch $id --exit-status

A push is not a finished change until the run is green."
    ;;
*) allow ;;
esac
allow
