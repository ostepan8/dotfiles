#!/usr/bin/env bash
# harden-node-key.sh — pin a worker node's control-plane SSH key to one command.
#
# This is the ONLY real enforcement in the tier model. The layer names in
# hosts/layers.conf are a declaration; this is the boundary. Without it, any
# node holding a control-plane key can run `nephos keys new` and mint whatever
# it likes, no matter what the dotfiles say.
#
# Run this ON THE CONTROL PLANE, once per node key. It prints the line to use —
# it does not edit authorized_keys for you, because getting that wrong locks you
# out of your own control plane.
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

cat <<EOF

Add this to the control plane's ~/.ssh/authorized_keys — as ONE line:

command="\${HOME}/bin/nephos node-agent --node=$NODE",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding $KEY

What each part buys you:

  command=          the node can run ONLY this. Whatever it asks for on the
                    command line is ignored, so 'ssh control nephos keys new'
                    runs node-agent instead of minting a key.
  no-pty            no interactive shell to escape into.
  no-*-forwarding   the node cannot tunnel through the control plane to reach
                    anything else on the tailnet.
  no-user-rc        ~/.ssh/rc cannot be used to run something else first.

Verify from the node afterwards — this MUST fail:

    ssh $NODE-control "nephos keys new anything"

If it succeeds, the key was appended without the command= prefix, or a second
unrestricted entry for the same key is still present. Check for duplicates:

    grep -c "\$(awk '{print \$2}' <<< "$KEY")" ~/.ssh/authorized_keys

Keeper and operator keys are deliberately NOT hardened this way — provisioning
is their job.

EOF
