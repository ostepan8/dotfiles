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

echo "[apply] linking configs from $REPO_DIR"
mkdir -p ~/.config/nvim ~/.config/ghostty ~/.config/aerospace ~/.config/sketchybar/plugins

cp -f "$REPO_DIR/nvim/init.lua"            ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml"   ~/.config/starship.toml
cp -f "$REPO_DIR/ghostty/config"           ~/.config/ghostty/config
cp -f "$REPO_DIR/skhd/skhdrc"              ~/.skhdrc
cp -f "$REPO_DIR/aerospace/aerospace.toml" ~/.config/aerospace/aerospace.toml
cp -f "$REPO_DIR/aerospace/"*.sh           ~/.config/aerospace/ 2>/dev/null || true
chmod +x ~/.config/aerospace/*.sh 2>/dev/null || true

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
  dest="$HOME/Library/LaunchAgents/$(basename "$plist")"
  cp -f "$plist" "$dest"
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

# Reload services that can hot-reload, so pulled changes take effect now.
echo "[apply] reloading services"
command -v skhd       >/dev/null 2>&1 && skhd --reload 2>/dev/null || true
command -v sketchybar >/dev/null 2>&1 && sketchybar --reload 2>/dev/null || true
command -v aerospace  >/dev/null 2>&1 && aerospace reload-config 2>/dev/null || true
if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
  tmux source-file ~/.tmux.conf 2>/dev/null || true
fi

echo "[apply] done"
