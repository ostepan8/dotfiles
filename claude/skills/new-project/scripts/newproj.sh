#!/usr/bin/env bash
#
# newproj — create a project directory, a tmux session for it, a Claude Code
# pane inside that session, and a new Ghostty window attached to it.
#
# One command, one project, ready to work in.
#
#   newproj marooned-tools
#   newproj misc/scratch --cmd ccdw
#   newproj llm-bench --prompt "read the repo and summarize the layout"
#
# See ~/.claude-personal/skills/new-project/SKILL.md for the full workflow.

set -euo pipefail

readonly DEFAULT_CMD="ccd"
readonly SHELL_WAIT_TIMEOUT=30 # x 0.1s = 3s max wait for the pane shell to boot
readonly TRUST_WAIT_TIMEOUT=80 # x 0.1s = 8s max wait for Claude's trust prompt
readonly GHOSTTY_APP="/Applications/Ghostty.app"

# Machines sharing these dotfiles do NOT share a folder layout — ~/Desktop/Projects
# is one Mac's habit, not a given. Resolve the root per machine instead of
# assuming, in descending order of explicitness:
#
#   1. --root / --path            this invocation
#   2. $NEWPROJ_ROOT              exported from zsh/hosts/<type>.zsh
#   3. ~/.config/newproj/root     machine-local file (survives non-interactive
#                                 shells that never source zshrc — how Claude
#                                 and cron run this). Untracked; never commit it.
#   4. first candidate that exists on this machine
#   5. ~/Projects                 last resort, created on demand
readonly ROOT_CONFIG="$HOME/.config/newproj/root"
readonly ROOT_CANDIDATES=(
  "$HOME/Desktop/Projects"
  "$HOME/Projects"
  "$HOME/projects"
  "$HOME/code"
  "$HOME/dev"
  "$HOME/src"
  "$HOME/Developer"
)
readonly ROOT_FALLBACK="$HOME/Projects"

resolve_root() {
  if [ -n "${NEWPROJ_ROOT:-}" ]; then
    printf '%s' "${NEWPROJ_ROOT/#\~/$HOME}"
    return
  fi

  if [ -r "$ROOT_CONFIG" ]; then
    local configured
    configured="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$ROOT_CONFIG" | grep -m1 .)" || true
    if [ -n "$configured" ]; then
      printf '%s' "${configured/#\~/$HOME}"
      return
    fi
  fi

  local candidate
  for candidate in "${ROOT_CANDIDATES[@]}"; do
    if [ -d "$candidate" ]; then
      printf '%s' "$candidate"
      return
    fi
  done

  printf '%s' "$ROOT_FALLBACK"
}

# ---------------------------------------------------------------- helpers ---

die() {
  printf 'newproj: %s\n' "$1" >&2
  exit 1
}

info() { printf '  %s\n' "$1"; }

usage() {
  cat <<'EOF'
Usage: newproj [options] <name>

Creates <root>/<name>, a tmux session named after it running Claude Code,
and opens a new Ghostty window attached to that session.

Arguments:
  <name>              Project name. May contain slashes to nest under the
                      root (e.g. "web/scratch"); the tmux session is named
                      after the last segment.

Options:
  -r, --root DIR      Project root. Machines sharing these dotfiles don't share
                      a folder layout, so the default is resolved per machine:
                      $NEWPROJ_ROOT, then ~/.config/newproj/root, then the first
                      of ~/Desktop/Projects ~/Projects ~/projects ~/code ~/dev
                      ~/src ~/Developer that exists, then ~/Projects.
      --show-root     Print the root this machine resolves to, and exit
  -p, --path DIR      Exact directory to use; overrides --root and <name> path
  -c, --cmd CMD       Claude launcher: ccd | ccds | ccdw | none  (default: ccd)
  -P, --prompt TEXT   Initial prompt handed to Claude on launch
  -s, --session NAME  Override the tmux session name
      --no-git        Skip `git init`
      --no-readme     Skip seeding README.md
      --no-window     Create everything, but don't open a Ghostty window
      --dry-run       Print what would happen, change nothing
  -h, --help          Show this help

Examples:
  newproj polymarket-bot
  newproj misc/scratch --no-git
  newproj client-site --cmd ccdw --prompt "scaffold a Next.js app"
EOF
}

