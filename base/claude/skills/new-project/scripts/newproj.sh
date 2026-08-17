#!/usr/bin/env bash
#
# newproj — create a project directory, optionally a GitHub repo, a tmux
# session for it, a Claude Code pane inside that session, and a new Ghostty
# window attached to it.
#
# One command, one project, ready to work in.
#
#   newproj marooned-tools                    # asks the setup questions
#   newproj marooned-tools -y                 # no questions, all defaults
#   newproj api --github private --stack node # fully specified, no questions
#
# Run at a terminal it asks a short series of questions (stack, GitHub repo,
# Claude profile, opening task). Run from a script, a cron job, or Claude's
# Bash tool it never blocks — anything unspecified takes its default.
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

warn() { printf 'newproj: warning: %s\n' "$1" >&2; }
info() { printf '  %s\n' "$1"; }
step() { printf '\n%s\n' "$1"; }

usage() {
  cat <<'EOF'
Usage: newproj [options] <name>

Creates <root>/<name>, optionally a GitHub repo, a tmux session named after it
running Claude Code, and a new Ghostty window attached to that session.

At a terminal it asks four short questions (stack, GitHub, Claude profile,
opening task). Anything passed as a flag is not asked about; -y asks nothing.

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
  -g, --github VIS    GitHub repo: private | public | none
      --stack STACK   node | python | rust | go | roblox | web | none
  -c, --cmd CMD       Claude launcher: ccd | ccds | ccdw | none  (default: ccd)
  -P, --prompt TEXT   Opening task handed to Claude on launch
  -s, --session NAME  Override the tmux session name
  -y, --yes           Ask nothing; take defaults for whatever wasn't specified
      --no-git        Skip `git init` (and therefore GitHub)
      --no-readme     Skip seeding README.md
      --no-window     Create everything, but don't open a Ghostty window
      --dry-run       Print what would happen, change nothing
  -h, --help          Show this help

Examples:
  newproj polymarket-bot
  newproj api --github private --stack node -P "scaffold an Express server"
  newproj misc/scratch -y --no-git
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

interactive=0
prompts_enabled() { [ "$interactive" -eq 1 ]; }

# ask_choice <prompt> <valid-keys> <default-key-or-empty> -> echoes chosen key.
# Empty default means the answer is mandatory: it re-asks until a valid key.
ask_choice() {
  local prompt="$1" valid="$2" default="$3" answer=""
  while :; do
    printf '%s ' "$prompt" >&2
    IFS= read -r answer </dev/tty || answer=""
    answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    if [ -z "$answer" ] && [ -n "$default" ]; then
      printf '%s' "$default"
      return
    fi
    if [ -n "$answer" ]; then
      case "$valid" in
        *"|$answer|"*)
          printf '%s' "$answer"
          return
          ;;
      esac
    fi
    printf '  please answer one of: %s\n' "$(printf '%s' "$valid" | tr '|' ' ')" >&2
  done
}

ask_line() {
  local prompt="$1" answer=""
  printf '%s ' "$prompt" >&2
  IFS= read -r answer </dev/tty || answer=""
  printf '%s' "$answer"
}

# --------------------------------------------------------------- scaffold ---

# Stack-specific .gitignore. Deliberately just ignore rules — no `npm init`,
# `uv init`, or cargo scaffold, because the right tool per stack varies
# (npm vs bun, uv vs poetry) and guessing wrong leaves a mess to undo. Claude
# opens in the window able to do that properly, and knows the chosen stack.
gitignore_for_stack() {
  case "$1" in
    node)
      cat <<'EOF'
node_modules/
dist/
build/
.next/
coverage/
*.log
.env
.env.*
!.env.example
EOF
      ;;
    python)
      cat <<'EOF'
__pycache__/
*.py[cod]
.venv/
venv/
.pytest_cache/
.ruff_cache/
.mypy_cache/
dist/
build/
*.egg-info/
.env
.env.*
!.env.example
EOF
      ;;
    rust)
      cat <<'EOF'
