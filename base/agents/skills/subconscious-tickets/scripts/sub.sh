#!/usr/bin/env bash
# sub — one folder per Subconscious ticket, holding one git worktree per repo
# the ticket touches, each with its own env, ports and gateway database.
#
#   sub start <ticket> <repo>... [--branch NAME] [--prompt TEXT] [--cmd CMD] [--no-launch] [--no-window]
#   sub add   <ticket> <repo>...                 add a repo to an existing ticket
#   sub ls                                      every ticket, its branches and PR state
#   sub done  <ticket> [--force]                safety checks, then full teardown
#   sub repos                                   known repos, aliases and base branches
#
# Layout (SUB_HOME, default ~/Desktop/subconscious):
#   .repos/<repo>/        parent clones; never work in these
#   .env-store/<repo>/... env files copied into every new worktree
#   <ticket>/<repo>/      worktrees
#   <ticket>/.sub/        slot, branch, ports (machine-read)
#
# See ~/.agents/skills/subconscious-tickets/SKILL.md for the workflow.

set -euo pipefail

SUB_HOME="${SUB_HOME:-$HOME/Desktop/subconscious}"
SUB_REMOTE="${SUB_REMOTE:-git@github.com:subconscious-systems}"
SUB_GH_ORG="${SUB_GH_ORG:-subconscious-systems}"
SUB_CMD="${SUB_CMD:-ccdw}"
REPOS_DIR="$SUB_HOME/.repos"
ENV_STORE="$SUB_HOME/.env-store"
PORT_BASE=40000
PORT_STRIDE=100
MAX_SLOTS=90
SHELL_WAIT_TIMEOUT=50   # x0.1s
TRUST_WAIT_TIMEOUT=100  # x0.1s

die() { printf 'sub: %s\n' "$1" >&2; exit "${2:-1}"; }
warn() { printf 'sub: warning: %s\n' "$1" >&2; }
info() { printf '  %s\n' "$1"; }

shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# ------------------------------------------------------------------ repos ----

# canonical_repo <name-or-alias> -> GitHub repo name
canonical_repo() {
  case "$1" in
    platform | monorepo | subconscious-monorepo | web) echo platform ;;
    api-gateway | gateway | gw) echo api-gateway ;;
    subconscious | cli) echo subconscious ;;
    subconscious-code | marathon | code) echo subconscious-code ;;
    bench-runner | bench) echo bench-runner ;;
    SubconsciousCache-SGLang | sglang | cache) echo SubconsciousCache-SGLang ;;
    docs | ol-runbook | houston | orangeline | gpu-deployment | api-gateway-infra) echo "$1" ;;
    *) die "unknown repo '$1' (run: sub repos)" ;;
  esac
}

base_branch() {
  case "$1" in
    platform | api-gateway) echo dev ;;
    *) echo main ;;
  esac
}

cmd_repos() {
  cat <<'EOF'
repo                      aliases                  base
platform                  monorepo, web            dev
api-gateway               gateway, gw              dev
subconscious              cli                      main
subconscious-code         marathon, code           main
bench-runner              bench                    main
SubconsciousCache-SGLang  sglang, cache            main
docs, ol-runbook, houston, orangeline, gpu-deployment, api-gateway-infra   main
EOF
}

# ensure_parent <repo> -> path of an up-to-date parent clone
ensure_parent() {
  local repo="$1" dir="$REPOS_DIR/$1"
  mkdir -p "$REPOS_DIR"
  if [ ! -d "$dir/.git" ]; then
    info "cloning $repo"
    git clone -q --filter=blob:none "$SUB_REMOTE/$repo.git" "$dir" >&2 ||
      die "could not clone $repo"
  fi
  git -C "$dir" fetch -q --prune origin >&2 || warn "fetch failed for $repo; using cached refs"
  echo "$dir"
}

# ----------------------------------------------------------------- ticket ----

