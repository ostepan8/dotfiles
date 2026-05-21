#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[0/8] Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "[1/8] Updating Homebrew..."
brew update

echo "[2/8] Installing all packages via Brewfile..."
brew bundle --file="$REPO_DIR/Brewfile"

echo "[3/8] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[4/8] Linking configs..."
mkdir -p ~/.config/nvim ~/.config/ghostty ~/.config/aerospace ~/.config/sketchybar/plugins
cp -f "$REPO_DIR/nvim/init.lua" ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml" ~/.config/starship.toml
cp -f "$REPO_DIR/ghostty/config" ~/.config/ghostty/config
cp -f "$REPO_DIR/skhd/skhdrc" ~/.skhdrc
cp -f "$REPO_DIR/aerospace/aerospace.toml" ~/.config/aerospace/aerospace.toml
cp -f "$REPO_DIR/aerospace/"*.sh ~/.config/aerospace/ 2>/dev/null || true
chmod +x ~/.config/aerospace/*.sh 2>/dev/null || true
# displays.env holds machine-specific persistent display IDs. Don't overwrite an
# existing one — those IDs only apply to this machine.
[ -f ~/.config/aerospace/displays.env ] || cp -f "$REPO_DIR/aerospace/displays.env" ~/.config/aerospace/displays.env
# Phantom-window watchdog helper — Swift program that asks each running
# app via the AX API how many windows it really has, so cleanup-phantoms.sh
# can detect stale-window phantoms (process alive but window already closed).
# Lazy-compiled by cleanup-phantoms.sh on first run if missing, but we
# build it eagerly at setup time so the very first cleanup is fast.
if [ -f "$REPO_DIR/aerospace/list-real-windows.swift" ]; then
  cp -f "$REPO_DIR/aerospace/list-real-windows.swift" ~/.config/aerospace/list-real-windows.swift
  if command -v swiftc >/dev/null 2>&1; then
    swiftc -O ~/.config/aerospace/list-real-windows.swift -o ~/.config/aerospace/list-real-windows \
      && echo "  compiled aerospace/list-real-windows"
  fi
fi
# Display-watcher daemon — Swift program that listens for CoreGraphics
# display reconfiguration events and runs set-main-display.sh auto whenever
# the screen layout changes (plug, unplug, rotation, resolution swap).
# Loaded as the com.ostepan.display-watcher LaunchAgent below.
if [ -f "$REPO_DIR/aerospace/display-watcher.swift" ]; then
  cp -f "$REPO_DIR/aerospace/display-watcher.swift" ~/.config/aerospace/display-watcher.swift
  if command -v swiftc >/dev/null 2>&1; then
    swiftc -O ~/.config/aerospace/display-watcher.swift -o ~/.config/aerospace/display-watcher \
      && echo "  compiled aerospace/display-watcher"
  fi
fi
cp -f "$REPO_DIR/sketchybar/sketchybarrc" ~/.config/sketchybar/sketchybarrc
cp -f "$REPO_DIR/sketchybar/plugins/"*.sh ~/.config/sketchybar/plugins/
chmod +x ~/.config/sketchybar/sketchybarrc ~/.config/sketchybar/plugins/*.sh
[ -f "$REPO_DIR/tmux/.tmux.conf" ] && cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf

# Install LaunchAgents (per-user background services). The aerospace-cleanup
# agent runs every 60s and surgically drops phantom windows from AeroSpace's
# tiling tree (both dead-PID phantoms and stale-window phantoms where the
# process is alive but the window was closed without notifying AeroSpace).
# Fixes the "new app opens at 1/N of the screen" bug where the tiling tree
# counts ghost windows from already-closed apps.
mkdir -p ~/Library/LaunchAgents
for plist in "$REPO_DIR/mac/LaunchAgents/"*.plist; do
  [ -f "$plist" ] || continue
  label="$(basename "$plist" .plist)"
  cp -f "$plist" "$HOME/Library/LaunchAgents/$(basename "$plist")"
  launchctl unload "$HOME/Library/LaunchAgents/$(basename "$plist")" 2>/dev/null || true
  launchctl load    "$HOME/Library/LaunchAgents/$(basename "$plist")"
  echo "  loaded LaunchAgent: $label"
done

echo "[5/8] Linking zsh + git + claude config..."
# Back up any existing .zshrc once
[ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.backup" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp -f "$REPO_DIR/zsh/zshrc" ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt
# Back up an existing global gitconfig once, then install ours
[ -f "$HOME/.gitconfig" ] && [ ! -f "$HOME/.gitconfig.backup" ] && cp "$HOME/.gitconfig" "$HOME/.gitconfig.backup"
cp -f "$REPO_DIR/git/gitconfig" ~/.gitconfig
cp -f "$REPO_DIR/git/gitignore_global" ~/.gitignore_global
# Claude Code: install global settings + MCP registrations + custom rules.
# Skips skills/, sessions/, projects/, and the local-only settings.local.json.
mkdir -p ~/.claude
[ -f "$HOME/.claude/settings.json" ] && [ ! -f "$HOME/.claude/settings.json.backup" ] && cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.backup"
cp -f "$REPO_DIR/claude/settings.json" ~/.claude/settings.json
cp -f "$REPO_DIR/claude/mcp.json" ~/.claude/.mcp.json
mkdir -p ~/.claude/rules
cp -R "$REPO_DIR/claude/rules/." ~/.claude/rules/

echo "[6/8] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[7/8] Applying macOS defaults + setting default file handlers + starting services..."
bash "$SCRIPT_DIR/defaults.sh"
for ext in sh command tool zsh bash; do
  duti -s com.mitchellh.ghostty ".$ext" all 2>/dev/null || true
done
skhd --start-service 2>/dev/null || true
brew services start felixkratz/formulae/sketchybar 2>/dev/null || true
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (first load will clone zsh plugins — ~10s one-time)"
echo "  2. In tmux, press prefix + I to install tmux plugins"
echo "  3. Launch nvim to finish plugin installation"
echo ""
echo "Opt+Space hotkey — grant Accessibility permission to skhd:"
echo "    System Settings → Privacy & Security → Accessibility"
echo "      - skhd   (/opt/homebrew/bin/skhd)"
echo ""
echo "Then press Opt+Space from anywhere to launch a new Ghostty window."
echo "Opt+\` (Opt+backtick) toggles the Ghostty drop-down quick terminal."
