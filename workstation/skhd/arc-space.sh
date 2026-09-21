#!/usr/bin/env bash
# arc-space.sh <index> — focus Arc on a specific Space, by 1-based sidebar index.
#
# Replaces the old Chrome-profile bindings (Opt+B / Opt+W). Arc models the
# personal/work split as Spaces inside ONE browser rather than as separate
# profile directories, so there's no --profile-directory equivalent and nothing
# for chrome-profile.sh to resolve. Arc exposes Spaces through its AppleScript
# dictionary (the `space` class plus a `focus` command) — that's the only
# supported way to target one; Arc has no URL scheme or CLI flag for Spaces.
#
# Spaces are addressed by INDEX, not title, because titles are user-editable in
# the sidebar and a rename would silently break the keybinding. Index tracks
# sidebar order instead, which is what you actually reach for.
#
# Usage:
#   arc-space.sh 1   # Personal
#   arc-space.sh 3   # subconscious.dev (work)

set -euo pipefail

ARC_APP_PATH="/Applications/Arc.app"

usage() {
    echo "usage: $(basename "$0") <space-index>" >&2
    exit 2
}

[ $# -eq 1 ] || usage
SPACE_INDEX="$1"

case "$SPACE_INDEX" in
    ''|*[!0-9]*)
        echo "space index must be a positive integer, got: '$SPACE_INDEX'" >&2
        usage
        ;;
    0)
        echo "space index is 1-based; 0 is not a valid Space" >&2
        usage
        ;;
esac

if [ ! -d "$ARC_APP_PATH" ]; then
    echo "Arc not found at $ARC_APP_PATH — is it installed?" >&2
    exit 1
fi

# `focus` is a command on the space class, so it needs a window to resolve
# against. A cold launch (or all windows closed) leaves none and `front window`
# would fail with -1728, hence the explicit make-new-window path.
/usr/bin/osascript - "$SPACE_INDEX" <<'APPLESCRIPT'
on run argv
    set spaceIndex to (item 1 of argv) as integer
    tell application "Arc"
        activate
        if (count of windows) is 0 then
            make new window
            -- Give the fresh window time to populate its space list; focusing
            -- before it settles resolves against an empty collection.
            delay 0.4
        end if
        tell front window
            set spaceCount to count of spaces
            if spaceIndex > spaceCount then
                error "Arc has " & spaceCount & " Space(s); index " & spaceIndex & " requested"
            end if
            tell space spaceIndex to focus
        end tell
    end tell
end run
APPLESCRIPT
