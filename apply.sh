#!/usr/bin/env bash
# apply.sh — put every managed config where it belongs, for THIS machine.
#
# Idempotent and safe to re-run: a machine that is already set up should see no
# changes and no service reloads. Runs from launchd every 30 min via sync.sh, and
# by hand any time.
#
#   ./apply.sh              apply
#   ./apply.sh --dry-run    report what would change, touch nothing
#   ./apply.sh --prune      also delete tree entries the repo no longer has
#                           (combine with --dry-run first — always)
#   ./apply.sh --layers     show which layers this machine resolves to
#
# Which files go where is data, not code: see manifest.conf.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES

. "$DOTFILES/lib/reloads.sh"
. "$DOTFILES/lib/engine.sh"

DRY_RUN=0
PRUNE=0
# A loop, not a single case on $1: --prune is only safe to try if it can be
# combined with --dry-run, and the one-argument form silently ignored the
# second flag — so `--prune --dry-run` deleted for real.
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY_RUN=1 ;;
    --prune)      PRUNE=1 ;;
    --layers)     resolve_layers; exit 0 ;;
    "")           ;;
    *)            echo "usage: apply.sh [--dry-run|-n] [--prune] [--layers]" >&2; exit 2 ;;
  esac
  shift
done
export DRY_RUN PRUNE

ACTIVE_LAYERS="$(resolve_layers)"
export ACTIVE_LAYERS

echo "[apply] $([ "$DRY_RUN" = 1 ] && echo 'DRY RUN — ')layers: $ACTIVE_LAYERS"

if ! apply_manifest; then
  echo "[apply] failed" >&2
  exit 1
fi

if [ "${CHANGES:-0}" -eq 0 ]; then
  echo "[apply] already up to date"
else
  echo "[apply] $CHANGES change(s)"
fi
