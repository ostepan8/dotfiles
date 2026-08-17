#!/usr/bin/env bash
# roles.sh — read roles/*.role, the single source of truth for what a tier may do.
#
# Everything downstream is generated from these files rather than maintained by
# hand: the Tailscale ACL, the control plane's authorized_keys lines, and the
# `nephos-can` check the shell and the agent skill use. Hand-maintaining any of
# those separately is how a role and its enforcement drift apart — which is
# exactly the failure this repo already had with three copy lists.

role_file() { printf '%s/roles/%s.role' "$DOTFILES" "$1"; }

# role_get <role> <field>
role_get() {
  local f; f="$(role_file "$1")"
  [ -f "$f" ] || return 1
  awk -v k="$2" '!/^[[:space:]]*#/ && $1 == k {
    $1=""; sub(/^[[:space:]]+/, ""); print; exit
  }' "$f"
}

# role_may <role> <action> — is the action in this role's `may` list?
role_may() {
  local a
  for a in $(role_get "$1" may); do
    [ "$a" = "$2" ] && return 0
  done
  return 1
}

# roles_for_host <host-type> — the nephos-* layers that host declares.
roles_for_host() {
  awk -v h="$1" '!/^[[:space:]]*#/ && $1 == h {
    for (i = 2; i <= NF; i++) if ($i ~ /^nephos-/) print $i
  }' "$DOTFILES/hosts/layers.conf"
}

# hosts_with_role <role> — every host type declaring that role.
hosts_with_role() {
  awk -v r="$1" '!/^[[:space:]]*#/ && NF > 1 {
    for (i = 2; i <= NF; i++) if ($i == r) { print $1; break }
  }' "$DOTFILES/hosts/layers.conf"
}

# all_roles — every role that has a file.
all_roles() {
  local f
  for f in "$DOTFILES"/roles/*.role; do
    [ -f "$f" ] || continue
    basename "$f" .role
  done
}
