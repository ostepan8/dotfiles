#!/usr/bin/env bash
# Render clangd/config.yaml for this machine.
#
# Points the editor at Homebrew GCC's libstdc++ so <bits/stdc++.h> and pbds
# resolve for competitive-programming C++. Paths are computed from the installed
# GCC so this survives version bumps, and the result lands at the macOS-specific
# clangd location (~/Library/Preferences/clangd), NOT ~/.config/clangd.
set -uo pipefail

[ -d /opt/homebrew/opt/gcc/include/c++ ] || exit 0

GCXX="$(ls -d /opt/homebrew/opt/gcc/include/c++/[0-9]* 2>/dev/null | sort -V | tail -1)"
[ -n "$GCXX" ] || exit 0
GTRIPLE="$(ls -d "$GCXX"/*-apple-darwin*/ 2>/dev/null | head -1)"
[ -n "$GTRIPLE" ] || exit 0

rendered="$(sed -e "s|__GCXX__|$GCXX|g" -e "s|__GTRIPLE__|${GTRIPLE%/}|g" "$RENDER_SRC")"

# Idempotent: only write when the result actually differs.
if [ -f "$RENDER_DEST" ] && [ "$rendered" = "$(cat "$RENDER_DEST")" ]; then
  exit 0
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "  render $RENDER_DEST"
  exit 0
fi

mkdir -p "$(dirname "$RENDER_DEST")"
printf '%s\n' "$rendered" > "$RENDER_DEST"
echo "  render $RENDER_DEST (GCC libstdc++ at $GCXX)"
