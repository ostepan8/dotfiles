#!/usr/bin/env bash
# End-to-end test for sub.sh against throwaway local repos. No GitHub, no Docker.
#   bash sub_test.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUB="$HERE/sub.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/sub-test.XXXXXX")"
SESSION_PREFIX="subtest$$"
trap 'tmux kill-session -t "=$SESSION_PREFIX-1" 2>/dev/null || true; rm -rf "$T"' EXIT

export SUB_HOME="$T/home" SUB_REMOTE="file://$T/remote" SUB_GH_ORG="sub-test-no-such-org"
fails=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

seed() {
  local r="$1"
  git init -q -b main "$T/seed/$r"
  printf 'local-dev/.env\n.env\n' >"$T/seed/$r/.gitignore"
  git -C "$T/seed/$r" add .gitignore
  git -C "$T/seed/$r" commit -q -m init
  git -C "$T/seed/$r" branch dev
  git clone -q --bare "$T/seed/$r" "$T/remote/$r.git"
}
mkdir -p "$T/remote" "$T/seed" "$SUB_HOME/.env-store/api-gateway/local-dev"
seed api-gateway
seed bench-runner
git -C "$T/seed/bench-runner" switch -q -c subcon-9-old-work
git -C "$T/seed/bench-runner" commit -q --allow-empty -m wip
git -C "$T/seed/bench-runner" push -q "$T/remote/bench-runner.git" subcon-9-old-work
printf 'DEV_POSTGRES_PORT=\nFOO=bar\n' >"$SUB_HOME/.env-store/api-gateway/local-dev/.env"

"$SUB" start SUBCON-5 gateway bench --no-launch >/dev/null
W="$SUB_HOME/subcon-5"
check "start makes one worktree per repo" '[ -d "$W/api-gateway/.git" ] || [ -f "$W/api-gateway/.git" ]'
check "gateway branches from dev" '[ "$(git -C "$W/api-gateway" rev-parse HEAD)" = "$(git -C "$SUB_HOME/.repos/api-gateway" rev-parse origin/dev)" ]'
check "env copied" 'grep -q "^FOO=bar$" "$W/api-gateway/local-dev/.env"'
check "gateway gets its own compose project" 'grep -q "^DEV_COMPOSE_PROJECT=gw-subcon-5$" "$W/api-gateway/local-dev/.env"'
check "empty port key gets the slot port" 'grep -q "^DEV_POSTGRES_PORT=40101$" "$W/api-gateway/local-dev/.env"'
check "ticket CLAUDE.md written" 'grep -q "PLATFORM_WEB_PORT=40130" "$W/CLAUDE.md"'

"$SUB" start subcon-9 bench --no-launch >/dev/null
check "existing remote branch is continued" '[ "$(cat "$SUB_HOME/subcon-9/.sub/branch")" = subcon-9-old-work ]'
check "second ticket gets slot 2" '[ "$(cat "$SUB_HOME/subcon-9/.sub/slot")" = 2 ]'
check "rerun with no repos is safe" '"$SUB" start subcon-5 --no-launch >/dev/null'
check "rerun rejects a different branch" '! "$SUB" start subcon-5 --branch other --no-launch >/dev/null 2>&1'
"$SUB" add subcon-9 gateway >/dev/null
check "add puts the new repo on the ticket branch" '[ "$(git -C "$SUB_HOME/subcon-9/api-gateway" branch --show-current)" = subcon-9-old-work ]'

check "done refuses without a merged PR" '! "$SUB" done subcon-5 >/dev/null 2>&1'
touch "$W/bench-runner/stray"
check "done --force still refuses uncommitted work" '! "$SUB" done subcon-5 --force >/dev/null 2>&1'
rm "$W/bench-runner/stray"
git -C "$W/bench-runner" commit -q --allow-empty -m local
check "done --force refuses unpushed commits" '! "$SUB" done subcon-5 --force >/dev/null 2>&1'
git -C "$W/bench-runner" reset -q --hard HEAD~1
check "done --force cleans a safe ticket" '"$SUB" done subcon-5 --force >/dev/null'
check "ticket folder gone" '[ ! -e "$W" ]'
check "worktrees pruned" '! git -C "$SUB_HOME/.repos/api-gateway" worktree list | grep -q subcon-5'
"$SUB" start subcon-11 bench --no-launch >/dev/null
check "freed slot is reused" '[ "$(cat "$SUB_HOME/subcon-11/.sub/slot")" = 1 ]'

"$SUB" start subcon-12 gateway --no-launch >/dev/null
echo 'NEW_KEY=1' >>"$SUB_HOME/subcon-12/api-gateway/local-dev/.env"
check "done refuses an edited env file" '! "$SUB" done subcon-12 --force >/dev/null 2>&1'
sed -i '' '/^NEW_KEY=1$/d' "$SUB_HOME/subcon-12/api-gateway/local-dev/.env"
git -C "$SUB_HOME/subcon-12/api-gateway" switch -q -c side
check "done refuses a worktree moved off the ticket branch" '! "$SUB" done subcon-12 --force >/dev/null 2>&1'
git -C "$SUB_HOME/subcon-12/api-gateway" switch -q subcon-12
check "done cleans after the env is restored" '"$SUB" done subcon-12 --force >/dev/null'

mkdir -p "$SUB_HOME/subcon-13/.sub" && echo subcon-13 >"$SUB_HOME/subcon-13/.sub/branch"
check "done cleans a ticket that has no worktrees" '"$SUB" done subcon-13 --force >/dev/null'

for b in subcon-14-a subcon-14-b; do git -C "$T/seed/bench-runner" switch -q -c "$b" main; git -C "$T/seed/bench-runner" push -q "$T/remote/bench-runner.git" "$b"; done
check "several matching branches need --branch" '! "$SUB" start subcon-14 bench --no-launch >/dev/null 2>&1'

for i in 1 2 3 4 5 6; do "$SUB" start "par-$i" bench --no-launch >/dev/null 2>&1 & done
wait
check "parallel starts get distinct slots" '[ "$(cat "$SUB_HOME"/par-*/.sub/slot | sort | uniq -d | wc -l | tr -d " ")" = 0 ]'
check "bad ticket names are refused" '! "$SUB" start "$(printf "ok\nbad name")" bench --no-launch >/dev/null 2>&1'

if command -v tmux >/dev/null; then
  tmux new-session -d -s "$SESSION_PREFIX-2" -c "$T"
  mkdir -p "$SUB_HOME/$SESSION_PREFIX-2/.sub" && echo x >"$SUB_HOME/$SESSION_PREFIX-2/.sub/branch"
  "$SUB" done "$SESSION_PREFIX-2" --force >/dev/null 2>&1 || true
  check "done leaves a same-named session it did not create" 'tmux has-session -t "=$SESSION_PREFIX-2"'
  tmux kill-session -t "=$SESSION_PREFIX-2"
fi

if command -v tmux >/dev/null; then
  t="$SESSION_PREFIX-1"
  "$SUB" start "$t" bench --cmd none --no-window >/dev/null
  check "tmux session created" 'tmux has-session -t "=$t"'
  check "session carries ticket ports" 'tmux show-environment -t "=$t" PLATFORM_WEB_PORT | grep -q "=4"'
  "$SUB" done "$t" --force >/dev/null
  check "done kills only its session" '! tmux has-session -t "=$t" 2>/dev/null'
fi

printf '\n%s\n' "$([ "$fails" -eq 0 ] && echo 'all passed' || echo "$fails failed")"
[ "$fails" -eq 0 ]
