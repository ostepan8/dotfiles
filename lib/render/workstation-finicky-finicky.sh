#!/usr/bin/env bash
# Render ~/.finicky.js for this machine.
#
# Substitutes this machine's Chrome profiles for the personal and work accounts
# into the template. Two indirections, both forced on us:
#
#   1. The account, not the directory, is what is stable across the fleet.
#      Chrome names profile dirs in creation order, so ohstep23@gmail.com is
#      "Default" on the Studio and "Profile 1" on the MacBook. That lesson is
#      already encoded in workstation/skhd/chrome-profile.sh, so resolve with
#      it rather than growing a second copy that can drift.
#
#   2. Finicky's `profile` field wants the display NAME for a uniquely named
#      profile -- it does its own info_cache lookup and logs "Found profile by
#      name". But display names are not unique: three profiles here are all
#      named "subconscious.dev", and Finicky resolves names by iterating a Go
#      map, so a name would pick one of the three at random -- including ones
#      with nobody signed in. Its second pass matches the profile DIRECTORY
#      exactly, so the work profile is rendered as a directory instead.
#
#      Rule of thumb: render a name when the name is unique, a directory when
#      it is not. This script decides per account rather than assuming.
#
# Keep the emails in sync with skhd's Opt+B / Opt+W bindings in
# workstation/skhd/skhdrc.
set -uo pipefail

PERSONAL_EMAIL="ohstep23@gmail.com"
WORK_EMAIL="owen@subconscious.dev"
STATE="$HOME/Library/Application Support/Google/Chrome/Local State"

# No Chrome on this machine: leave ~/.finicky.js alone rather than writing a
# config that names a browser which is not installed.
[ -f "$STATE" ] || exit 0

PERSONAL_DIR="$("$DOTFILES/workstation/skhd/chrome-profile.sh" "$PERSONAL_EMAIL" Default)"
WORK_DIR="$("$DOTFILES/workstation/skhd/chrome-profile.sh" "$WORK_EMAIL" 'Profile 13')"
[ -n "$PERSONAL_DIR" ] && [ -n "$WORK_DIR" ] || exit 0

rendered="$(python3 - "$RENDER_SRC" "$STATE" "$PERSONAL_DIR" "$WORK_DIR" <<'PY'
import json, sys
src, state, personal_dir, work_dir = sys.argv[1:5]
try:
    cache = json.load(open(state))["profile"]["info_cache"]
except Exception:
    raise SystemExit(1)

names = [info.get("name") for info in cache.values()]

def selector(directory):
    """Display name when it identifies exactly one profile, else the directory.

    Finicky matches names first and directories only as a fallback, so a name
    that is shared by several profiles resolves nondeterministically. Falling
    back to the directory costs a "Please use the profile name instead" warning
    in Finicky's log and buys an unambiguous answer.
    """
    name = cache.get(directory, {}).get("name")
    if name and names.count(name) == 1:
        return name
    return directory

# Replace the quoted placeholders wholesale so a value containing a quote or
# backslash still produces valid JS.
template = open(src).read()
for placeholder, directory in (
    ("__PERSONAL_PROFILE__", personal_dir),
    ("__WORK_PROFILE__", work_dir),
):
    value = selector(directory)
    if not value:
        raise SystemExit(1)
    template = template.replace('"%s"' % placeholder, json.dumps(value))

# Quoted form only. The template header names both placeholders in prose to
# explain them, and an unquoted match here would read that prose as an
# unsubstituted value and refuse to render -- which it did, silently, once.
#
# Apostrophes are also avoided in this block on purpose: it sits inside a
# heredoc inside a command substitution, where bash still pairs quotes.
if '"__PERSONAL_PROFILE__"' in template or '"__WORK_PROFILE__"' in template:
    raise SystemExit(1)

sys.stdout.write(template)
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
echo "  render $RENDER_DEST ($PERSONAL_EMAIL -> $PERSONAL_DIR, $WORK_EMAIL -> $WORK_DIR)"
