#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[0/9] Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "[1/9] Updating Homebrew..."
brew update

echo "[2/9] Installing all packages via Brewfile..."
brew bundle --file="$REPO_DIR/Brewfile"

echo "[3/9] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[4/9] Installing Rokit (Roblox toolchain manager)..."
# Rokit manages per-project Roblox tools (rojo/stylua/selene) pinned in each
# project's rokit.toml. The installer appends `. "$HOME/.rokit/env"` to
# ~/.zshenv so the tools land on PATH in new shells. Run `rokit install` inside
# a Roblox project (e.g. ~/Desktop/marooned) to fetch its pinned tools.
if ! command -v rokit >/dev/null 2>&1 && [ ! -x "$HOME/.rokit/bin/rokit" ]; then
  curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
  "$HOME/.rokit/bin/rokit" self-install
fi

# luau-lsp: the Luau language server (autocomplete/type-checking in nvim, wired
# into nvim/init.lua's servers list). Not in Homebrew — fetch the prebuilt
# macOS binary from GitHub releases into ~/.local/bin (already on PATH via zshrc).
if ! command -v luau-lsp >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  _luau_tmp="$(mktemp -d)"
  if gh release download --repo JohnnyMorganz/luau-lsp --pattern 'luau-lsp-macos.zip' \
       --dir "$_luau_tmp" 2>/dev/null; then
    unzip -o "$_luau_tmp/luau-lsp-macos.zip" -d "$_luau_tmp" >/dev/null
    _luau_bin="$(find "$_luau_tmp" -name luau-lsp -type f | head -1)"
    chmod +x "$_luau_bin"
    mv -f "$_luau_bin" "$HOME/.local/bin/luau-lsp"
    xattr -d com.apple.quarantine "$HOME/.local/bin/luau-lsp" 2>/dev/null || true
    echo "  installed luau-lsp $("$HOME/.local/bin/luau-lsp" --version 2>/dev/null)"
  else
    echo "  WARN: could not download luau-lsp (needs authenticated gh); install manually"
  fi
  rm -rf "$_luau_tmp"
fi

echo "[5/9] Linking configs..."
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
# Display-watcher daemon — bash polling loop that watches the connected
# monitor set and runs set-main-display.sh auto whenever it changes. Loaded
# as the com.ostepan.display-watcher LaunchAgent below. (Polling beats a
# CGDisplayRegisterReconfigurationCallback Swift daemon here — CG callbacks
# silently drop events when fired from a launchd context, and the ~3s poll
# is well under 0.1% CPU.)
# display-watcher.sh is copied in the `cp aerospace/*.sh` step above; this
# block just makes the dependency on it explicit and removes any stale
# Swift binary from earlier iterations.
rm -f ~/.config/aerospace/display-watcher ~/.config/aerospace/display-watcher.swift
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

echo "[6/9] Linking zsh + git + claude config..."
# Back up any existing .zshrc once
[ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.backup" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp -f "$REPO_DIR/zsh/zshrc" ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt
# Back up an existing global gitconfig once, then install ours
[ -f "$HOME/.gitconfig" ] && [ ! -f "$HOME/.gitconfig.backup" ] && cp "$HOME/.gitconfig" "$HOME/.gitconfig.backup"
cp -f "$REPO_DIR/git/gitconfig" ~/.gitconfig
cp -f "$REPO_DIR/git/gitignore_global" ~/.gitignore_global
# Claude Code: install global settings + MCP registrations + custom rules + skills.
# NOTE: the zshrc export and the ccd/ccds/ccdw aliases run Claude against the
# ~/.claude-personal / ~/.claude-school / ~/.claude-work profile dirs — NOT the
# vanilla ~/.claude — so config must be installed into each profile to take
# effect. Skips sessions/, projects/, and the local-only settings.local.json.
for cfg in "$HOME/.claude-personal" "$HOME/.claude-school" "$HOME/.claude-work"; do
  mkdir -p "$cfg/rules" "$cfg/skills"
  [ -f "$cfg/settings.json" ] && [ ! -f "$cfg/settings.json.backup" ] && cp "$cfg/settings.json" "$cfg/settings.json.backup"
  cp -f "$REPO_DIR/claude/settings.json" "$cfg/settings.json"
  cp -f "$REPO_DIR/claude/mcp.json" "$cfg/.mcp.json"
  cp -R "$REPO_DIR/claude/rules/." "$cfg/rules/"
  cp -R "$REPO_DIR/claude/skills/." "$cfg/skills/"
done

echo "[7/9] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[8/9] Applying macOS defaults + setting default file handlers + starting services..."
bash "$SCRIPT_DIR/defaults.sh"
for ext in sh command tool zsh bash; do
  duti -s com.mitchellh.ghostty ".$ext" all 2>/dev/null || true
done
skhd --start-service 2>/dev/null || true
brew services start felixkratz/formulae/sketchybar 2>/dev/null || true
open -a AeroSpace 2>/dev/null || true
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (first load will clone zsh plugins — ~10s one-time)"
echo "  2. In tmux, press prefix + I to install tmux plugins"
echo "  3. Launch nvim to finish plugin installation"
echo ""
echo "IMPORTANT: hotkeys + window manager need Accessibility permission."
echo "    System Settings → Privacy & Security → Accessibility"
echo "      - skhd       (/opt/homebrew/bin/skhd)         ← Opt+Space, Opt+B/W/S/M/E"
echo "      - AeroSpace  (/Applications/AeroSpace.app)    ← Alt+1-9 workspaces, Alt+h/j/k/l"
echo ""
echo "After toggling them ON, restart both so the new perms take effect:"
echo "    skhd --restart-service"
echo "    killall AeroSpace 2>/dev/null; open -a AeroSpace"
echo ""
echo "Then test:"
echo "  Opt+Space     → new Ghostty window"
echo "  Opt+\` (tick)  → toggle Ghostty drop-down terminal"
echo "  Alt+1..9      → switch AeroSpace workspaces"
