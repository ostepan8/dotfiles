#!/usr/bin/env bash
# verify-apply.sh — Phase 2 gate: prove the engine before any file moves.
#
# Runs apply.sh against a throwaway HOME so nothing on the real machine is
# touched. This is what lets the restructure be validated WITHOUT going first on
# the Mac Studio, which is the owner's working machine.
#
# Asserts:
#   1. every managed destination for the machine's layers exists
#   2. its content matches the repo source
#   3. a second run reports zero changes (idempotence)
#   4. an unknown host applies base only — no GUI config on a headless box
#   5. per-machine files (displays.env) survive a re-apply unmodified
set -uo pipefail

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DOTFILES" || exit 1

RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; DIM=""; OFF=""; }

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  %sok%s   %s\n' "$GREEN" "$OFF" "$1"; }
bad()  { fail=$((fail+1)); printf '  %sFAIL%s %s\n' "$RED" "$OFF" "$1"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

run_apply() {  # run_apply <home> [args...]
  local home="$1"; shift
  env HOME="$home" NO_RELOAD=1 bash "$DOTFILES/apply.sh" "$@" 2>&1
}

# ---------------------------------------------------------------------------
echo "${DIM}[1/5] fresh machine, host type 'studio'${OFF}"
H="$SANDBOX/studio"; mkdir -p "$H"
echo studio > "$H/.dotfiles-host"
out="$(run_apply "$H")"
echo "$out" | grep -q '^\[apply\]' || bad "apply produced no output"

# Spot-check one destination per mode.
# Resolve the expected target from the manifest rather than hardcoding a path —
# a hardcoded one silently goes stale the moment a file moves, which is exactly
# what this suite exists to catch.
zshrc_src="$(awk '!/^[[:space:]]*#/ && $4 == "~/.zshrc" { print $3; exit }' "$DOTFILES/manifest.conf")"
[ -L "$H/.zshrc" ] && [ "$(readlink "$H/.zshrc")" = "$DOTFILES/$zshrc_src" ] \
  && ok "link: .zshrc -> $zshrc_src" || bad "link: .zshrc (expected -> $zshrc_src)"

[ -f "$H/.config/aerospace/aerospace.toml" ] && [ ! -L "$H/.config/aerospace/aerospace.toml" ] \
  && ok "copy: aerospace.toml is a real file, not a symlink" \
  || bad "copy: aerospace.toml must not be a symlink (runtime rewrites it)"

[ -f "$H/.config/aerospace/displays.env" ] && [ ! -L "$H/.config/aerospace/displays.env" ] \
  && ok "seed: displays.env is a real file" || bad "seed: displays.env"

[ -d "$H/.claude-personal/skills" ] && [ -f "$H/.claude-personal/skills/nephos/SKILL.md" ] \
  && ok "tree: claude skills reached the profile claude actually reads" \
  || bad "tree: claude skills missing from ~/.claude-personal"

[ -f "$H/.claude-personal/settings.json" ] \
  && ok "claude settings in ~/.claude-personal (not ~/.claude)" \
  || bad "claude settings missing"

[ -e "$H/.claude" ] && bad "wrote to ~/.claude — the directory nothing reads" \
  || ok "nothing written to the stale ~/.claude path"

# Content fidelity across every non-glob link row for the active layers.
mismatch=0; checked=0
while read -r layer mode source dest reload; do
  case "$layer" in ''|\#*) continue ;; esac
  case "$layer" in base|workstation|services) ;; *) continue ;; esac
  [ "$mode" = "link" ] || continue
  [[ "$source" == *"*"* ]] && continue
  d="${dest/#\~/$H}"
  [ -e "$d" ] || { echo "     missing: $d"; mismatch=$((mismatch+1)); continue; }
  cmp -s "$DOTFILES/$source" "$d" || { echo "     differs: $d"; mismatch=$((mismatch+1)); }
  checked=$((checked+1))
done < "$DOTFILES/manifest.conf"
[ "$mismatch" -eq 0 ] && ok "content matches repo for all $checked linked files" \
  || bad "$mismatch destination(s) missing or differing"

# ---------------------------------------------------------------------------
echo "${DIM}[2/5] idempotence — second run must change nothing${OFF}"
out2="$(run_apply "$H")"
echo "$out2" | grep -q 'already up to date' \
  && ok "second run: no changes" \
  || { bad "second run still reports changes"; echo "$out2" | sed 's/^/     /' | head -20; }

# Match the reload log line specifically — a bare 'reload' also matches the
# string "reloads.sh" in any diagnostic, which made this pass/fail on noise.
echo "$out2" | grep -qE '^[[:space:]]*(would )?reload ' \
  && bad "idle run fired a reload (this is the top-bar-flash bug)" \
  || ok "idle run fired no reloads"

# ---------------------------------------------------------------------------
echo "${DIM}[3/5] per-machine files survive re-apply${OFF}"
printf 'MACHINE_SPECIFIC=1\n' > "$H/.config/aerospace/displays.env"
printf '# pinned by this machine\n' >> "$H/.config/aerospace/aerospace.toml"
run_apply "$H" >/dev/null
grep -q 'MACHINE_SPECIFIC=1' "$H/.config/aerospace/displays.env" \
  && ok "seed: local displays.env not clobbered" || bad "seed: displays.env was overwritten"
grep -q 'pinned by this machine' "$H/.config/aerospace/aerospace.toml" \
  && ok "copy: live monitor pins survive an idle apply" \
  || bad "copy: idle apply reverted the machine's aerospace.toml"

# ---------------------------------------------------------------------------
echo "${DIM}[4/5] headless machine — unknown host applies base only${OFF}"
S="$SANDBOX/server"; mkdir -p "$S"
run_apply "$S" >/dev/null
[ -L "$S/.zshrc" ] && ok "server: base config applied" || bad "server: no .zshrc"
[ -f "$S/.claude-personal/skills/nephos/SKILL.md" ] \
  && ok "server: claude skills present (nephos works everywhere now)" \
  || bad "server: claude skills missing — the bug this restructure fixes"
[ -e "$S/.skhdrc" ] && bad "server: GUI hotkey config leaked onto a headless box" \
  || ok "server: no skhd config"
[ -e "$S/.config/sketchybar" ] && bad "server: sketchybar leaked onto a headless box" \
  || ok "server: no sketchybar config"
[ -e "$S/Library/LaunchAgents" ] && bad "server: launchd agents leaked" \
  || ok "server: no launchd agents"

# ---------------------------------------------------------------------------
echo "${DIM}[5/5] explicit host with no layers entry falls back safely${OFF}"
U="$SANDBOX/unknown"; mkdir -p "$U"; echo "brand-new-box" > "$U/.dotfiles-host"
out5="$(run_apply "$U")"
echo "$out5" | grep -q "not in hosts/layers.conf" \
  && ok "unknown host warns" || bad "unknown host did not warn"
[ -L "$U/.zshrc" ] && ok "unknown host still gets a working shell" \
  || bad "unknown host got nothing"

# ---------------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
  echo "${GREEN}$pass checks passed${OFF} — engine verified without touching this machine."
  exit 0
fi
echo "${RED}$fail of $((pass+fail)) checks failed${OFF}"
exit 1
