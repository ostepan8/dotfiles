#!/usr/bin/env bash
# harden-node-key.sh — emit the control plane's authorized_keys line for a node.
#
# Derived from roles/<role>.role (the ssh_command field), so changing what a
# role may do changes this output. Nothing here is hand-maintained.
#
# THIS IS DEFENSE IN DEPTH, NOT THE BOUNDARY. The control plane is reached over
# HTTP on the tailnet, so a node that can open that port can provision whatever
# the SSH config says. The boundary is the Tailscale ACL —
# scripts/gen-nephos-acl.sh. Do that one first; this closes the second path.
#
#   ./scripts/harden-node-key.sh gpu1 ~/.ssh/gpu1.pub
set -uo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
export DOTFILES
. "$DOTFILES/lib/roles.sh"

NODE="${1:-}"
PUBKEY="${2:-}"

if [ -z "$NODE" ] || [ -z "$PUBKEY" ]; then
  echo "usage: harden-node-key.sh <host-type> <path-to-public-key>" >&2
  echo >&2
  echo "known host types and their roles:" >&2
  awk '!/^[[:space:]]*#/ && NF > 1 { printf "  %-10s", $1;
       for (i=2;i<=NF;i++) if ($i ~ /^nephos-/) printf " %s", $i; print "" }' \
    "$DOTFILES/hosts/layers.conf" >&2
  exit 2
fi
[ -f "$PUBKEY" ] || { echo "no such key: $PUBKEY" >&2; exit 1; }

ROLE="$(roles_for_host "$NODE" | head -1)"
if [ -z "$ROLE" ]; then
  echo "$NODE declares no nephos-* role in hosts/layers.conf" >&2
  exit 1
fi

CMD="$(role_get "$ROLE" ssh_command)"
KEY="$(tr -d '\n' < "$PUBKEY")"
FP="$(awk '{print $2}' <<< "$KEY")"

echo
echo "host:  $NODE"
echo "role:  $ROLE — $(role_get "$ROLE" summary)"
echo "may:   $(role_get "$ROLE" may)"
echo

if [ "$CMD" = "-" ]; then
  cat <<EOF
This role has no ssh_command restriction — provisioning is its job. Install the
key normally, with no command= prefix.

EOF
  exit 0
fi

# Substitute the role template's placeholder.
CMD="${CMD//%NODE%/$NODE}"

cat <<EOF
STEP 1 — Tailscale ACL (the actual boundary)

  ./scripts/gen-nephos-acl.sh

  Until tag:$ROLE is denied the control port, the line below changes nothing
  that matters: this host can still reach the control API directly.

STEP 2 — pin the key, on the control plane's ~/.ssh/authorized_keys, ONE line:

command="$CMD",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding $KEY

STEP 3 — verify BOTH paths, from $NODE. Each must fail:

    ssh <control-host> "nephos keys new probe"    # SSH path (step 2)
    nephos keys new probe                          # HTTP path (step 1)

  If the second succeeds, the ACL is not applied. That is the one that counts.

  A duplicate unrestricted entry silently defeats step 2 — check:

    grep -c "$FP" ~/.ssh/authorized_keys

  More than one match means an older line is still active.

EOF
