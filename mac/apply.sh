#!/usr/bin/env bash
# COMPATIBILITY SHIM — remove alongside mac/sync.sh.
#
# The real implementation is now ../apply.sh, driven by ../manifest.conf. This
# path is kept alive only because anything still holding the pre-restructure
# layout — an old installed LaunchAgent, a shell alias, muscle memory — would
# otherwise fail silently.
#
# See mac/sync.sh for the removal procedure.
exec "$(cd "$(dirname "$0")/.." && pwd)/apply.sh" "$@"
