#!/usr/bin/env bash
# Headless test run for the nvim PDF reader.
#
#   base/nvim/tests/run.sh
#
# `nvim -l` (Lua script mode) rather than `--headless -c luafile`: the latter
# turns any uncaught error into a "Press ENTER" prompt that hangs a CI run
# forever. Script mode writes the error to stderr and exits non-zero.
#
# --clean on purpose: the suite must prove the pdfview module works on its own,
# not that it works alongside 20 plugins on this particular laptop.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"

exec nvim --clean \
  --cmd "set runtimepath^=$root" \
  --cmd "lua package.path = '$here/helpers/?.lua;' .. package.path" \
  -l "$here/pdfview_spec.lua"
