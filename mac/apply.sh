#!/usr/bin/env bash
# apply.sh — copy dotfiles from the repo into their live locations and reload
# the services that consume them. This is the lightweight half of setup.sh
# (steps [4]/[5]) with NO brew/defaults/network work, so it's safe to run on
# every dotfiles sync. Idempotent.
#
# Machine-specific files are never overwritten here:
#   - ~/.config/aerospace/displays.env   (persistent display IDs per machine)
#   - ~/.claude/settings.local.json      (local-only Claude settings)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/with-timeout.sh
. "$SCRIPT_DIR/lib/with-timeout.sh"

# Budget for a single service hot-reload. These are local IPC round-trips that
# finish in well under a second when healthy, so 10s is generous.
RELOAD_TIMEOUT=10

# set-main-display.sh is not a simple IPC ping — it rewrites aerospace.toml,
# reloads aerospace, restarts sketchybar and polls for the bar to come back —
# so it gets its own, larger budget.
DISPLAY_RECONCILE_TIMEOUT=60

# Per-source change detection. The dotfiles-sync agent runs this every 30 min;
# copying files is cheap, but *reloading services* (aerospace retile, sketchybar
# daemon restart, skhd reload, relaunching LaunchAgents) is disruptive — it was
# flashing/closing the top bar and re-firing the display-watcher on every tick,
# even when nothing had changed. `changed <tag> <file...>` returns true only
# when a source's content hash has moved since the last apply, so each reload
# fires exactly when its inputs actually changed. State lives per-machine (not
# tracked), so every machine detects+applies its own pulls independently.
APPLY_STATE="$HOME/.config/.dotfiles-apply"
mkdir -p "$APPLY_STATE"
changed() {
  local tag="$1"; shift
  local sha store prev
  sha="$(cat "$@" 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  store="$APPLY_STATE/$tag.sha"
  prev="$(cat "$store" 2>/dev/null || true)"
  [ "$sha" = "$prev" ] && return 1
  printf '%s\n' "$sha" > "$store"
  return 0
}

echo "[apply] linking configs from $REPO_DIR"
mkdir -p ~/.config/nvim ~/.config/ghostty ~/.config/aerospace ~/.config/sketchybar/plugins

