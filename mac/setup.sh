#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[0/11] Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "[1/11] Updating Homebrew..."
brew update

echo "[2/11] Installing core developer tools..."
brew install neovim git tmux node python ripgrep

echo "[3/11] Installing LSP servers & formatters..."
brew install pyright llvm black clang-format

echo "[4/11] Installing terminal tools..."
brew install fzf fd jq bat eza gh starship zoxide

echo "[5/11] Installing git tools..."
brew install lazygit git-delta

echo "[6/11] Installing zsh plugin manager..."
brew install antidote

echo "[7/11] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[8/11] Linking configs..."
mkdir -p ~/.config/nvim ~/.config
cp -f "$REPO_DIR/nvim/init.lua" ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml" ~/.config/starship.toml
[ -f "$REPO_DIR/tmux/.tmux.conf" ] && cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf

echo "[9/11] Linking zsh config..."
# Back up any existing .zshrc once
[ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.backup" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp -f "$REPO_DIR/zsh/zshrc" ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt

echo "[10/11] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[11/11] Bootstrapping Neovim plugins..."
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (first load will clone zsh plugins — ~10s one-time)"
echo "  2. In tmux, press prefix + I to install tmux plugins"
echo "  3. Launch nvim to finish plugin installation"