# tmux session names cannot contain '.' or ':'; spaces make them a pain to
# target from the shell. Normalize to a safe, lowercase slug.
slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    tr ' _' '--' |
    tr -cd 'a-z0-9.:/-' |
    tr '.:' '--' |
    sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//'
}

# Single-quote a string for safe injection into an interactive shell line.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# ------------------------------------------------------------ arg parsing ---

name=""
root=""
explicit_path=""
claude_cmd="$DEFAULT_CMD"
initial_prompt=""
session_override=""
do_git=1
do_readme=1
do_window=1
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    -r | --root) [ $# -ge 2 ] || die "--root needs a value"; root="$2"; shift 2 ;;
    --show-root) resolve_root; printf '\n'; exit 0 ;;
    -p | --path) [ $# -ge 2 ] || die "--path needs a value"; explicit_path="$2"; shift 2 ;;
    -c | --cmd) [ $# -ge 2 ] || die "--cmd needs a value"; claude_cmd="$2"; shift 2 ;;
    -P | --prompt) [ $# -ge 2 ] || die "--prompt needs a value"; initial_prompt="$2"; shift 2 ;;
    -s | --session) [ $# -ge 2 ] || die "--session needs a value"; session_override="$2"; shift 2 ;;
    --no-git) do_git=0; shift ;;
    --no-readme) do_readme=0; shift ;;
    --no-window) do_window=0; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *)
      [ -z "$name" ] || die "unexpected argument: $1 (quote names containing spaces)"
      name="$1"
      shift
      ;;
  esac
done

# ------------------------------------------------------------- validation ---

command -v tmux >/dev/null 2>&1 || die "tmux is not installed (brew install tmux)"

case "$claude_cmd" in
  ccd | ccds | ccdw | none) ;;
  *) die "--cmd must be one of: ccd, ccds, ccdw, none (got '$claude_cmd')" ;;
esac

if [ -z "$name" ] && [ -n "$explicit_path" ]; then
  name="$(basename "$explicit_path")"
fi
[ -n "$name" ] || { usage >&2; die "missing project name"; }

slug="$(slugify "$name")"
[ -n "$slug" ] || die "'$name' has no usable characters for a project name"

session="${session_override:-$(slugify "$(basename "$slug")")}"
[ -n "$session" ] || die "could not derive a tmux session name from '$name'"

if [ -n "$explicit_path" ]; then
  project_dir="${explicit_path/#\~/$HOME}"
else
  [ -n "$root" ] || root="$(resolve_root)"
  project_dir="${root/#\~/$HOME}/$slug"
fi

if [ "$dry_run" -eq 1 ]; then
  cat <<EOF
newproj (dry run)
  directory : $project_dir
  session   : $session
  claude    : $claude_cmd${initial_prompt:+ "$initial_prompt"}
  git init  : $([ "$do_git" -eq 1 ] && echo yes || echo no)
  readme    : $([ "$do_readme" -eq 1 ] && echo yes || echo no)
  window    : $([ "$do_window" -eq 1 ] && echo yes || echo no)
EOF
  exit 0
fi

# ------------------------------------------------------------- directory ----

dir_is_new=0
if [ -d "$project_dir" ]; then
  info "directory exists, reusing: $project_dir"
else
  mkdir -p "$project_dir" || die "could not create $project_dir"
  dir_is_new=1
  info "created $project_dir"
fi