cp -f "$REPO_DIR/nvim/init.lua"            ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml"   ~/.config/starship.toml
cp -f "$REPO_DIR/ghostty/config"           ~/.config/ghostty/config
cp -f "$REPO_DIR/skhd/skhdrc"              ~/.skhdrc
# aerospace scripts always refreshed — copying them touches no running service.
cp -f "$REPO_DIR/aerospace/"*.sh           ~/.config/aerospace/ 2>/dev/null || true
chmod +x ~/.config/aerospace/*.sh 2>/dev/null || true

# aerospace.toml is BOTH a tracked dotfile AND a file rewritten at runtime by
# set-main-display.sh (it stamps this machine's monitor pins + gaps into it).
# So we must NOT blindly copy the repo's generic copy over the live one every
# tick — that reverts the machine-specific pins and forces an aerospace reload.
# Only re-stamp when the tracked toml actually changed upstream, then reconcile
# it for THIS machine via set-main-display.sh (which reloads once, and is a
# no-op for side effects when nothing effectively changed).
if changed aerospace-toml "$REPO_DIR/aerospace/aerospace.toml"; then
  echo "[apply] aerospace.toml changed — reconciling for this machine"
  cp -f "$REPO_DIR/aerospace/aerospace.toml" ~/.config/aerospace/aerospace.toml
  rc=0
  with_timeout "$DISPLAY_RECONCILE_TIMEOUT" \
    ~/.config/aerospace/set-main-display.sh auto >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "  WARN: set-main-display.sh timed out after ${DISPLAY_RECONCILE_TIMEOUT}s — skipped (is aerospace wedged?)"
  fi
fi

# displays.env holds machine-specific persistent display IDs — never clobber.
[ -f ~/.config/aerospace/displays.env ] || cp -f "$REPO_DIR/aerospace/displays.env" ~/.config/aerospace/displays.env

# Phantom-window watchdog helper (Swift). Recompile if the source changed.
if [ -f "$REPO_DIR/aerospace/list-real-windows.swift" ]; then
  cp -f "$REPO_DIR/aerospace/list-real-windows.swift" ~/.config/aerospace/list-real-windows.swift
  if command -v swiftc >/dev/null 2>&1; then
    swiftc -O ~/.config/aerospace/list-real-windows.swift -o ~/.config/aerospace/list-real-windows 2>/dev/null \
      && echo "  compiled aerospace/list-real-windows"
  fi
fi
# Remove any stale Swift display-watcher binary from earlier iterations.
rm -f ~/.config/aerospace/display-watcher ~/.config/aerospace/display-watcher.swift

cp -f "$REPO_DIR/sketchybar/sketchybarrc"     ~/.config/sketchybar/sketchybarrc
cp -f "$REPO_DIR/sketchybar/plugins/"*.sh     ~/.config/sketchybar/plugins/
chmod +x ~/.config/sketchybar/sketchybarrc ~/.config/sketchybar/plugins/*.sh
[ -f "$REPO_DIR/tmux/.tmux.conf" ] && cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf

# Reinstall + reload any LaunchAgents (so changes to the agents themselves —
# including this sync agent — propagate from the other machine).
mkdir -p ~/Library/LaunchAgents
for plist in "$REPO_DIR/mac/LaunchAgents/"*.plist; do
  [ -f "$plist" ] || continue
  base="$(basename "$plist")"
  dest="$HOME/Library/LaunchAgents/$base"
  # Skip entirely when the installed plist already matches — reloading an
  # unchanged agent every tick was restarting the display-watcher (resetting
  # its state so it re-fired set-main-display.sh, restarting sketchybar and
  # retiling aerospace for no reason). Only touch an agent that actually moved.
  if cmp -s "$plist" "$dest"; then
    continue
  fi
  cp -f "$plist" "$dest"
  # The dotfiles-sync agent's own plist is never unloaded/reloaded here:
  # sync.sh always runs apply.sh as a child of the process launchd is
  # supervising *for that exact agent*, so `launchctl unload` on it would
  # SIGTERM the very process running this script mid-apply, truncating every
  # scheduled sync before it finishes (silently, since the kill lands here).
  # The copied plist still takes effect on the agent's next natural
  # login/relaunch.
  if [ "$base" = "com.ostepan.dotfiles-sync.plist" ]; then
    continue
  fi
  launchctl unload "$dest" 2>/dev/null || true
  launchctl load    "$dest" 2>/dev/null || true
done

echo "[apply] linking zsh + git + claude config"
cp -f "$REPO_DIR/zsh/zshrc"          ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt
cp -f "$REPO_DIR/git/gitconfig"       ~/.gitconfig
cp -f "$REPO_DIR/git/gitignore_global" ~/.gitignore_global
mkdir -p ~/.claude
cp -f "$REPO_DIR/claude/settings.json" ~/.claude/settings.json
cp -f "$REPO_DIR/claude/mcp.json"      ~/.claude/.mcp.json
mkdir -p ~/.claude/rules
cp -R "$REPO_DIR/claude/rules/." ~/.claude/rules/

# Reload services that can hot-reload — but ONLY when their source changed, so
# an idle sync tick leaves the running desktop untouched (no bar flash, no
# retile). aerospace's reload is handled by the aerospace.toml branch above
# (via set-main-display.sh), since its live toml is machine-mutated.
#
# Every reload is also timeout-guarded. Each shells into a long-running daemon,
# and a wedged daemon blocks apply.sh forever — which in turn blocks sync.sh,
# which stops launchd from ever firing the next sync. A cosmetic "reload the
# window manager" step must never be able to take the whole sync pipeline down
# with it, so a stuck reload is logged and skipped.
echo "[apply] reloading changed services"

reload_service() {
  local name="$1"; shift
  command -v "$name" >/dev/null 2>&1 || return 0
  local rc=0
  with_timeout "$RELOAD_TIMEOUT" "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "  WARN: $name reload timed out after ${RELOAD_TIMEOUT}s — skipped (is $name wedged?)"
  fi
  return 0
}

# `command -v` is tested BEFORE `changed` in each guard below, and never folded
# into reload_service alone: `changed` records the new hash as a side effect, so
# consuming it for a tool that isn't installed would mark the change applied and
# suppress the reload that should happen once that tool does get installed.
if command -v skhd >/dev/null 2>&1 && changed skhd "$REPO_DIR/skhd/skhdrc"; then
  reload_service skhd skhd --reload
fi
if command -v sketchybar >/dev/null 2>&1 \
   && changed sketchybar "$REPO_DIR/sketchybar/sketchybarrc" "$REPO_DIR"/sketchybar/plugins/*.sh; then
  reload_service sketchybar sketchybar --reload
fi
# tmux needs a liveness probe first (source-file against no server is an error,
# not a no-op) — and the probe itself gets a timeout for the same reason as the
# reloads. The probe also precedes `changed` for the side-effect reason above:
# with no server running there is nothing to reload, so the hash must not move.
if command -v tmux >/dev/null 2>&1 \
   && with_timeout "$RELOAD_TIMEOUT" tmux info >/dev/null 2>&1 \
   && changed tmux "$REPO_DIR/tmux/.tmux.conf"; then
  reload_service tmux tmux source-file "$HOME/.tmux.conf"
fi

echo "[apply] done"
