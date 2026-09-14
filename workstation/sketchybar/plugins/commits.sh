#!/usr/bin/env bash
# Commits authored today, summed across every project root on this machine.
#
# rev-list --count is used rather than `log | wc -l` so git does the counting and
# nothing crosses a pipe. --since=midnight is git's own local-midnight boundary,
# so this resets with the calendar day rather than on a rolling 24h window.
#
# Scanning is bounded to depth 2, which covers <root>/<project>/.git without
# descending into node_modules and friends. Measured at ~0.19s across 20 repos,
# comfortably inside the 5-minute update_freq this runs on.
ROOTS=(
    "$HOME/Desktop/Projects"
    "$HOME/Desktop/Web-Experiments"
    "$HOME/projects"
    "$HOME/dotfiles"
)
AUTHOR="ohstep23@gmail.com"

# Every value here is scrubbed to digits before it reaches $(( )). Under the
# launch agent's shell this loop was yielding an empty $total, which made
# `label=` expand to nothing -- and sketchybar silently IGNORES an empty
# assignment rather than clearing the field, so the item kept whatever it had
# and the failure looked like "the script never ran". The unset colour came from
# the same place: `[ "$total" -eq 0 ]` on an empty string is an error, not false,
# so the whole if/elif fell through without assigning COLOR.
total=0
while IFS= read -r gitdir; do
    repo="${gitdir%/.git}"
    # A repo with no commits today, or no commits at all, exits non-zero here.
    n="$(git -C "$repo" rev-list --count --since=midnight --author="$AUTHOR" HEAD 2>/dev/null)"
    n="${n//[^0-9]/}"
    [ -n "$n" ] || n=0
    total=$(( total + n ))
done < <(find "${ROOTS[@]}" -maxdepth 2 -name .git -type d 2>/dev/null)

# Belt and braces: never let an empty or non-numeric total reach the --set below.
total="${total//[^0-9]/}"
[ -n "$total" ] || total=0

# Gruvbox: grey until the day has started, green once it is moving, orange on a
# genuinely heavy day.
COLOR=0xff928374
if   [ "$total" -eq 0 ];  then COLOR=0xff928374
elif [ "$total" -lt 10 ]; then COLOR=0xff98971a
else                           COLOR=0xffd65d0e
fi

sketchybar --set "$NAME" \
    icon="GIT" icon.color="$COLOR" icon.font="SF Pro:Bold:11.0" \
    label="$total"
