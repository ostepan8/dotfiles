#!/usr/bin/env bash
# harden-node-key.sh — restrict what a worker node can do.
#
# READ THIS FIRST. An earlier version of this script claimed that pinning a
# node's SSH key to a force-command was the enforcement boundary for the tier
# model. That was wrong, and the mistake is worth stating plainly because it is
# the kind that produces false confidence:
#
#   The control plane is reached over HTTP on the tailnet (NEPHOS_CONTROL_ADDR,
#   port 7930), NOT over SSH. The `nephos` CLI wrapper points itself at that
#   address. So a node holding the binary and tailnet reachability can call the
#   control API directly, and no authorized_keys restriction touches that path.
#
# The boundary has to be one of these, in rough order of preference:
#
#   1. TAILSCALE ACL — the natural fit, since every node is already on the
#      tailnet. Deny node hosts access to the control plane's port entirely:
#
#        "acls": [
#          { "action": "accept", "src": ["tag:keeper", "tag:operator"],
#            "dst": ["tag:control:7930"] },
#          { "action": "accept", "src": ["tag:node"],
#            "dst": ["tag:control:0"] }        // nothing on 7930
#        ]
#
#      Tag the machines, then a node cannot even open the socket. This is the
#      one to do.
#
#   2. CONTROL-PLANE AUTHZ — per-caller tokens with scopes, checked by the
#      nephos binary itself. Strongest and survives a network mistake, but it is
#      server-side work.
#
#   3. SSH force-command (below) — defense in depth ONLY. Worth doing if nodes
#      also have shell access to the control plane, since it closes that second
#      path. It closes nothing on its own.
#
# Run on the control plane, once per node key. It prints the line rather than
# editing authorized_keys, because getting that wrong locks you out.
#
#   ./harden-node-key.sh gpu1 ~/.ssh/gpu1_id_ed25519.pub
set -uo pipefail

NODE="${1:-}"
PUBKEY="${2:-}"

if [ -z "$NODE" ] || [ -z "$PUBKEY" ]; then
  echo "usage: harden-node-key.sh <node-name> <path-to-node-public-key>" >&2
  exit 2
fi
[ -f "$PUBKEY" ] || { echo "no such key: $PUBKEY" >&2; exit 1; }

KEY="$(tr -d '\n' < "$PUBKEY")"
FINGERPRINT="$(awk '{print $2}' <<< "$KEY")"

cat <<EOF

STEP 1 (the actual boundary) — Tailscale ACL

  Tag this node and deny it the control plane's port. Until you do, the SSH
  restriction below is cosmetic: the node can reach the control API directly.

STEP 2 (defense in depth) — pin the SSH key

  Add to the control plane's ~/.ssh/authorized_keys, as ONE line:

command="\${HOME}/bin/nephos node-agent --node=$NODE",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding $KEY

  command=          only this runs; whatever the client asks for is ignored
  no-pty            no interactive shell to escape into
  no-*-forwarding   the node cannot tunnel onward through the control plane
  no-user-rc        ~/.ssh/rc cannot run something else first

STEP 3 — verify BOTH paths are closed

  From the node, each of these must fail:

    ssh $NODE-control "nephos keys new anything"     # SSH path
    nephos keys new anything                         # HTTP path (needs the ACL)

  If the second still succeeds, the ACL is not in place and the node can
  provision regardless of the SSH restriction.

  Check for a duplicate unrestricted entry for the same key:

    grep -c "$FINGERPRINT" ~/.ssh/authorized_keys

  More than one match means an older, unrestricted line is still active.

Keeper and operator keys are deliberately NOT restricted — provisioning is
their job.

EOF
