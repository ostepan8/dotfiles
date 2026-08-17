#!/usr/bin/env bash
# COMPATIBILITY SHIM — remove only after both Macs have run a full sync cycle.
#
# The installed LaunchAgent in ~/Library/LaunchAgents is a COPY of the plist, and
# apply.sh only refreshes that copy when it differs. The old copy runs:
#
#     exec "$HOME/dotfiles/mac/sync.sh"
#
# So on the first pull after the layer restructure, launchd still execs THIS
# path. Without this file the agent would exit before ever reaching apply.sh —
# and apply.sh is the only thing that would install the corrected plist. The fix
# would be sitting in the repo with nothing left running to deliver it, and both
# Macs would need manual repair at the keyboard.
#
# Removal procedure (see docs/RESTRUCTURE-PLAN.md, phase 4):
#   1. confirm ~/Library/Logs/dotfiles-sync.log shows a clean run on BOTH Macs
#   2. confirm ~/Library/LaunchAgents/com.ostepan.dotfiles-sync.plist now execs
#      "$HOME/dotfiles/sync.sh"
#   3. only then delete mac/ entirely
exec "$(cd "$(dirname "$0")/.." && pwd)/sync.sh" "$@"