normalize_ticket() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    "" | -* | *[!a-z0-9-]*) die "bad ticket name '$1' (use letters, digits and dashes, like subcon-670)" ;;
  esac
  echo "$t"
}

ticket_dir() { echo "$SUB_HOME/$1"; }
meta() { cat "$(ticket_dir "$1")/.sub/$2" 2>/dev/null || true; }

# claim_slot <ticket> -> lowest free slot number. mkdir is atomic, so two
# parallel starts can never get the same slot.
claim_slot() {
  local n
  mkdir -p "$SUB_HOME/.slots"
  for n in $(seq 1 "$MAX_SLOTS"); do
    if mkdir "$SUB_HOME/.slots/$n" 2>/dev/null; then
      echo "$1" >"$SUB_HOME/.slots/$n/ticket"
      echo "$n"
      return
    fi
  done
  die "all $MAX_SLOTS port slots are in use; clean up old tickets (sub ls)"
}

release_slot() {
  local n="$1"
  if [ -n "$n" ]; then rm -rf "${SUB_HOME:?}/.slots/$n"; fi
}

# worktrees <ticket> -> one worktree path per line (skips anything that is not
# a worktree of the matching parent clone)
worktrees() {
  local tdir wt repo
  tdir="$(ticket_dir "$1")"
  for wt in "$tdir"/*/; do
    [ -d "$wt" ] || continue
    wt="${wt%/}"
    repo="$(basename "$wt")"
    git -C "$REPOS_DIR/$repo" worktree list --porcelain 2>/dev/null |
      grep -qxF "worktree $(cd "$wt" && pwd -P)" && echo "$wt"
  done
  return 0
}

# port <slot> <offset>
port() { echo $((PORT_BASE + $1 * PORT_STRIDE + $2)); }

write_ports() {
  local slot="$1" file="$2"
  cat >"$file" <<EOF
PLATFORM_WEB_PORT=$(port "$slot" 30)
DEV_POSTGRES_PORT=$(port "$slot" 1)
DEV_VALKEY_PORT=$(port "$slot" 2)
DEV_ADAPTER_PORT=$(port "$slot" 10)
DEV_ROUTER_PORT=$(port "$slot" 20)
DEV_ROUTER_METRICS_PORT=$(port "$slot" 21)
DEV_GATEWAY_PORT=$(port "$slot" 80)
DEV_GATEWAY_MANAGEMENT_PORT=$(port "$slot" 81)
DEV_GATEWAY_ADMIN_PORT=$(port "$slot" 82)
EOF
}

# resolve_branch <ticket> <explicit-or-empty> -> branch name
# An explicit name wins. Otherwise reuse a branch that already starts with the
# ticket id on any parent (Linear names them subcon-670-<title>), so a ticket
# begun elsewhere continues instead of forking.
resolve_branch() {
  local ticket="$1" explicit="$2" found="" repo
  [ -n "$explicit" ] && { echo "$explicit"; return; }
  found="$(for repo in "$REPOS_DIR"/*/; do
    [ -d "$repo/.git" ] || continue
    git -C "$repo" for-each-ref --format='%(refname:lstrip=3)' \
      "refs/remotes/origin/$ticket" "refs/remotes/origin/$ticket-*" 2>/dev/null
  done | sort -u)"
  if [ -z "$found" ]; then
    echo "$ticket"
  elif [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" -gt 1 ]; then
    die "several branches match $ticket; pick one with --branch:
$found"
  else
    echo "$found"
  fi
}

