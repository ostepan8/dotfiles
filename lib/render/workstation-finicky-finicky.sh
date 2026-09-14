#!/usr/bin/env bash
# Render ~/.finicky.js for this machine.
#
# Substitutes the Chrome profile DISPLAY NAME for the personal account into the
# template. Two indirections, both forced on us:
#
#   1. The account, not the directory, is what is stable across the fleet.
#      Chrome names profile dirs in creation order, so ohstep23@gmail.com is
#      "Default" on the Studio and "Profile 1" on the MacBook. That lesson is
#      already encoded in workstation/skhd/chrome-profile.sh, so resolve with
#      it rather than growing a second copy that can drift.
#
#   2. Finicky's `profile` field wants the display name, not the directory --
#      it does its own info_cache lookup and logs "Found profile by name".
#      So chrome-profile.sh's directory has to be mapped back to a name.
#
# Keep the email in sync with skhd's Opt+B binding in workstation/skhd/skhdrc.
set -uo pipefail

EMAIL="ohstep23@gmail.com"
STATE="$HOME/Library/Application Support/Google/Chrome/Local State"

# No Chrome on this machine: leave ~/.finicky.js alone rather than writing a
# config that names a browser which is not installed.
[ -f "$STATE" ] || exit 0

DIR="$("$DOTFILES/workstation/skhd/chrome-profile.sh" "$EMAIL" Default)"
[ -n "$DIR" ] || exit 0

rendered="$(python3 - "$RENDER_SRC" "$STATE" "$DIR" <<'PY'
import json, sys
src, state, directory = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    cache = json.load(open(state))["profile"]["info_cache"]
except Exception:
    raise SystemExit(1)
name = cache.get(directory, {}).get("name")
if not name:
    raise SystemExit(1)
template = open(src).read()
# Replace the quoted placeholder wholesale so a name containing a quote or
# backslash still produces valid JS.
sys.stdout.write(template.replace('"__PERSONAL_PROFILE__"', json.dumps(name)))
PY
)" || exit 0
[ -n "$rendered" ] || exit 0

# Idempotent: only write when the result actually differs. Finicky watches the
# file, so a write is a live reload -- an unconditional one would re-parse the
# config on every 30-minute apply tick for nothing.
if [ -f "$RENDER_DEST" ] && [ "$rendered" = "$(cat "$RENDER_DEST")" ]; then
  exit 0
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "  render $RENDER_DEST"
  exit 0
fi

mkdir -p "$(dirname "$RENDER_DEST")"
printf '%s' "$rendered" > "$RENDER_DEST"
echo "  render $RENDER_DEST ($EMAIL -> profile dir $DIR)"
