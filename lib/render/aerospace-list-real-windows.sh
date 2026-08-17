#!/usr/bin/env bash
# Build the phantom-window watchdog helper.
#
# A Swift program that asks each running app via the AX API how many windows it
# really has, so cleanup-phantoms.sh can detect stale-window phantoms (process
# alive, window already closed). Compiled eagerly here so the first cleanup after
# setup is fast; cleanup-phantoms.sh lazy-compiles it otherwise.
set -uo pipefail

command -v swiftc >/dev/null 2>&1 || exit 0

src_live="$(dirname "$RENDER_DEST")/$(basename "$RENDER_SRC")"

# Recompile only when the source actually moved.
if [ -f "$src_live" ] && [ -x "$RENDER_DEST" ] && cmp -s "$RENDER_SRC" "$src_live"; then
  exit 0
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "  render $RENDER_DEST (compile)"
  exit 0
fi

mkdir -p "$(dirname "$RENDER_DEST")"
cp -f "$RENDER_SRC" "$src_live"

# Remove any stale Swift display-watcher binary from earlier iterations. The
# watcher is a bash polling loop now: CoreGraphics reconfiguration callbacks
# silently drop events when fired from a launchd context.
rm -f "$(dirname "$RENDER_DEST")/display-watcher" \
      "$(dirname "$RENDER_DEST")/display-watcher.swift"

if swiftc -O "$src_live" -o "$RENDER_DEST" 2>/dev/null; then
  echo "  render $RENDER_DEST (compiled)"
else
  echo "  WARN: swiftc failed for $src_live — cleanup-phantoms.sh will lazy-compile"
fi