# add_worktree <ticket> <repo> <branch>
add_worktree() {
  local ticket="$1" repo="$2" branch="$3" parent dest base
  dest="$(ticket_dir "$ticket")/$repo"
  if [ -e "$dest" ]; then
    info "$repo: worktree exists"
    return
  fi
  parent="$(ensure_parent "$repo")"
  base="$(base_branch "$repo")"
  if git -C "$parent" show-ref -q --verify "refs/heads/$branch"; then
    git -C "$parent" worktree add -q "$dest" "$branch" >&2 ||
      die "$repo: branch $branch is checked out somewhere else (git -C $parent worktree list)"
    info "$repo: reused local branch $branch"
    if git -C "$parent" show-ref -q --verify "refs/remotes/origin/$branch"; then
      local behind
      behind="$(git -C "$parent" rev-list --count "$branch..origin/$branch")"
      [ "$behind" = 0 ] || warn "$repo: local $branch is $behind commits behind origin; pull before work"
    fi
  elif git -C "$parent" show-ref -q --verify "refs/remotes/origin/$branch"; then
    git -C "$parent" worktree add -q --track -b "$branch" "$dest" "origin/$branch" >&2
    info "$repo: continued origin/$branch"
  else
    git -C "$parent" worktree add -q --no-track -b "$branch" "$dest" "origin/$base" >&2
    info "$repo: new branch $branch from origin/$base"
  fi
  copy_env "$ticket" "$repo"
}

# set_kv <file> <key> <value>: replace or append KEY=value, writing a new file.
set_kv() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "$file.XXXXXX")"
  awk -v k="$key" -v v="$value" '
    BEGIN { done = 0 }
    $0 ~ "^"k"=" { print k"="v; done = 1; next }
    { print }
    END { if (!done) print k"="v }' "$file" >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

copy_env() {
  local ticket="$1" repo="$2" src dest rel tdir
  tdir="$(ticket_dir "$ticket")"
  src="$ENV_STORE/$repo"
  [ -d "$src" ] || return 0
  while IFS= read -r rel; do
    dest="$tdir/$repo/$rel"
    [ -e "$dest" ] && continue
    mkdir -p "$(dirname "$dest")"
    cp -p "$src/$rel" "$dest"
    chmod 600 "$dest"
    info "$repo: copied env $rel"
  done < <(cd "$src" && find . -type f | sed 's#^\./##')
  [ "$repo" = api-gateway ] && wire_gateway_env "$ticket"
  return 0
}

# Point the gateway's compose stack at this ticket's own project and ports, so
# its Postgres is a separate database that `sub done` can drop.
wire_gateway_env() {
  local ticket="$1" tdir env key value
  tdir="$(ticket_dir "$ticket")"
  env="$tdir/api-gateway/local-dev/.env"
  [ -f "$env" ] || return 0
  set_kv "$env" DEV_COMPOSE_PROJECT "$(compose_project "$ticket")"
  while IFS='=' read -r key value; do
    case "$key" in DEV_*) set_kv "$env" "$key" "$value" ;; esac
  done <"$tdir/.sub/ports"
}

compose_project() { echo "gw-$1"; }

# session_is_ours <ticket>: the session with the ticket's name started in its folder
session_is_ours() {
  local path
  path="$(tmux display-message -p -t "=$1:" '#{session_path}' 2>/dev/null)" || return 1
  [ "$path" = "$(ticket_dir "$1")" ]
}

# The root CLAUDE.md (the repo map every agent reads first) lives in this skill.
ensure_home() {
  local map="$HOME/.agents/skills/subconscious-tickets/references/home-CLAUDE.md"
  mkdir -p "$SUB_HOME"
  [ -e "$SUB_HOME/CLAUDE.md" ] || [ ! -f "$map" ] || ln -s "$map" "$SUB_HOME/CLAUDE.md"
}

