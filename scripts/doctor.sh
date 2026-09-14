#!/usr/bin/env bash
# doctor.sh — assert the RUNNING system matches what the config claims.
#
# `make verify` proves the apply engine would do the right thing against a
# throwaway HOME. Nothing proved that THIS machine is currently in the state the
# repo describes, and that gap is where every bug in this repo's history has
# lived. A sampling, all found by hand, none of which raised an error anywhere:
#
#   - sketchybar ran with zero items for three weeks. apply only reloads a
#     service when one of its source files changes, and none did.
#   - prefix+C-l read as next-window in .tmux.conf and did clear-screen, because
#     a plugin binds the same key and `run tpm` is the last line of the file.
#   - M-1..9 and M-hjkl in .tmux.conf never worked at all: aerospace claims them
#     system-wide, above tmux.
#   - a launchd job was renamed .migrated-to-nephos with nothing on the nephos
#     side to replace it. It ran nowhere for six weeks.
#   - PATH reached 37 entries for 28 directories.
#
# The shape is always the same: the file says one thing, the running system does
# another, and nothing reports the disagreement. Every check below asserts
# against live state -- list-keys, launchctl, --query -- never against a file.
#
# Read-only. Exits non-zero if any check fails, 0 if everything passes or is
# legitimately skipped.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES" || exit 1

