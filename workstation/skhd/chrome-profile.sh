#!/usr/bin/env bash
# chrome-profile.sh <email> [fallback] — resolve a Chrome profile DIRECTORY by
# the account signed into it.
#
# Chrome's profile directory names are assigned in creation order, so they mean
# different things on different machines. Measured on this fleet:
#
#            Default                  Profile 1
#   Studio   ohstep23@gmail.com       (empty "Person 1")
#   MacBook  (empty "Person 1")       ohstep23@gmail.com
#
# Exactly inverted. A hardcoded --profile-directory in the shared skhdrc is
# therefore correct on at most one machine, which is why Opt+B opened the wrong
# Chrome on the MacBook until it was patched locally — and why that patch could
# not simply be merged, since it would have broken the Studio.
#
# The email is stable across machines; the directory is not. Resolve by email.
#
# Falls back to the second argument when the account is not signed in on this
# machine (some profiles report no user_name), and finally to "Default", so
# skhd always gets something rather than an empty --profile-directory=.
set -uo pipefail

EMAIL="${1:-}"
FALLBACK="${2:-Default}"
[ -z "$EMAIL" ] && { printf '%s' "$FALLBACK"; exit 0; }

STATE="$HOME/Library/Application Support/Google/Chrome/Local State"
[ -f "$STATE" ] || { printf '%s' "$FALLBACK"; exit 0; }

python3 - "$STATE" "$EMAIL" "$FALLBACK" <<'PY' 2>/dev/null || printf '%s' "$FALLBACK"
import json, sys
state, email, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    cache = json.load(open(state))["profile"]["info_cache"]
except Exception:
    print(fallback, end=""); raise SystemExit(0)
for directory, info in cache.items():
    if info.get("user_name", "").lower() == email.lower():
        print(directory, end=""); raise SystemExit(0)
print(fallback, end="")
PY
