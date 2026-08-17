#!/usr/bin/env bash
# setup.sh — run the interview scripts for this machine's active layers.
#
# Each script in setup.d/ declares which layers it applies to in a header:
#
#     # layers: base
#     # layers: nephos-keeper nephos-operator nephos-node
#
# It runs if ANY listed layer is active. Contract for each script:
#
#   - exit 0 quietly when already configured (these run on every install)
#   - write ONLY to ~/.config/... — never to the repo, which is public
#   - ask nothing when there is no terminal
#
# That last rule matters: install.sh runs from automation and over SSH, and a
# script blocking on read() would hang a machine build forever with no output
# explaining why. Non-interactive runs report what still needs configuring and
# move on.

setup_is_interactive() { [ -t 0 ] && [ -t 1 ]; }

# ask <var> <prompt> [default]
ask() {
  local __var="$1" __prompt="$2" __default="${3:-}" __reply=""
  if ! setup_is_interactive; then
    SETUP_DEFERRED=1
    return 1
  fi
  if [ -n "$__default" ]; then
    printf '    %s [%s]: ' "$__prompt" "$__default" >&2
  else
    printf '    %s: ' "$__prompt" >&2
  fi
  read -r __reply
  [ -z "$__reply" ] && __reply="$__default"
  [ -z "$__reply" ] && return 1
  printf -v "$__var" '%s' "$__reply"
  return 0
}

# ask_secret <var> <prompt> — same, but no echo
ask_secret() {
  local __var="$1" __prompt="$2" __reply=""
  setup_is_interactive || { SETUP_DEFERRED=1; return 1; }
  printf '    %s: ' "$__prompt" >&2
  read -rs __reply
  echo >&2
  [ -z "$__reply" ] && return 1
  printf -v "$__var" '%s' "$__reply"
  return 0
}

script_layers() {
  sed -n 's/^# layers:[[:space:]]*//p' "$1" | head -1
}

run_setup_scripts() {
  local dir="$DOTFILES/setup.d" script wants want ran=0
  [ -d "$dir" ] || return 0

  SETUP_DEFERRED=0
  for script in "$dir"/*.sh; do
    [ -f "$script" ] || continue
    wants="$(script_layers "$script")"
    [ -z "$wants" ] && continue

    local match=0
    for want in $wants; do
      layer_active "$want" && { match=1; break; }
    done
    [ "$match" = "1" ] || continue

    ran=1
    # shellcheck disable=SC1090
    . "$script"
  done

  if [ "${SETUP_DEFERRED:-0}" = "1" ]; then
    echo
    echo "  Some setup needs answers and there is no terminal here."
    echo "  Run it interactively when you can:   make setup"
  fi
  return 0
}