/target/
**/*.rs.bk
.env
.env.*
!.env.example
EOF
      ;;
    go)
      cat <<'EOF'
/bin/
/dist/
*.test
*.out
.env
.env.*
!.env.example
EOF
      ;;
    roblox)
      cat <<'EOF'
/build/
*.rbxl
*.rbxlx
*.rbxl.lock
*.rbxlx.lock
sourcemap.json
/Packages/
.env
.env.*
!.env.example
EOF
      ;;
    web)
      cat <<'EOF'
node_modules/
dist/
.cache/
*.log
.env
.env.*
!.env.example
EOF
      ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ arg parsing ---

name=""
root=""
explicit_path=""
claude_cmd=""
initial_prompt=""
session_override=""
github_vis=""
stack=""
assume_yes=0
prompt_given=0
do_git=1
do_readme=1
do_window=1
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    -r | --root) [ $# -ge 2 ] || die "--root needs a value"; root="$2"; shift 2 ;;
    --show-root) resolve_root; printf '\n'; exit 0 ;;
    -p | --path) [ $# -ge 2 ] || die "--path needs a value"; explicit_path="$2"; shift 2 ;;
    -g | --github) [ $# -ge 2 ] || die "--github needs a value"; github_vis="$2"; shift 2 ;;
    --stack) [ $# -ge 2 ] || die "--stack needs a value"; stack="$2"; shift 2 ;;
    -c | --cmd) [ $# -ge 2 ] || die "--cmd needs a value"; claude_cmd="$2"; shift 2 ;;
    -P | --prompt)
      [ $# -ge 2 ] || die "--prompt needs a value"
      initial_prompt="$2"
      prompt_given=1
      shift 2
      ;;
    -s | --session) [ $# -ge 2 ] || die "--session needs a value"; session_override="$2"; shift 2 ;;
    -y | --yes) assume_yes=1; shift ;;
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

if [ -n "$claude_cmd" ]; then
  case "$claude_cmd" in
    ccd | ccds | ccdw | none) ;;
    *) die "--cmd must be one of: ccd, ccds, ccdw, none (got '$claude_cmd')" ;;
  esac
fi

if [ -n "$github_vis" ]; then
  case "$github_vis" in
    private | public | none) ;;
    *) die "--github must be one of: private, public, none (got '$github_vis')" ;;
  esac
fi

if [ -n "$stack" ]; then
  case "$stack" in
    node | python | rust | go | roblox | web | none) ;;
    *) die "--stack must be one of: node, python, rust, go, roblox, web, none (got '$stack')" ;;
  esac
fi

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

# Questions need a terminal on both ends, and are skipped entirely for -y and
# --dry-run. This is what keeps the script safe to call from Claude or cron:
# no TTY, no blocking, everything falls back to its default.
if [ "$assume_yes" -eq 0 ] && [ "$dry_run" -eq 0 ] &&
  [ -t 0 ] && [ -t 1 ] && [ -r /dev/tty ]; then
  interactive=1
fi

# gh is only offered when it can actually succeed.
github_available=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  github_available=1
fi

# ------------------------------------------------------------- questions ----

if prompts_enabled; then
  printf '\n%s → %s\n' "$slug" "$project_dir"
  printf 'tmux session "%s" · Enter accepts the default\n\n' "$session"

  if [ -z "$stack" ]; then
    key="$(ask_choice \
      "  stack?    [n]ode [p]ython [r]ust [g]o [x]roblox [w]eb [s]kip (skip):" \
      "|n|p|r|g|x|w|s|" "s")"
    case "$key" in
      n) stack="node" ;;
      p) stack="python" ;;
      r) stack="rust" ;;
      g) stack="go" ;;
      x) stack="roblox" ;;
      w) stack="web" ;;
      *) stack="none" ;;
    esac
  fi

  if [ -z "$github_vis" ] && [ "$do_git" -eq 1 ]; then
    if [ "$github_available" -eq 1 ]; then
      if [ "$(ask_choice "  github?   [y]es [n]o (no):" "|y|n|" "n")" = "y" ]; then
        # No default here on purpose — visibility is the one answer worth
        # forcing a keystroke for, since guessing it wrong is public code.
        case "$(ask_choice "  visible?  [p]rivate [u]public (no default):" "|p|u|" "")" in
          p) github_vis="private" ;;
          u) github_vis="public" ;;
        esac
      else
        github_vis="none"
      fi
    else
      info "github?   skipped — gh not installed or not logged in"
      github_vis="none"
    fi
  fi

  if [ -z "$claude_cmd" ]; then
    case "$(ask_choice "  claude?   [p]ersonal [s]chool [w]ork [n]one (personal):" \
      "|p|s|w|n|" "p")" in
      p) claude_cmd="ccd" ;;
      s) claude_cmd="ccds" ;;
      w) claude_cmd="ccdw" ;;
      n) claude_cmd="none" ;;
    esac
  fi

  if [ "$prompt_given" -eq 0 ] && [ "$claude_cmd" != "none" ]; then
    initial_prompt="$(ask_line "  first task? (blank = none):")"
  fi
  printf '\n'
fi

# Defaults for everything still unanswered (non-interactive path).
[ -n "$claude_cmd" ] || claude_cmd="$DEFAULT_CMD"
[ -n "$stack" ] || stack="none"
[ -n "$github_vis" ] || github_vis="none"
[ "$do_git" -eq 1 ] || github_vis="none"

if [ "$github_vis" != "none" ] && [ "$github_available" -eq 0 ]; then
  warn "gh unavailable or not logged in — skipping GitHub repo creation"
  github_vis="none"
fi

if [ "$dry_run" -eq 1 ]; then
  cat <<EOF
newproj (dry run)
  directory : $project_dir
  session   : $session
  stack     : $stack
  github    : $github_vis
  claude    : $claude_cmd${initial_prompt:+ "$initial_prompt"}
  git init  : $([ "$do_git" -eq 1 ] && echo yes || echo no)
  readme    : $([ "$do_readme" -eq 1 ] && echo yes || echo no)
  window    : $([ "$do_window" -eq 1 ] && echo yes || echo no)
EOF
  exit 0
fi

# ------------------------------------------------------------- directory ----

step "setting up $slug"

dir_is_new=0
if [ -d "$project_dir" ]; then
  info "directory exists, reusing: $project_dir"
else
  mkdir -p "$project_dir" || die "could not create $project_dir"
  dir_is_new=1
  info "created $project_dir"
fi

if [ "$do_readme" -eq 1 ] && [ ! -e "$project_dir/README.md" ]; then
  printf '# %s\n' "$(basename "$slug")" >"$project_dir/README.md" ||
    warn "could not write README.md"
fi

if [ "$stack" != "none" ] && [ ! -e "$project_dir/.gitignore" ]; then
  if gitignore_for_stack "$stack" >"$project_dir/.gitignore"; then
    info "seeded .gitignore for $stack"
  else
    rm -f "$project_dir/.gitignore"
    warn "no .gitignore template for stack '$stack'"
  fi
fi

# ------------------------------------------------------------------- git ----

if [ "$do_git" -eq 1 ] && ! git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$project_dir" init -b main >/dev/null 2>&1 ||
    git -C "$project_dir" init >/dev/null 2>&1; then
    info "git repo initialized"
  else
    warn "git init failed in $project_dir"
    github_vis="none"
  fi
fi

# ---------------------------------------------------------------- github ----

repo_url=""
if [ "$github_vis" != "none" ]; then
  repo_name="$(basename "$slug")"
  if git -C "$project_dir" remote get-url origin >/dev/null 2>&1; then
    repo_url="$(git -C "$project_dir" remote get-url origin)"
    info "origin already set ($repo_url) — leaving it alone"
  else
    # gh needs something to push. Commit whatever is here; an empty repo with
    # nothing staged would fail the push and leave a bare remote behind.
    if [ -z "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ] &&
      ! git -C "$project_dir" rev-parse HEAD >/dev/null 2>&1; then
      printf '# %s\n' "$repo_name" >"$project_dir/README.md"
    fi
    if ! git -C "$project_dir" rev-parse HEAD >/dev/null 2>&1; then
      git -C "$project_dir" add -A >/dev/null 2>&1 || true
      git -C "$project_dir" commit -q -m "chore: initial commit" >/dev/null 2>&1 ||
        warn "could not create the initial commit"
    fi

    if gh repo create "$repo_name" "--$github_vis" \
      --source "$project_dir" --remote origin --push >/dev/null 2>&1; then
      repo_url="$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)"
      info "github repo created ($github_vis) and pushed${repo_url:+ → $repo_url}"
    else
      # A taken name or a network blip must not cost you the whole session.
      warn "gh repo create failed (name taken? offline?) — local repo is fine, remote skipped"
    fi
  fi
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

  # Hand Claude the stack alongside the task, so it doesn't have to infer it
  # from an empty directory.
  opening="$initial_prompt"
  if [ -n "$opening" ] && [ "$stack" != "none" ]; then
    opening="This is a $stack project. $opening"
  fi

  launch="$claude_cmd"
  [ -n "$opening" ] && launch="$claude_cmd $(shell_quote "$opening")"
  tmux send-keys -t "=$session:claude" "$launch" C-m ||
    warn "could not start $claude_cmd in the session"
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
[ -n "$repo_url" ] && printf '%s\n' "$repo_url"
exit 0
