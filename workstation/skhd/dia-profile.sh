#!/usr/bin/env bash
# dia-profile.sh <profile-name> — bring Dia forward on one profile.
#
# Opt+B / Opt+W call this. Arc used to own these keys, but Arc is being
# sunset. Dia keeps personal and work as profiles inside one browser, and its
# AppleScript dictionary (Dia.sdef) gives each window a `profiles` element
# with a `focus` command. That is the only supported way to pick a profile:
# Dia has no CLI flag or URL scheme for it.
#
# Profiles are matched by NAME, case-insensitive. Dia's profile index order is
# not documented, so an index could silently point at the wrong account.
#
# Usage:
#   dia-profile.sh Personal
#   dia-profile.sh Work

set -euo pipefail

DIA_APP_PATH="/Applications/Dia.app"

if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "usage: $(basename "$0") <profile-name>" >&2
    exit 2
fi

if [ ! -d "$DIA_APP_PATH" ]; then
    echo "Dia not found at $DIA_APP_PATH. Install it: brew install --cask thebrowsercompany-dia" >&2
    exit 1
fi

# `focus` resolves against a window, so a cold launch with no windows needs
# one first. Without it, `front window` fails with -1728.
/usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
    set wanted to item 1 of argv
    tell application "Dia"
        activate
        if (count of windows) is 0 then
            make new window
            delay 0.4
        end if
        tell front window
            set names to name of every profile
            repeat with p in profiles
                ignoring case
                    if (name of p) is wanted then
                        focus p
                        return
                    end if
                end ignoring
            end repeat
        end tell
    end tell
    set AppleScript's text item delimiters to ", "
    error "Dia has no profile named '" & wanted & "'. Profiles: " & (names as text)
end run
APPLESCRIPT
