#!/usr/bin/env bash
# Reset the focused workspace to a clean tiled layout.
# Bound to alt-shift-t. Every window on the workspace stops floating, the
# container tree is flattened (this clears any accordion), the root is set to
# horizontal tiles and the sizes are balanced. Focus returns to the window that
# had it before.

set -u

AERO=/opt/homebrew/bin/aerospace

WS=$("$AERO" list-workspaces --focused 2>/dev/null) || exit 1
[ -n "$WS" ] || exit 0

FOCUSED=$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null || true)
WINDOWS=$("$AERO" list-windows --workspace "$WS" --format '%{window-id}' 2>/dev/null)
[ -n "$WINDOWS" ] || exit 0

for id in $WINDOWS; do
    "$AERO" layout --window-id "$id" tiling 2>/dev/null || true
done

"$AERO" flatten-workspace-tree --workspace "$WS"

FIRST=$(printf '%s\n' "$WINDOWS" | head -1)
"$AERO" layout --window-id "$FIRST" tiles horizontal 2>/dev/null || true
"$AERO" balance-sizes --workspace "$WS" 2>/dev/null || true

if [ -n "$FOCUSED" ]; then
    "$AERO" focus --window-id "$FOCUSED" 2>/dev/null || true
fi
