#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[0/13] Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "[1/13] Updating Homebrew..."
brew update

echo "[2/13] Installing core developer tools..."
brew install neovim git tmux node python ripgrep

echo "[3/13] Installing LSP servers & formatters..."
brew install pyright llvm black clang-format

echo "[4/13] Installing terminal tools..."
brew install fzf fd jq bat eza gh starship zoxide

echo "[5/13] Installing git tools..."
brew install lazygit git-delta

echo "[6/13] Installing zsh plugin manager..."
brew install antidote

echo "[7/13] Installing Ghostty terminal + skhd + aerospace + CLI utilities..."
brew install --cask ghostty
brew install --cask nikitabobko/tap/aerospace
brew install koekeishiya/formulae/skhd duti dockutil

echo "[8/13] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[9/13] Linking configs..."
mkdir -p ~/.config/nvim ~/.config/ghostty ~/.config/aerospace ~/Applications
cp -f "$REPO_DIR/nvim/init.lua" ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml" ~/.config/starship.toml
cp -f "$REPO_DIR/ghostty/config" ~/.config/ghostty/config
cp -f "$REPO_DIR/skhd/skhdrc" ~/.skhdrc
cp -f "$REPO_DIR/aerospace/aerospace.toml" ~/.config/aerospace/aerospace.toml
[ -f "$REPO_DIR/tmux/.tmux.conf" ] && cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf

echo "[10/13] Compiling OpenGhostty.app launcher..."
rm -rf ~/Applications/OpenGhostty.app
osacompile -o ~/Applications/OpenGhostty.app "$REPO_DIR/skhd/open-ghostty.applescript"

echo "[11/13] Linking zsh config..."
# Back up any existing .zshrc once
[ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.backup" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp -f "$REPO_DIR/zsh/zshrc" ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt

echo "[12/13] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[13/13] Setting Ghostty as default terminal file handler + starting services..."
for ext in sh command tool zsh bash; do
  duti -s com.mitchellh.ghostty ".$ext" all 2>/dev/null || true
done
skhd --start-service 2>/dev/null || true
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (first load will clone zsh plugins — ~10s one-time)"
echo "  2. In tmux, press prefix + I to install tmux plugins"
echo "  3. Launch nvim to finish plugin installation"
echo ""
echo "Opt+Space hotkey — grant Accessibility permission to:"
echo "    System Settings → Privacy & Security → Accessibility"
echo "      - skhd                          (/opt/homebrew/bin/skhd)"
echo "      - OpenGhostty                   (~/Applications/OpenGhostty.app)"
echo "      - applet                        (generic AppleScript runner, usually auto-added)"
echo ""
echo "Then press Opt+Space from anywhere to launch Ghostty."
echo "Opt+\` (Opt+backtick) toggles the Ghostty drop-down quick terminal."
