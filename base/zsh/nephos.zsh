# nephos shell helpers — sourced by zshrc when ~/.config/nephos/env exists.
#
# Credentials are fetched on demand and exported into the CURRENT SHELL. Nothing
# is written to disk, which is the point: only the keeper (the Studio) holds
# anything long-lived.
#
# Understand the tradeoff you are getting. Environment variables are readable by
# every child process and by anything running as you, and they survive in the
# shell for as long as it lives. That is strictly better than a file at rest,
# but it is not a secret manager — use `nephos-unenv` when you are done, and do
# not export credentials in a shell you are screen-sharing.

# Load this machine's endpoints if it has them. Deliberately NOT an early return
# for the whole file: what a machine is ALLOWED to do is a property of its role,
# not of whether it has been pointed at a control plane yet. On a machine that
# is not set up, `nephos-role` should still answer — the setup interview and the
# agent skill both ask before anything is configured. Only the operational
# commands need the env, and they say so when it is missing.
[ -f "$HOME/.config/nephos/env" ] && { set -a; . "$HOME/.config/nephos/env"; set +a; }

# nephos-tier — what this machine is allowed to do.
#
# NEPHOS_TIER comes from ~/.config/nephos/env, but env files written before the
# tier model existed do not have it. Rather than defaulting to the most
# restrictive tier — which would make the keeper refuse to provision on its own
# machine — derive it from the layer set, which is the actual source of truth.
nephos-tier() {
  if [ -n "${NEPHOS_TIER:-}" ]; then
    echo "$NEPHOS_TIER"
    return 0
  fi
  local host layers
  [ -f "$HOME/.dotfiles-host" ] || { echo unknown; return 0; }
  host="$(tr -d '[:space:]' < "$HOME/.dotfiles-host")"
  layers="$(awk -v h="$host" '!/^[[:space:]]*#/ && $1 == h { print }' \
    "$HOME/dotfiles/hosts/layers.conf" 2>/dev/null)"
  case "$layers" in
    *nephos-keeper*)   echo keeper ;;
    *nephos-operator*) echo operator ;;
    *nephos-node*)     echo node ;;
    *)                 echo unknown ;;
  esac
}

# nephos-can <action> — may THIS machine do that?
#
# Reads roles/<tier>.role, the same file the Tailscale ACL and the
# authorized_keys lines are generated from. One source, so the shell guardrail
# cannot say yes to something the network denies.
nephos-can() {
  local action="${1:-}" tier role_file a
  [ -z "$action" ] && { echo "usage: nephos-can <action>" >&2; return 2; }
  tier="$(nephos-tier)"
  role_file="$HOME/dotfiles/roles/nephos-$tier.role"
  [ -f "$role_file" ] || return 1
  for a in $(awk '!/^[[:space:]]*#/ && $1 == "may" { $1=""; print }' "$role_file"); do
    [ "$a" = "$action" ] && return 0
  done
  return 1
}

# nephos-role — what this machine is, and what that permits.
nephos-role() {
  local tier; tier="$(nephos-tier)"
  local f="$HOME/dotfiles/roles/nephos-$tier.role"
  if [ ! -f "$f" ]; then echo "tier: $tier (no role file)"; return 0; fi
  awk '!/^[[:space:]]*#/ && NF { printf "%-14s %s\n", $1, substr($0, index($0,$2)) }' "$f"
}

_nephos_require() {
  if [ ! -f "$HOME/.config/nephos/env" ]; then
    echo "nephos: not set up on this machine (no ~/.config/nephos/env) — run: make setup" >&2
    return 1
  fi
  if command -v tailscale >/dev/null 2>&1 && ! tailscale status >/dev/null 2>&1; then
    echo "nephos: tailscale is down — the control plane is unreachable" >&2
    return 1
  fi
  return 0
}

# Run a nephos command the way THIS machine reaches the control plane.
#
# Prefer the local CLI: the wrapper points --control at the fleet control plane
# over the tailnet, so it works from cron and scripts too. Only fall back to ssh
# when the binary is genuinely absent. Hardcoding ssh was wrong — on machines
# that have the CLI it adds a pointless hop and fails if sshd is not reachable
# even though the control API is.
_nephos_run() {
  if command -v nephos >/dev/null 2>&1; then
    nephos "$@"
  elif [ -n "${NEPHOS_CONTROL_HOST:-}" ]; then
    ssh "$NEPHOS_CONTROL_HOST" "${NEPHOS_BIN:-nephos} $*"
  else
    echo "nephos: no local CLI and no NEPHOS_CONTROL_HOST — is this machine set up?" >&2
    return 1
  fi
}

# nephos-env <app> — fetch this app's credentials and export them here.
nephos-env() {
  local app="${1:-}"
  [ -z "$app" ] && { echo "usage: nephos-env <app>" >&2; return 2; }
  _nephos_require || return 1

  local out
  if ! out="$(_nephos_run keys show "$app" --env 2>&1)"; then
    echo "nephos: could not fetch credentials for '$app'" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi

  # Expect KEY=VALUE lines. Export without echoing any value.
  local n=0 line
  while IFS= read -r line; do
    case "$line" in
      ''|\#*) continue ;;
      *=*) export "${line?}"; NEPHOS_EXPORTED="${NEPHOS_EXPORTED:-} ${line%%=*}"; n=$((n+1)) ;;
    esac
  done <<< "$out"

  export NEPHOS_EXPORTED
  echo "nephos: exported $n variable(s) for '$app' — this shell only"
}

# nephos-unenv — drop everything nephos-env exported.
nephos-unenv() {
  local v n=0
  for v in ${NEPHOS_EXPORTED:-}; do unset "$v"; n=$((n+1)); done
  unset NEPHOS_EXPORTED
  echo "nephos: cleared $n variable(s)"
}

# nephos-provision <app> — mint credentials. Keeper and operator only.
#
# This check is a guardrail, NOT a security boundary. It stops an absent-minded
# `nephos-provision` on a worker node; it does not stop anything determined,
# because the control plane is reachable over the tailnet on its HTTP port and
# the CLI can be invoked directly. Real enforcement has to live at the control
# plane or in the Tailscale ACL — see scripts/harden-node-key.sh.
nephos-provision() {
  local app="${1:-}"
  [ -z "$app" ] && { echo "usage: nephos-provision <app>" >&2; return 2; }
  if ! nephos-can provision; then
    echo "nephos: role '$(nephos-tier)' does not provision — run this from the keeper" >&2
    return 1
  fi
  _nephos_require || return 1
  _nephos_run keys new "$app"
}
