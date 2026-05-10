#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1; }

echo "[0/14] Detecting package manager..."
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

echo "[1/14] Updating package database..."
case "$PKG" in
    apt)    sudo apt update ;;
    dnf)    sudo dnf check-update || true ;;
    pacman) sudo pacman -Sy ;;
esac

echo "[2/14] Installing core developer tools..."
case "$PKG" in
    apt)
        sudo apt install -y neovim git tmux zsh nodejs npm python3 python3-pip ripgrep curl unzip xclip
        ;;
    dnf)
        sudo dnf install -y neovim git tmux zsh nodejs npm python3 python3-pip ripgrep curl unzip xclip
        ;;
    pacman)
        sudo pacman -Syu --noconfirm neovim git tmux zsh nodejs npm python python-pip ripgrep curl unzip xclip
        ;;
esac

echo "[3/14] Installing LSP servers & formatters..."
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

echo "[4/14] Installing terminal tools..."
case "$PKG" in
    apt)
        sudo apt install -y fzf fd-find bat jq
        if need fdfind && ! need fd; then
            sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
        fi
        if need batcat && ! need bat; then
            sudo ln -sf "$(which batcat)" /usr/local/bin/bat
        fi
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

echo "[5/14] Installing git tools..."
case "$PKG" in
    apt)
        if ! need lazygit; then
            LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
            curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
            sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit
            rm /tmp/lazygit.tar.gz
        fi
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

echo "[6/14] Installing starship prompt..."
if ! need starship; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

echo "[7/14] Installing atuin (shell history)..."
if ! need atuin; then
    curl -sSf https://setup.atuin.sh | bash
fi

echo "[8/14] Installing GitHub CLI..."
if ! need gh; then
    case "$PKG" in
        dnf) sudo dnf install -y gh ;;
        apt) sudo apt install -y gh ;;
        pacman) sudo pacman -S --noconfirm github-cli ;;
    esac
fi

echo "[9/14] Installing antidote (zsh plugin manager)..."
if [ ! -d "$HOME/.antidote" ]; then
    git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"
fi

echo "[10/14] Installing lazy.nvim..."
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone https://github.com/folke/lazy.nvim.git \
    ~/.local/share/nvim/lazy/lazy.nvim
fi

echo "[11/14] Linking configs..."
mkdir -p ~/.config/nvim ~/.config/ghostty
cp -f "$REPO_DIR/nvim/init.lua" ~/.config/nvim/init.lua
cp -f "$REPO_DIR/starship/starship.toml" ~/.config/starship.toml
cp -f "$REPO_DIR/ghostty/config" ~/.config/ghostty/config
[ -f "$REPO_DIR/tmux/.tmux.conf" ] && cp -f "$REPO_DIR/tmux/.tmux.conf" ~/.tmux.conf

echo "[12/14] Linking zsh config..."
[ -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.zshrc.backup" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
cp -f "$REPO_DIR/zsh/zshrc" ~/.zshrc
cp -f "$REPO_DIR/zsh/zsh_plugins.txt" ~/.zsh_plugins.txt

echo "[13/14] Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

echo "[14/14] Bootstrapping Neovim plugins..."
nvim --headless +qa 2>/dev/null || true

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Set zsh as default shell:  chsh -s \$(which zsh)"
echo "  2. Open a new terminal (first load will clone zsh plugins — ~10s one-time)"
echo "  3. In tmux, press prefix + I to install tmux plugins"
echo "  4. Launch nvim to finish plugin installation"
echo ""
echo "Optional desktop setup (GNOME auto-tiling + Alt+N workspaces):"
echo "  bash $SCRIPT_DIR/setup-desktop.sh"
