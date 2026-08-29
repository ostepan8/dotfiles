#!/usr/bin/env bash
#
# Shared helpers for claude-local / claude-local-setup.
#
# The central idea: no Ollama tag is usable by Claude Code as published,
# because Ollama runs every model at num_ctx=4096 regardless of what the
# weights support. So for any base tag we transparently maintain a derived
# "<tag>-cc" sibling whose only difference is a large context window. Deriving
# is instant and layer-deduplicated — the big weight blob is never copied.

CC_SUFFIX="-cc"
DEFAULT_CTX="${CLAUDE_LOCAL_CTX:-65536}"
STATE_FILE="${CLAUDE_LOCAL_STATE:-$HOME/.claude-local/model}"

cl_die()  { printf '\033[31m%s:\033[0m %s\n' "${0##*/}" "$*" >&2; exit 1; }
cl_note() { printf '\033[2m%s:\033[0m %s\n' "${0##*/}" "$*" >&2; }
cl_step() { printf '\033[1m==>\033[0m %s\n' "$*" >&2; }

# Every installed tag, excluding the derived ones (which are an implementation
# detail the user should never have to pick from).
cl_base_models() {
  ollama list 2>/dev/null | awk 'NR>1 && $1 != "" {print $1}' | grep -v -- "${CC_SUFFIX}\$" || true
}

cl_model_exists() { ollama show "$1" >/dev/null 2>&1; }

# Is this word an installed tag? Used to tell a bare model argument apart from
# a prompt. Matched against the actual list rather than by shape: a tag looks
# like ordinary text, so any pattern guess would misfire in both directions.
cl_is_installed_tag() {
  [[ -n "$1" ]] || return 1
  ollama list 2>/dev/null | awk -v t="$1" 'NR>1 && $1 == t {found=1} END {exit !found}'
}

cl_is_derived() { [[ "$1" == *"${CC_SUFFIX}" ]]; }

# Strip the suffix so passing an already-derived tag is idempotent rather than
# producing qwen3.6:35b-a3b-cc-cc.
cl_base_of() { printf '%s' "${1%${CC_SUFFIX}}"; }

cl_derived_of() { printf '%s%s' "$(cl_base_of "$1")" "$CC_SUFFIX"; }

# num_ctx currently baked into a tag, or empty. Ollama prints parameters as
# two whitespace-separated columns under a "Parameters" heading.
cl_ctx_of() {
  ollama show "$1" 2>/dev/null | awk '$1=="num_ctx" {print $2; exit}'
}

# Build (or rebuild) <base>-cc at the requested context length. A no-op when
# the derived tag already exists at that exact length, so this is cheap enough
# to call on every launch.
cl_ensure_derived() {
  local base derived ctx
  base="$(cl_base_of "$1")"
  ctx="${2:-$DEFAULT_CTX}"
  derived="$(cl_derived_of "$base")"

  cl_model_exists "$base" || cl_die "base model '$base' is not installed.
    Install it with:  ollama pull $base
    Or list what you have:  claude-local --list"

  if [[ "$(cl_ctx_of "$derived")" == "$ctx" ]]; then
    printf '%s' "$derived"; return 0
  fi

  cl_step "Deriving $derived (num_ctx=$ctx) from $base"
  # A real temp file rather than stdin: `ollama create -f -` reports "no
  # Modelfile or safetensors files found" instead of reading the pipe.
  #
  # Sampling parameters are left to the base model on purpose: they are tuned
  # per-model upstream, and overriding them uniformly here would be a guess.
  local tmp err
  tmp="$(mktemp -t claude-local-modelfile)"
  printf 'FROM %s\nPARAMETER num_ctx %s\n' "$base" "$ctx" > "$tmp"
  if ! err="$(ollama create "$derived" -f "$tmp" 2>&1)"; then
    rm -f "$tmp"
    cl_die "ollama create failed for $derived: $err"
  fi
  rm -f "$tmp"
  printf '%s' "$derived"
}

# Interactive picker. fzf when present, numbered menu otherwise, so this still
# works over a bare ssh session on a machine without fzf installed.
cl_pick_model() {
  local models choice
  models="$(cl_base_models)"
  [[ -n "$models" ]] || cl_die "no Ollama models installed (try: ollama pull qwen3.8:27b)"

  if command -v fzf >/dev/null 2>&1; then
    choice="$(printf '%s\n' "$models" \
      | fzf --height=40% --reverse --prompt='local model > ' \
            --header='Model for Claude Code')" || return 1
  else
    printf '%s\n' "$models" | nl -w2 -s') ' >&2
    printf 'model number: ' >&2
    local n; read -r n
    choice="$(printf '%s\n' "$models" | sed -n "${n}p")"
  fi
  [[ -n "$choice" ]] || return 1
  printf '%s' "$choice"
}

cl_saved_model() { [[ -f "$STATE_FILE" ]] && tr -d '[:space:]' < "$STATE_FILE"; }

cl_save_model() {
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$1" > "$STATE_FILE"
}

# Resolution order, most explicit first. Falls back to the largest installed
# model rather than an arbitrary one, since a bigger model is the likelier
# intent for a coding agent.
cl_resolve_model() {
  local m
  m="${CLAUDE_LOCAL_MODEL:-}"
  [[ -z "$m" ]] && m="$(cl_saved_model || true)"
  if [[ -z "$m" ]]; then
    m="$(ollama list 2>/dev/null \
         | awk 'NR>1 && $1 != "" {print $3, $4, $1}' \
         | grep -v -- "${CC_SUFFIX} \$" \
         | sort -rn | head -1 | awk '{print $3}')"
  fi
  [[ -n "$m" ]] || cl_die "no model selected and none installed"
  printf '%s' "$m"
}

# Ollama is normally the menubar app on macOS; a stopped server after a reboot
# is the common case, so start it and wait rather than just failing.
cl_ensure_server() {
  local host="$1"
  curl -fsS --max-time 2 "$host/api/tags" >/dev/null 2>&1 && return 0
  cl_note "Ollama not responding at $host — starting it"
  if [[ "$(uname -s)" == "Darwin" && -d /Applications/Ollama.app ]]; then
    open -a Ollama
  else
    ollama serve >/dev/null 2>&1 &
  fi
  local i
  for i in $(seq 1 30); do
    curl -fsS --max-time 2 "$host/api/tags" >/dev/null 2>&1 && return 0
    sleep 1
  done
  cl_die "Ollama still unreachable at $host after 30s"
}
