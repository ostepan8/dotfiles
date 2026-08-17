#!/usr/bin/env bash
# setup.sh — re-run the interview on demand, without a full install.
#
# Use to configure something that was skipped (an install over SSH with no
# terminal), or to set up a tier on a machine that has been rebuilt.
set -uo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
export DOTFILES

. "$DOTFILES/lib/reloads.sh"
. "$DOTFILES/lib/engine.sh"
. "$DOTFILES/lib/setup.sh"

ACTIVE_LAYERS="$(resolve_layers)"
export ACTIVE_LAYERS

echo "layers: $ACTIVE_LAYERS"
run_setup_scripts
echo "done."