if [ "$do_git" -eq 1 ] && ! git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$project_dir" init -b main >/dev/null 2>&1 || git -C "$project_dir" init >/dev/null 2>&1; then
    info "git repo initialized"
  else
    printf 'newproj: warning: git init failed in %s\n' "$project_dir" >&2
  fi
fi

if [ "$do_readme" -eq 1 ] && [ ! -e "$project_dir/README.md" ]; then
  printf '# %s\n' "$(basename "$slug")" >"$project_dir/README.md" ||
    printf 'newproj: warning: could not write README.md\n' >&2
fi

# --------------------------------------------------------------- session ----

session_existed=0
if tmux has-session -t "=$session" 2>/dev/null; then
  session_existed=1
  info "tmux session '$session' already exists, reusing"
else
  tmux new-session -d -s "$session" -c "$project_dir" ||
    die "could not create tmux session '$session'"
  tmux rename-window -t "=$session:1" claude 2>/dev/null || true
  tmux new-window -d -t "=$session:" -n shell -c "$project_dir" 2>/dev/null || true
  info "tmux session '$session' created (windows: claude, shell)"
fi

# Launch Claude only in a session we just made — never type into a live one.
if [ "$session_existed" -eq 0 ] && [ "$claude_cmd" != "none" ]; then
  # tmux queues keystrokes into the pty, but zsh's line editor can swallow
  # input typed before it finishes initializing. Wait for the shell to settle.
  waited=0
  while [ "$waited" -lt "$SHELL_WAIT_TIMEOUT" ]; do
    pane_cmd="$(tmux display-message -p -t "=$session:claude" '#{pane_current_command}' 2>/dev/null || true)"
    case "$pane_cmd" in
      zsh | bash | fish | sh) break ;;
    esac
    sleep 0.1
    waited=$((waited + 1))
  done

  launch="$claude_cmd"
  [ -n "$initial_prompt" ] && launch="$claude_cmd $(shell_quote "$initial_prompt")"
  tmux send-keys -t "=$session:claude" "$launch" C-m ||
    printf 'newproj: warning: could not start %s in the session\n' "$claude_cmd" >&2
  info "started $claude_cmd in window 'claude'"

  # Claude asks whether it can trust a folder it hasn't seen before. When this
  # run is what created the folder — empty, seconds old, made on request —
  # there is nothing to review, so answer it. Only ever fires on a directory
  # this run created, and only once the prompt is actually on screen; a folder
  # that already existed is left for the user to vet.
  if [ "$dir_is_new" -eq 1 ]; then
    waited=0
    while [ "$waited" -lt "$TRUST_WAIT_TIMEOUT" ]; do
      if tmux capture-pane -p -t "=$session:claude" 2>/dev/null |
        grep -qi 'trust this folder'; then
        tmux send-keys -t "=$session:claude" C-m 2>/dev/null || true
        info "confirmed folder trust (directory created by this run)"
        break
      fi
      sleep 0.1
      waited=$((waited + 1))
    done
  fi
fi

tmux select-window -t "=$session:claude" 2>/dev/null || true

# ---------------------------------------------------------------- attach ----

attach_cmd="tmux attach -t $session"

if [ "$do_window" -eq 0 ]; then
  info "skipped opening a window — attach with: $attach_cmd"
elif [ -n "$(tmux list-clients -t "=$session" 2>/dev/null)" ]; then
  info "a terminal is already attached to '$session' — not opening another"
elif [ -n "${TMUX:-}" ] && [ -t 1 ]; then
  # Already inside tmux at a real terminal: switching beats nesting.
  tmux switch-client -t "=$session"
  info "switched this client to '$session'"
elif [ -d "$GHOSTTY_APP" ]; then
  open -na Ghostty --args -e tmux attach -t "$session" ||
    die "could not open a Ghostty window — attach manually with: $attach_cmd"
  info "opened a Ghostty window attached to '$session'"
else
  info "Ghostty not found — attach with: $attach_cmd"
fi

printf '\n%s ready → %s\n' "$session" "$project_dir"
