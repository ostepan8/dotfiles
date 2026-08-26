#!/usr/bin/env bash
# check-exec-bits.sh — pre-push gate: every script something else EXECUTES must
# be committed mode 100755.
#
# Why this exists: `workstation/aerospace/display-watcher.sh` was committed 644.
# Its LaunchAgent's ProgramArguments does `exec "$HOME/.config/aerospace/
# display-watcher.sh"`, which failed with exit 126 — "Permission denied" — and
# launchd's KeepAlive respawned it every few seconds for ten days. Nothing
# surfaced: aerospace ran fine, the bar drew fine, and the only symptom was that
# workspaces 9/10 silently stopped pinning to the external monitor, because the
# dead watcher was the thing that reconciled the pin block after a cold boot.
#
# A missing exec bit is uniquely bad at failing loudly. The file reads fine, the
# diff looks fine, and the caller dies with a numeric status into a log nobody
# tails. So it gets caught here instead.
#
# Design note: the checked set is DERIVED from manifest.conf's `exec` rows, not
# hardcoded. Declaring a row `exec` is the single act that both makes apply.sh
# assert the bit on the machine and enrolls the file in this gate — the two can
# never drift. Files nothing executes (lib/*.sh are sourced, mlx-chat-clean.py is
# run as `python3 <path>`) are correctly absent, because they hold no exec row.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; DIM=""; OFF=""; }

MANIFEST=manifest.conf
[ -r "$MANIFEST" ] || { echo "${RED}FAIL${OFF} $MANIFEST unreadable"; exit 1; }

# Sources of every `exec` row, globs expanded, deduplicated (newproj.sh holds two
# rows: ~/.local/bin/newproj and ~/.local/bin/np).
sources() {
  local layer mode source rest f
  while read -r layer mode source rest; do
    case "$layer" in ''|\#*) continue ;; esac
    [ "$mode" = exec ] || continue
    for f in $source; do
      [ -f "$f" ] && printf '%s\n' "$f"
    done
  done < "$MANIFEST" | sort -u
}

# git's recorded mode, not the working tree's. The working tree is what apply.sh
# chmods on every run, so a local chmod makes the bug LOOK fixed while the commit
# still carries 644 and every other machine still breaks. The index is the only
# thing that travels.
mode_in_git() { git ls-files -s -- "$1" | awk '{print $1; exit}'; }

checked=0; fail=0; declare -a broken=()

while read -r f; do
  [ -n "$f" ] || continue
  checked=$((checked + 1))
  m="$(mode_in_git "$f")"
  if [ -z "$m" ]; then
    printf '  %sFAIL%s %s — declared exec in %s but not tracked by git\n' \
      "$RED" "$OFF" "$f" "$MANIFEST"
    fail=$((fail + 1))
  elif [ "$m" != 100755 ]; then
    printf '  %sFAIL%s %s — committed %s, needs 100755\n' "$RED" "$OFF" "$f" "$m"
    broken+=("$f")
    fail=$((fail + 1))
  fi
done < <(sources)

if [ "$checked" -eq 0 ]; then
  # A gate that checks nothing reports success forever. Treat it as a failure:
  # it means the manifest parse broke, not that the repo is clean.
  echo "${RED}FAIL${OFF} no exec rows found in $MANIFEST — parser is broken"
  exit 1
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "${RED}Push blocked.${OFF} $fail of $checked executable(s) would deploy non-executable."
  if [ "${#broken[@]}" -gt 0 ]; then
    echo "Fix the recorded mode (a plain chmod touches only your working tree):"
    echo "  ${DIM}git update-index --chmod=+x ${broken[*]}${OFF}"
  fi
  exit 1
fi

echo "${GREEN}exec bits ok${OFF} — $checked manifest executable(s) committed 100755."
