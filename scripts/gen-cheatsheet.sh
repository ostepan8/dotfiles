#!/usr/bin/env bash
# gen-cheatsheet.sh — render the keybinding sections of docs/cheatsheet.html
# from docs/keys.tsv.
#
# Only the KEYBINDING sections are generated. The prose sections (aliases, Cloud,
# local models) stay hand-written, because nothing about them is derivable and
# rewriting them would be churn for its own sake.
#
# The point is that a key and its description live in exactly one place. The
# hand-maintained version had already drifted: it documented Alt+, as "Accordion
# layout" long after aerospace.toml stopped binding it, and knew nothing about
# any key added since.
#
#   --check   exit non-zero if the file on disk differs from what would be
#             generated, without writing. Used by doctor.
set -uo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-write}"
exec python3 "$DOTFILES/scripts/gen_cheatsheet.py" "$MODE"
