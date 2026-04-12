#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[0/10] Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "[1/10] Updating Homebrew..."
brew update

echo "[2/10] Installing core developer tools..."
brew install neovim git tmux node python ripgrep

echo "[3/10] Installing LSP servers & formatters..."
brew install pyright llvm black clang-format

echo "[4/10] Installing terminal tools..."
brew install fzf fd jq bat eza gh starship

echo "[5/10] Installing git tools..."
brew install lazygit git-delta

echo "[6/10] Installing zsh plugins..."
brew install zsh-autosuggestions zsh-syntax-highlighting

echo "[7/10] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[8/10] Linking configs..."
mkdir -p ~/.config/nvim
cp -f "$REPO_DIR/nvim/init.lua" ~/.config/nvim/init.lua
cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf
mkdir -p ~/.config
cp -f "$REPO_DIR/starship/starship.toml" ~/.config/starship.toml

echo "[9/10] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[10/10] Bootstrapping Neovim plugins..."
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal or run: source ~/.zshrc"
echo "  2. In tmux, press prefix + I to install tmux plugins"
echo "  3. Launch nvim to finish plugin installation"