write_ticket_claude_md() {
  local ticket="$1" tdir repo branch
  tdir="$(ticket_dir "$ticket")"
  branch="$(meta "$ticket" branch)"
  {
    printf '# %s\n\n' "$ticket"
    printf 'Generated by `sub`. Do not edit; `sub add` rewrites it.\n\n'
    printf 'Branch in every repo: `%s`\n\n' "$branch"
    printf '| Repo | Base | PR target |\n|---|---|---|\n'
    for repo in $(worktrees "$ticket"); do
      repo="$(basename "$repo")"
      printf '| `%s/` | origin/%s | %s |\n' "$repo" "$(base_branch "$repo")" "$(base_branch "$repo")"
    done
    printf '\n## Ports for this ticket\n\nUse these, never the defaults. Other tickets run at the same time.\n\n```\n'
    cat "$tdir/.sub/ports"
    printf '```\n\n'
    printf -- '- Platform web: `PORT=$PLATFORM_WEB_PORT pnpm dev` in `platform/web`. It uses the shared Neon database from `.env`.\n'
    printf -- '- Gateway: `bash local-dev/dev.sh up` in `api-gateway`. `.env` already sets compose project `%s` and the ports above, so it gets its own Postgres.\n' "$(compose_project "$ticket")"
    printf -- '- Open PRs against the base branch in the table. Push with `-u`.\n'
    printf -- '- Need another repo? Run `sub add %s <repo>`.\n' "$ticket"
    printf -- '- When the PRs merge, Owen runs `sub done %s`. Never delete worktrees yourself.\n' "$ticket"
  } >"$tdir/CLAUDE.md"
}

# ---------------------------------------------------------------- session ----

start_session() {
  local ticket="$1" cmd="$2" prompt="$3" new_dir="$4" tdir session pane launch waited
  tdir="$(ticket_dir "$ticket")"
  session="$ticket"
  if tmux has-session -t "=$session" 2>/dev/null; then
    session_is_ours "$ticket" || die "a tmux session named '$session' exists but is not this ticket's; rename it first"
    info "tmux session '$session' already running"
    return
  fi
  local envs=() line
  while IFS= read -r line; do envs+=(-e "$line"); done <"$tdir/.sub/ports"
  tmux new-session -d -s "$session" -n claude -c "$tdir" "${envs[@]}" || die "could not create tmux session '$session'"
  tmux new-window -d -t "=$session:" -n shell -c "$tdir" 2>/dev/null || true
  info "tmux session '$session' created (windows: claude, shell)"
  [ "$cmd" = none ] && return

  waited=0
  while [ "$waited" -lt "$SHELL_WAIT_TIMEOUT" ]; do
    pane="$(tmux display-message -p -t "=$session:claude" '#{pane_current_command}' 2>/dev/null || true)"
    case "$pane" in zsh | bash | fish | sh) break ;; esac
    sleep 0.1
    waited=$((waited + 1))
  done
  launch="$cmd"
  [ -n "$prompt" ] && launch="$cmd $(shell_quote "$prompt")"
  tmux send-keys -t "=$session:claude" "$launch" C-m
  info "started $cmd in window 'claude'"

  # The trust prompt only gets answered for a folder this run created.
  [ "$new_dir" -eq 1 ] || return 0
  waited=0
  while [ "$waited" -lt "$TRUST_WAIT_TIMEOUT" ]; do
    if tmux capture-pane -p -t "=$session:claude" 2>/dev/null | grep -qi 'trust this folder'; then
      tmux send-keys -t "=$session:claude" C-m 2>/dev/null || true
      info "confirmed folder trust (folder created by this run)"
      return
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
}

open_window() {
  local session="$1"
  if [ -n "$(tmux list-clients -t "=$session" 2>/dev/null)" ]; then
    info "a terminal is already attached to '$session'"
  elif [ -d /Applications/Ghostty.app ]; then
    open -na Ghostty --args -e tmux attach -t "$session" && info "opened a Ghostty window on '$session'"
  else
    info "attach with: tmux attach -t $session"
  fi
}

# ------------------------------------------------------------------ start ----

