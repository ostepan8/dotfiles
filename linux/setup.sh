#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1; }

echo "[0/12] Detecting package manager..."
if need apt; then
    PKG=apt
elif need dnf; then
    PKG=dnf
elif need pacman; then
    PKG=pacman
else
    echo "Unsupported package manager. Install dependencies manually."
    exit 1
fi

echo "[1/12] Updating package database..."
case "$PKG" in
    apt)    sudo apt update ;;
    dnf)    sudo dnf check-update || true ;;
    pacman) sudo pacman -Sy ;;
esac

echo "[2/12] Installing core developer tools..."
case "$PKG" in
    apt)
        sudo apt install -y neovim git tmux nodejs npm python3 python3-pip ripgrep curl unzip xclip
        ;;
    dnf)
        sudo dnf install -y neovim git tmux nodejs npm python3 python3-pip ripgrep curl unzip xclip
        ;;
    pacman)
        sudo pacman -Syu --noconfirm neovim git tmux nodejs npm python python-pip ripgrep curl unzip xclip
        ;;
esac

echo "[3/12] Installing LSP servers & formatters..."
case "$PKG" in
    apt)
        sudo apt install -y clang-format llvm
        sudo npm install -g pyright
        pip3 install --user black
        ;;
    dnf)
        sudo dnf install -y clang-tools-extra llvm
        sudo npm install -g pyright
        pip3 install --user black
        ;;
    pacman)
        sudo pacman -S --noconfirm clang llvm
        sudo npm install -g pyright
        pip install --user black
        ;;
esac

echo "[4/12] Installing terminal tools..."
case "$PKG" in
    apt)
        sudo apt install -y fzf fd-find bat jq
        # fd is named fdfind on debian/ubuntu, symlink it
        if need fdfind && ! need fd; then
            sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
        fi
        # bat is named batcat on debian/ubuntu, symlink it
        if need batcat && ! need bat; then
            sudo ln -sf "$(which batcat)" /usr/local/bin/bat
        fi
        # zoxide isn't in older apt repos — use the upstream installer
        if ! need zoxide; then
            curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
        fi
        ;;
    dnf)
        sudo dnf install -y fzf fd-find bat jq zoxide
        ;;
    pacman)
        sudo pacman -S --noconfirm fzf fd bat jq zoxide
        ;;
esac

echo "[5/12] Installing git tools..."
case "$PKG" in
    apt)
        # lazygit via github release
        if ! need lazygit; then
            LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
            curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
            sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
            rm /tmp/lazygit.tar.gz
        fi
        # delta via github release
        if ! need delta; then
            DELTA_VERSION=$(curl -s "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*')
            curl -Lo /tmp/delta.deb "https://github.com/dandavison/delta/releases/latest/download/git-delta_${DELTA_VERSION}_amd64.deb"
            sudo dpkg -i /tmp/delta.deb
            rm /tmp/delta.deb
        fi
        ;;
    dnf)
        sudo dnf install -y git-delta
        if ! need lazygit; then
            sudo dnf copr enable atim/lazygit -y
            sudo dnf install -y lazygit
        fi
        ;;
    pacman)
        sudo pacman -S --noconfirm lazygit git-delta
        ;;
esac

echo "[6/12] Installing starship prompt..."
if ! need starship; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

echo "[7/12] Installing antidote (zsh plugin manager)..."
if [ ! -d "$HOME/.antidote" ]; then
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"
fi

echo "[8/12] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[9/12] Linking configs..."
mkdir -p ~/.config/nvim ~/.config
cp -f "$REPO_DIR/nvim/init.lua" ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml" ~/.config/starship.toml
[ -f "$REPO_DIR/tmux/.tmux.conf" ] && cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf

echo "[10/12] Linking zsh config..."
[ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.backup" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp -f "$REPO_DIR/zsh/zshrc" ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt

echo "[11/12] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[12/12] Bootstrapping Neovim plugins..."
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal (first load will clone zsh plugins — ~10s one-time)"
echo "  2. In tmux, press prefix + I to install tmux plugins"
echo "  3. Launch nvim to finish plugin installation"
