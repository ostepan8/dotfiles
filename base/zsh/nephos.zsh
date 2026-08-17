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

[ -f "$HOME/.config/nephos/env" ] || return 0
set -a; . "$HOME/.config/nephos/env"; set +a

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

_nephos_require() {
  if [ -z "${NEPHOS_CONTROL_HOST:-}" ]; then
    echo "nephos: no NEPHOS_CONTROL_HOST — is ~/.config/nephos/env set up?" >&2
    return 1
  fi
  if command -v tailscale >/dev/null 2>&1 && ! tailscale status >/dev/null 2>&1; then
    echo "nephos: tailscale is down — the control plane is unreachable" >&2
    return 1
  fi
  return 0
}

# nephos-env <app> — fetch this app's credentials and export them here.
nephos-env() {
  local app="${1:-}"
  [ -z "$app" ] && { echo "usage: nephos-env <app>" >&2; return 2; }
  _nephos_require || return 1

  local out
  if ! out="$(ssh "$NEPHOS_CONTROL_HOST" "$NEPHOS_BIN keys show $app --env" 2>&1)"; then
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

# nephos-provision <app> — mint credentials. Keeper and operator only; a node's
# control-plane key is force-command pinned, so this fails there by design
# rather than by politeness.
nephos-provision() {
  local app="${1:-}"
  [ -z "$app" ] && { echo "usage: nephos-provision <app>" >&2; return 2; }
  local tier; tier="$(nephos-tier)"
  case "$tier" in
    keeper|operator) ;;
    *) echo "nephos: tier '$tier' does not provision" >&2; return 1 ;;
  esac
  _nephos_require || return 1
  ssh "$NEPHOS_CONTROL_HOST" "$NEPHOS_BIN keys new $app"
}