cmd_start() {
  local ticket="" branch="" prompt="" cmd="$SUB_CMD" launch=1 window=1 repos=() tdir new_dir=0 r
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) branch="${2:?--branch needs a value}"; shift 2 ;;
      --prompt) prompt="${2:?--prompt needs a value}"; shift 2 ;;
      --cmd) cmd="${2:?--cmd needs a value}"; shift 2 ;;
      --no-launch) launch=0; shift ;;
      --no-window) window=0; shift ;;
      -*) die "unknown flag $1" ;;
      *) if [ -z "$ticket" ]; then ticket="$(normalize_ticket "$1")"; else repos+=("$(canonical_repo "$1")"); fi; shift ;;
    esac
  done
  [ -n "$ticket" ] || die "usage: sub start <ticket> <repo>..."
  tdir="$(ticket_dir "$ticket")"
  ensure_home

  if [ -d "$tdir/.sub" ]; then
    info "ticket $ticket exists; reusing branch $(meta "$ticket" branch)"
    [ -z "$branch" ] || [ "$branch" = "$(meta "$ticket" branch)" ] ||
      die "ticket $ticket is already on branch $(meta "$ticket" branch), not $branch"
    branch="$(meta "$ticket" branch)"
  else
    [ ${#repos[@]} -gt 0 ] || die "name at least one repo: sub start $ticket <repo>..."
    for r in ${repos[@]+"${repos[@]}"}; do ensure_parent "$r" >/dev/null; done
    branch="$(resolve_branch "$ticket" "$branch")"
    mkdir -p "$tdir/.sub"
    new_dir=1
    echo "$branch" >"$tdir/.sub/branch"
    claim_slot "$ticket" >"$tdir/.sub/slot"
    write_ports "$(meta "$ticket" slot)" "$tdir/.sub/ports"
    info "ticket $ticket: branch $branch, port slot $(meta "$ticket" slot)"
  fi

  for r in ${repos[@]+"${repos[@]}"}; do add_worktree "$ticket" "$r" "$branch"; done
  write_ticket_claude_md "$ticket"
  report_prs "$ticket"

  if [ "$launch" -eq 1 ]; then
    command -v tmux >/dev/null || die "tmux is not installed"
    start_session "$ticket" "$cmd" "$prompt" "$new_dir"
    [ "$window" -eq 1 ] && [ -z "${TMUX:-}" ] && open_window "$ticket"
  fi
  printf '\n%s ready -> %s\n' "$ticket" "$tdir"
}

cmd_add() {
  local ticket
  ticket="$(normalize_ticket "${1:?usage: sub add <ticket> <repo>...}")"
  shift
  [ -d "$(ticket_dir "$ticket")/.sub" ] || die "no ticket $ticket (start it with: sub start $ticket <repo>...)"
  [ $# -gt 0 ] || die "usage: sub add $ticket <repo>..."
  cmd_start "$ticket" "$@" --no-launch
}

# --------------------------------------------------------------------- ls ----

# pr_info <repo> <branch> -> "STATE HEADOID"; STATE is MERGED | OPEN | CLOSED | none | unknown
pr_info() {
  [ -n "$2" ] || { echo "unknown -"; return; }
  command -v gh >/dev/null || { echo "unknown -"; return; }
  local s
  s="$(gh pr list -R "$SUB_GH_ORG/$1" --head "$2" --state all --limit 1 \
    --json state,headRefOid -q '.[0] | "\(.state) \(.headRefOid)"' 2>/dev/null)" || { echo "unknown -"; return; }
  echo "${s:-none -}"
}
pr_state() { pr_info "$1" "$2" | cut -d' ' -f1; }

report_prs() {
  local ticket="$1" tdir repo state branch
  tdir="$(ticket_dir "$ticket")"
  branch="$(meta "$ticket" branch)"
  for repo in $(worktrees "$ticket"); do
    repo="$(basename "$repo")"
    state="$(pr_state "$repo" "$branch")"
    case "$state" in OPEN | MERGED | CLOSED) info "$repo: PR is $state — tell the agent to continue it" ;; esac
  done
}

# unpushed <worktree> [rev] [merged-head-oid] -> commits on rev not on GitHub.
# A squash-merged PR's branch is often deleted on origin, so its merged head
# counts as pushed.
unpushed() {
  local rev="${2:-HEAD}" extra=()
  [ -n "${3:-}" ] && [ "$3" != - ] && git -C "$1" cat-file -e "$3^{commit}" 2>/dev/null && extra=("$3")
  git -C "$1" rev-list --count "$rev" --not --remotes=origin ${extra[@]+"${extra[@]}"} 2>/dev/null || echo "?"
}

dirty() {
  local out
  out="$(git -C "$1" status --porcelain 2>/dev/null)" || { echo "?"; return; }
  [ -z "$out" ] && { echo 0; return; }
  printf '%s\n' "$out" | wc -l | tr -d ' '
}

# changed_envs <ticket> <worktree> -> env files edited since they were copied
changed_envs() {
  local repo rel
  repo="$(basename "$2")"
  [ -d "$ENV_STORE/$repo" ] || return 0
  while IFS= read -r rel; do
    [ -f "$2/$rel" ] || continue
    if [ "$repo" = api-gateway ] && [ "$rel" = local-dev/.env ]; then
      # sub rewrote the DEV_* lines itself; compare the rest
      diff -q <(grep -v '^DEV_' "$ENV_STORE/$repo/$rel") <(grep -v '^DEV_' "$2/$rel") >/dev/null || echo "$rel"
    else
      cmp -s "$ENV_STORE/$repo/$rel" "$2/$rel" || echo "$rel"
    fi
  done < <(cd "$ENV_STORE/$repo" && find . -type f | sed 's#^\./##')
}

cmd_ls() {
  local tdir ticket branch repo wt state all_merged live line
  for tdir in "$SUB_HOME"/*/; do
    [ -d "$tdir/.sub" ] || continue
    ticket="$(basename "$tdir")"
    branch="$(meta "$ticket" branch)"
    live="no session"
    tmux has-session -t "=$ticket" 2>/dev/null && live="session running"
    all_merged=1
    line=""
    for wt in $(worktrees "$ticket"); do
      repo="$(basename "$wt")"
      state="$(pr_state "$repo" "$branch")"
      [ "$state" = MERGED ] && [ "$(dirty "$wt")" = 0 ] || all_merged=0
      line+="$(printf '    %-26s PR %-8s dirty %-3s unpushed %s' "$repo" "$state" "$(dirty "$wt")" "$(unpushed "$wt")")"$'\n'
    done
    printf '%s  [%s, slot %s, %s]%s\n' "$ticket" "$branch" "$(meta "$ticket" slot)" "$live" \
      "$([ "$all_merged" = 1 ] && [ -n "$line" ] && echo '  READY TO CLEAN')"
    printf '%s' "$line"
  done
}

# ------------------------------------------------------------------- done ----

# check_done <ticket> <force>: refuse (exit 3) if teardown could lose work.
# --force only skips the merged-PR check.
check_done() {
  local ticket="$1" force="$2" branch wt repo problems=0 info state oid head rel
  branch="$(meta "$ticket" branch)"
  [ -n "$branch" ] || die "ticket $ticket has no branch recorded; clean it up by hand" 3
  for wt in $(worktrees "$ticket"); do
    repo="$(basename "$wt")"
    info="$(pr_info "$repo" "$branch")"
    state="${info%% *}"
    oid="${info#* }"
    [ "$(dirty "$wt")" = 0 ] || { warn "$repo: uncommitted changes ($(dirty "$wt"))"; problems=1; }
    [ "$(unpushed "$wt" HEAD "$oid")" = 0 ] || { warn "$repo: commits not on GitHub ($(unpushed "$wt" HEAD "$oid"))"; problems=1; }
    head="$(git -C "$wt" symbolic-ref -q --short HEAD || echo detached)"
    if [ "$head" != "$branch" ]; then
      warn "$repo: on $head, not $branch; switch back or clean up by hand"
      problems=1
    elif git -C "$wt" show-ref -q --verify "refs/heads/$branch" &&
      [ "$(unpushed "$wt" "$branch" "$oid")" != 0 ]; then
      warn "$repo: branch $branch has commits not on GitHub"
      problems=1
    fi
    for rel in $(changed_envs "$ticket" "$wt"); do
      warn "$repo: $rel differs from .env-store; copy what you need, then rerun"
      problems=1
    done
    if [ "$state" != MERGED ] && [ "$force" -eq 0 ]; then
      warn "$repo: PR is $state, not MERGED (pass --force to clean anyway)"
      problems=1
    fi
  done
  [ "$problems" -eq 0 ] || die "nothing removed" 3
}

# stop_session <ticket>: kill the ticket's own tmux session once the checks
# pass, so no agent writes into a worktree while it is removed. A failed check
# leaves the session running. Inside that session, killing it would end this
# script, so it waits until the very end instead.
inside_session() { [ -n "${TMUX:-}" ] && [ "$(tmux display-message -p '#{session_name}' 2>/dev/null)" = "$1" ]; }
stop_session() {
  tmux has-session -t "=$1" 2>/dev/null || return 0
  session_is_ours "$1" || { warn "tmux session '$1' is not this ticket's; leaving it"; return 0; }
  inside_session "$1" && return 0
  tmux kill-session -t "=$1" && info "killed tmux session '$1'"
}

cmd_done() {
  local ticket force=0 tdir branch wt repo parent state failed=0
  ticket="$(normalize_ticket "${1:?usage: sub done <ticket> [--force]}")"
  [ "${2:-}" = --force ] && force=1
  tdir="$(ticket_dir "$ticket")"
  [ -d "$tdir/.sub" ] || die "no ticket $ticket"
  branch="$(meta "$ticket" branch)"

  check_done "$ticket" "$force"
  stop_session "$ticket"

  if [ -d "$tdir/api-gateway" ] && command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    docker compose -p "$(compose_project "$ticket")" down -v --remove-orphans >/dev/null 2>&1 &&
      info "stopped gateway stack and dropped its database ($(compose_project "$ticket"))"
  fi
  for wt in $(worktrees "$ticket"); do
    repo="$(basename "$wt")"
    parent="$REPOS_DIR/$repo"
    # No --force: git refuses if anything became dirty since the check. Ignored
    # files (env copies checked above, build output) do not block removal.
    if [ "$(dirty "$wt")" != 0 ] || ! git -C "$parent" worktree remove "$wt"; then
      warn "$repo: could not remove worktree; it changed after the check"
      failed=1
      continue
    fi
    info "$repo: worktree removed"
    state="$(pr_state "$repo" "$branch")"
    if [ "$state" = MERGED ]; then
      git -C "$parent" branch -D "$branch" >/dev/null 2>&1 && info "$repo: deleted merged local branch"
    else
      info "$repo: kept local branch $branch (PR $state)"
    fi
    git -C "$parent" worktree prune
  done
  [ "$failed" -eq 0 ] || die "stopped; ticket folder kept" 3
  release_slot "$(meta "$ticket" slot)"
  rm -rf "${tdir:?}/.sub" "$tdir/CLAUDE.md"
  rmdir "$tdir" 2>/dev/null || warn "left $tdir: it still holds files sub did not create"
  info "freed port slot"
  if inside_session "$ticket"; then
    printf '\n%s cleaned up; closing this session\n' "$ticket"
    tmux kill-session -t "=$ticket"
  fi
  printf '\n%s cleaned up\n' "$ticket"
}

# ------------------------------------------------------------------- main ----

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    start) cmd_start "$@" ;;
    add) cmd_add "$@" ;;
    ls) cmd_ls ;;
    done) cmd_done "$@" ;;
    repos) cmd_repos ;;
    "" | -h | --help | help) usage ;;
    *) die "unknown command '$sub' (run: sub help)" ;;
  esac
}

main "$@"
