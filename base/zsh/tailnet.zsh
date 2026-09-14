# tailnet.zsh — switch between Tailscale profiles without memorising ids.
#
# One account can belong to several tailnets. Tailscale calls each membership a
# "profile", only one is active at a time, and `tailscale switch` wants a 4-char
# opaque id — not something worth remembering. Hence `tn`.
#
# WHY THIS EARNS A HELPER, beyond saving keystrokes: being on the wrong profile
# does not fail like a network problem. A host on another tailnet still
# RESOLVES — Tailscale serves a public wildcard for *.ts.net — and even answers
# ping, so ssh just hangs until it times out, exactly as if the box were down or
# the key were wrong. Bare `tn` printing the active tailnet is the five-second
# way to rule that out before debugging anything else.
#
# Switching by *name* is not an option here: both profiles on this account share
# one nickname and account string, so `tailscale switch <name>` is ambiguous.
# Everything below resolves to an id first.
#
# This repo is PUBLIC, so no tailnet or host names are hardcoded — profiles are
# matched against the live output of `tailscale switch --list`. For friendly
# names, set in ~/.zshrc.local (untracked):
#     typeset -gA TAILNET_ALIASES=( personal 'some-substring' work 'other' )
#
# Note: these Macs run two tailscaled daemons — the GUI app's (default socket,
# owns system DNS) and a Homebrew userspace one on /tmp/tailscaled.sock that a
# couple of ssh ProxyCommands use. `tn` drives the GUI one; the other is left
# alone, so switching does not disturb sessions running over it.

_tn_json()       { tailscale switch --list --json 2>/dev/null }
_tn_suffix()     { tailscale status --json 2>/dev/null | jq -r '.MagicDNSSuffix // empty' }
_tn_current_id() { _tn_json | jq -r '.[] | select(.selected) | .id' }

_tn_show() {
  local tailnet suffix
  tailnet="$(_tn_json | jq -r '.[] | select(.selected) | .tailnet')"
  [[ -n "$tailnet" ]] || { print -u2 "tn: cannot reach tailscaled"; return 1 }
  suffix="$(_tn_suffix)"
  print -- "tailnet: ${tailnet}${suffix:+  (${suffix})}"
}

_tn_list() {
  _tn_json | jq -r 'to_entries[]
    | "\(.key+1)  \(if .value.selected then "*" else " " end)  \(.value.tailnet)"'
}

# <pattern> -> profile id on stdout. Pattern is a list index, or a
# case-insensitive regex matched against the tailnet and nickname.
_tn_resolve() {
  local pattern="$1" json matches
  json="$(_tn_json)"
  [[ -n "$json" ]] || { print -u2 "tn: cannot reach tailscaled"; return 1 }

  if [[ "$pattern" == <-> ]]; then
    local by_index
    by_index="$(jq -r --argjson i "$pattern" '.[$i-1].id // empty' <<<"$json")"
    [[ -n "$by_index" ]] || { print -u2 "tn: no profile #${pattern}"; return 1 }
    print -r -- "$by_index"
    return 0
  fi

  matches="$(jq -r --arg p "$pattern" \
    '.[] | select((.tailnet + " " + .nickname) | test($p; "i")) | .id' <<<"$json")"
  [[ -n "$matches" ]] || { print -u2 "tn: no tailnet matches '${pattern}'"; _tn_list >&2; return 1 }

  local -a ids=("${(@f)matches}")
  if (( ${#ids} > 1 )); then
    print -u2 "tn: '${pattern}' is ambiguous — matches ${#ids} profiles:"
    _tn_list >&2
    return 1
  fi
  print -r -- "${ids[1]}"
}

# The other profile, when there are exactly two — makes `tn -` a toggle.
_tn_other_id() {
  local json current
  json="$(_tn_json)"
  local -a all=("${(@f)$(jq -r '.[].id' <<<"$json")}")
  (( ${#all} == 2 )) || {
    print -u2 "tn: toggle needs exactly 2 profiles (found ${#all}) — pick one:"
    _tn_list >&2
    return 1
  }
  current="$(jq -r '.[] | select(.selected) | .id' <<<"$json")"
  if [[ "${all[1]}" == "$current" ]]; then print -r -- "${all[2]}"
  else                                     print -r -- "${all[1]}"; fi
}

# Does the SYSTEM resolver answer for this name? Not `tailscale status` — the
# point is to exercise the same path ssh will take.
_tn_resolves() {
  if command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "$1" 2>/dev/null | grep -q '_address:'
  else
    getent hosts "$1" >/dev/null 2>&1
  fi
}

# A profile switch tears down and rebuilds the netmap, and macOS reconfigures its
# resolver a beat AFTER the backend reports Running. Returning on Running alone
# is not enough: an `ssh` fired immediately then dies with "could not resolve
# hostname", which looks like a typo rather than a race. So wait for Running and
# then for this node's own MagicDNS name — which is tailnet-specific, so it can
# only answer once the new config is actually live — to resolve.
_tn_wait_up() {
  local i self
  for i in {1..40}; do
    [[ "$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')" == Running ]] && break
    sleep 0.25
  done
  if (( i == 40 )); then
    print -u2 "tn: backend still not Running after 10s — check 'tailscale status'"
    return 1
  fi

  self="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty')"
  self="${self%.}"
  [[ -n "$self" ]] || return 0
  for i in {1..40}; do
    _tn_resolves "$self" && return 0
    sleep 0.25
  done
  print -u2 "tn: MagicDNS not resolving after 10s — names may be stale"
  return 1
}

_tn_help() {
  print -- 'tn — switch Tailscale profiles

  tn                 show the active tailnet
  tn ls              list profiles (* = active)
  tn -               toggle to the other profile
  tn <substring>     switch to the profile whose tailnet matches
  tn <n>             switch to profile #n from `tn ls`

Friendly names come from $TAILNET_ALIASES, set in ~/.zshrc.local.'
}

tn() {
  command -v tailscale >/dev/null || { print -u2 "tn: tailscale is not installed"; return 1 }
  command -v jq        >/dev/null || { print -u2 "tn: jq is not installed"; return 1 }

  local id
  case "${1:-}" in
    '')             _tn_show; return ;;
    ls|list)        _tn_list; return ;;
    -h|--help|help) _tn_help; return ;;
    -|t|toggle)     id="$(_tn_other_id)" || return 1 ;;
    *)
      local key="$1"
      if (( ${+TAILNET_ALIASES} )) && [[ -n "${TAILNET_ALIASES[$1]:-}" ]]; then
        key="${TAILNET_ALIASES[$1]}"
      fi
      id="$(_tn_resolve "$key")" || return 1
      ;;
  esac

  # Already there: report, don't churn the netmap for nothing.
  [[ "$id" == "$(_tn_current_id)" ]] && { _tn_show; return 0 }

  tailscale switch "$id" >/dev/null 2>&1 || { print -u2 "tn: switch to ${id} failed"; return 1 }
  _tn_wait_up
  _tn_show
}