PASS=0; FAIL=0; SKIP=0; WARN=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[90mskip\033[0m  %s (%s)\n' "$1" "$2"; }
# Worth surfacing, not worth failing over. Housekeeping should never be the
# reason `make test` goes red.
warn() { WARN=$((WARN+1)); printf '  \033[33mwarn\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

printf '\n\033[1mdoctor\033[0m — checking the running system, not the config\n\n'

# ---------------------------------------------------------------- sketchybar
# The failure mode is a styled, entirely empty bar: the config aborted partway
# and nothing crashed, so there is no error to find. Item count is the only
# honest signal.
if ! command -v sketchybar >/dev/null 2>&1; then
    skip "sketchybar has items" "not installed"
elif ! pgrep -x sketchybar >/dev/null 2>&1; then
    skip "sketchybar has items" "not running"
else
    n="$(sketchybar --query bar 2>/dev/null \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("items",[])))' 2>/dev/null)"
    if [ "${n:-0}" -gt 0 ]; then
        ok "sketchybar has items ($n)"
    else
        bad "sketchybar has items" "bar is running with 0 items — rc aborted; run: sketchybar --reload"
    fi
fi

# ---------------------------------------------------------------- tmux drift
# Every key .tmux.conf binds should be bound in the live server. A missing one
# means something overwrote it after the fact -- almost always a plugin loading
# below it, since `run tpm` is the last line.
if ! command -v tmux >/dev/null 2>&1 || ! tmux info >/dev/null 2>&1; then
    skip "tmux bindings match the config" "no tmux server"
else
    # Live bindings, keyed exactly. Comparing with a regex broke on keys that
    # are themselves regex metacharacters -- tmux binds both `|` and `-`.
    tmux list-keys 2>/dev/null | awk '
        { for (i = 1; i <= NF; i++) if ($i == "-T") { print $(i+1) "\t" $(i+2); break } }
    ' | sort -u > /tmp/.doctor_bound

    missing=""
    while IFS=$'\t' read -r table key; do
        [ -z "$key" ] && continue
        grep -qxF "$table	$key" /tmp/.doctor_bound || missing="$missing $table:$key"
    done < <(awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*bind(-key)?[[:space:]]/ {
            table = "prefix"; key = ""
            for (i = 2; i <= NF; i++) {
                # A lone "-" is a KEY (bind - split-window), not a flag. Only
                # multi-character dash arguments are flags.
                if ($i == "-n")                      { table = "root"; continue }
                if ($i == "-T")                      { table = $(++i); continue }
                if ($i ~ /^-/ && length($i) > 1)     { continue }
                key = $i; break
            }
            gsub(/^'"'"'|'"'"'$/, "", key)
            if (key != "" && table != "copy-mode-vi" && key !~ /[$"{]/) print table "\t" key
        }' base/tmux/.tmux.conf | sort -u)
    rm -f /tmp/.doctor_bound

    if [ -z "$missing" ]; then
        ok "tmux bindings match the config"
    else
        bad "tmux bindings match the config" "declared but NOT bound:$missing"
    fi
fi

# ------------------------------------------------------- tmux option growth
# terminal-features/-overrides are append options. Without a -gu reset ahead of
# the appends, every `prefix + r` stacks another identical entry.
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
    dup=""
    for opt in terminal-features terminal-overrides; do
        total="$(tmux show -g "$opt" 2>/dev/null | wc -l | tr -d ' ')"
        uniq="$(tmux show -g "$opt" 2>/dev/null | sed 's/^[^ ]* //' | sort -u | wc -l | tr -d ' ')"
        [ "$total" -gt "$uniq" ] && dup="$dup $opt($total/$uniq)"
    done
    if [ -z "$dup" ]; then ok "tmux options have no duplicates"
    else bad "tmux options have no duplicates" "appended repeatedly:$dup — needs `set -gu` before `set -ga`"; fi
fi

# ------------------------------------------------------------ launchd jobs
# A .plist.migrated-to-nephos marker means the local job was retired. If the
# original is still loaded, the work runs twice; if neither runs, it runs
# nowhere. Both have happened.
if ! command -v launchctl >/dev/null 2>&1; then
    skip "no retired launchd job still loaded" "not macOS"
else
    still=""
    for marker in "$HOME"/Library/LaunchAgents/*.plist.migrated-to-*; do
        [ -e "$marker" ] || continue
        base="$(basename "$marker")"; label="${base%%.plist.migrated-to-*}"
        launchctl list 2>/dev/null | grep -q "	$label$" && still="$still $label"
    done
    if [ -z "$still" ]; then ok "no retired launchd job still loaded"
    else bad "no retired launchd job still loaded" "marked migrated but still scheduled:$still"; fi
fi

# ------------------------------------------------------------------- PATH
# Unconditional `export PATH=...:$PATH` lines re-run on every login shell, and
# tmux gives every new pane one. typeset -U keeps the list flat.
if ! command -v zsh >/dev/null 2>&1; then
    skip "PATH has no duplicates" "no zsh"
else
    p="$(zsh -lic 'echo $PATH' 2>/dev/null)"
    t="$(printf '%s' "$p" | tr ':' '\n' | grep -c .)"
    u="$(printf '%s' "$p" | tr ':' '\n' | grep -c . | head -1; printf '%s' "$p" | tr ':' '\n' | sort -u | grep -c .)"
    u="$(printf '%s' "$p" | tr ':' '\n' | sort -u | grep -c .)"
    if [ "$t" -eq "$u" ]; then ok "PATH has no duplicates ($t entries)"
    else bad "PATH has no duplicates" "$t entries for $u directories — add `typeset -U path PATH` before the first append"; fi
fi

# ------------------------------------------------------- Alt-key collisions
# Three layers claim Alt on a workstation and only the bottom one is tmux. skhd
# and aerospace register system-wide hotkeys, so a key either of them holds never
# reaches the terminal -- the tmux binding is simply dead, silently.
if [ ! -f "$HOME/.skhdrc" ] && [ ! -f "$HOME/.config/aerospace/aerospace.toml" ]; then
    skip "no Alt key claimed by two layers" "no skhd/aerospace config"
else
    tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
    grep -ohE "^[^#]*\balt *- *[a-z0-9]+" "$HOME/.skhdrc" 2>/dev/null \
        | grep -vE "shift|cmd|ctrl" | grep -oE "alt *- *[a-z0-9]+$" | tr -d ' ' \
        | sed 's/alt-//' | sort -u > "$tmpdir/skhd"
    grep -ohE "^alt-[a-z0-9]+ *=" "$HOME/.config/aerospace/aerospace.toml" 2>/dev/null \
        | sed 's/ *=//; s/alt-//' | sort -u > "$tmpdir/aero"
    if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
        tmux list-keys -T root 2>/dev/null | grep -oE '\-T root +M-[a-zA-Z0-9]+' \
            | awk '{print $NF}' | sed 's/M-//' | sort -u > "$tmpdir/tmux"
    else : > "$tmpdir/tmux"; fi

    clash=""
    for k in $(cat "$tmpdir/tmux"); do
        grep -qx "$k" "$tmpdir/skhd" 2>/dev/null && clash="$clash alt-$k(skhd)"
        grep -qx "$k" "$tmpdir/aero" 2>/dev/null && clash="$clash alt-$k(aerospace)"
    done
    if [ -z "$clash" ]; then ok "no Alt key claimed by two layers"
    else bad "no Alt key claimed by two layers" "tmux binds these but a system hotkey eats them first:$clash"; fi
fi

# ------------------------------------------------------------ tmux hoarding
# Empty sessions are not harmful in themselves, but they crowd the Opt+P picker
# -- every project touched once competes with the handful in actual use.
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
    idle=0
    while IFS= read -r s; do
        [ -z "$s" ] && continue
        busy="$(tmux list-panes -s -t "$s" -F '#{pane_current_command}' 2>/dev/null \
            | grep -vcE '^(zsh|bash|sh|fish)$')"
        [ "${busy:-1}" -eq 0 ] && idle=$((idle+1))
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    total="$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$idle" -lt 20 ]; then
        ok "tmux sessions are not piling up ($idle of $total empty)"
    else
        warn "tmux sessions are piling up ($idle of $total are empty shells)" "run: tmux-reap        (dry run; --kill to act)"
    fi
fi

# --------------------------------------------------------- nephos schedules
# A cron schedule that fails every night is the quietest kind of broken: it keeps
# firing, keeps failing, and the only record is a row in `nephos jobs` nobody
# reads. Correlate each schedule with its most recent run and assert that run
# succeeded.
if ! command -v nephos >/dev/null 2>&1; then
    skip "no nephos schedule failed its last run" "nephos not installed"
elif ! nephos jobs --json >/tmp/.doctor_jobs 2>/dev/null; then
    skip "no nephos schedule failed its last run" "control plane unreachable"
else
    broken="$(nephos schedules 2>/dev/null | awk 'NR>1 && NF {print $1}' | while read -r name; do
        [ -z "$name" ] && continue
        python3 - "$name" <<'PYEOF'
import json, sys
name = sys.argv[1]
try:
    rows = json.load(open("/tmp/.doctor_jobs")) or []
except Exception:
    raise SystemExit
runs = [r for r in rows if r.get("name") == name and r.get("state") in ("succeeded", "failed")]
runs.sort(key=lambda r: r.get("finishedAt") or r.get("submittedAt") or "", reverse=True)
if runs and runs[0].get("state") == "failed":
    print(name, end=" ")
PYEOF
    done)"
    rm -f /tmp/.doctor_jobs
    if [ -z "$broken" ]; then ok "no nephos schedule failed its last run"
    else bad "no nephos schedule failed its last run" "last run FAILED: $broken — it will fire again on schedule"; fi
fi

# ------------------------------------------------------------- cheatsheet
# The keybinding sections are generated from docs/keys.tsv. If the committed HTML
# no longer matches what keys.tsv renders, the doc is lying about the keys.
if bash scripts/gen-cheatsheet.sh --check >/dev/null 2>&1; then
    ok "cheatsheet matches docs/keys.tsv"
else
    bad "cheatsheet matches docs/keys.tsv" "docs/cheatsheet.html is stale — run: make cheatsheet"
fi

printf '\n  %d passed, %d failed, %d warned, %d skipped\n\n' "$PASS" "$FAIL" "$WARN" "$SKIP"
[ "$FAIL" -eq 0 ]