# A record for <host>, via the system resolver — the same path ssh uses.
_tn_addrs() {
  if command -v dscacheutil >/dev/null 2>&1; then
    dscacheutil -q host -a name "$1" 2>/dev/null | awk '/^ip_address:/ {print $2}'
  else
    getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u
  fi
}

# Wait until <host> resolves to a tailnet address (CGNAT 100.64.0.0/10).
#
# Checking merely that it RESOLVES is not enough, because both ways of getting
# this wrong still produce an answer:
#   - mid-switch, the resolver briefly returns nothing and ssh reports "could
#     not resolve hostname", which reads like a typo;
#   - from the wrong profile, *.ts.net resolves to Tailscale's PUBLIC wildcard
#     and even answers ping, so ssh hangs to a timeout as if the box were down.
# Demanding a 100.64/10 address rules out both.
tn_await() {
  local i
  for i in {1..40}; do
    _tn_addrs "$1" | grep -qE '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' && return 0
    sleep 0.25
  done
  print -u2 "tn: ${1} is not resolving to a tailnet address — wrong profile, or DNS is stale"
  return 1
}

# tn_ensure <pattern> [host] — switch only if not already on that tailnet, and
# say so when it happens. Used by wrappers (see ~/.zshrc.local) that ssh to a
# host on a specific tailnet. Silent on the no-op path; a switch is a global
# change and should be visible. Pass <host> to also block until it is reachable.
tn_ensure() {
  local id switched=0
  id="$(_tn_resolve "$1")" || return 1
  if [[ "$id" != "$(_tn_current_id)" ]]; then
    tailscale switch "$id" >/dev/null 2>&1 || { print -u2 "tn: switch to ${id} failed"; return 1 }
    _tn_wait_up
    switched=1
  fi
  [[ -n "${2:-}" ]] && { tn_await "$2" || return 1 }
  (( switched )) && print -u2 "→ $(_tn_show)"
  return 0
}

# Completion: static subcommands, live tailnet names, and any friendly aliases.
if (( ${+functions[compdef]} )); then
  _tn_completions() {
    local -a candidates
    candidates=(ls toggle -)
    (( ${+TAILNET_ALIASES} )) && candidates+=("${(@k)TAILNET_ALIASES}")
    candidates+=("${(@f)$(_tn_json | jq -r '.[].tailnet' 2>/dev/null)}")
    compadd -- "${(@)candidates:#}"
  }
  compdef _tn_completions tn
fi
