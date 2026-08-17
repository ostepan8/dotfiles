#!/usr/bin/env bash
# Package bootstrap for Linux nodes. Ported from linux/setup.sh.
#
# Every node in this fleet is headless, so nothing here installs or configures a
# desktop. (linux/setup-desktop.sh, which set up GNOME auto-tiling for machines
# whose lids are shut in a corner, was dropped in the restructure; git log keeps
# it if a Linux workstation ever appears.)
set -uo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

if   need apt;    then PKG=apt
elif need dnf;    then PKG=dnf
elif need pacman; then PKG=pacman
else
  echo "  unsupported package manager — install dependencies manually" >&2
  return 0 2>/dev/null || exit 0
fi

echo "  package manager: $PKG"

case "$PKG" in
  apt)    sudo apt update ;;
  dnf)    sudo dnf check-update || true ;;
  pacman) sudo pacman -Sy ;;
esac

echo "  core tools"
case "$PKG" in
  apt|dnf)
    sudo "$PKG" install -y neovim git tmux zsh nodejs npm python3 python3-pip \
      ripgrep curl unzip xclip fzf jq
    ;;
  pacman)
    sudo pacman -Syu --noconfirm neovim git tmux zsh nodejs npm python python-pip \
      ripgrep curl unzip xclip fzf jq
    ;;
esac

echo "  LSP servers and formatters"
case "$PKG" in
  apt) sudo apt install -y clang-format llvm ;;
  dnf) sudo dnf install -y clang-tools-extra llvm ;;
  pacman) sudo pacman -S --noconfirm clang llvm ;;
esac
need pyright || sudo npm install -g pyright
need black   || pip3 install --user black 2>/dev/null || pip install --user black

echo "  terminal tools"
case "$PKG" in
  apt)
    sudo apt install -y fd-find bat
    # Debian ships these under alternate names to avoid collisions.
    need fdfind && ! need fd  && sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    need batcat && ! need bat && sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
    need zoxide || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    ;;
  dnf)    sudo dnf install -y fd-find bat zoxide ;;
  pacman) sudo pacman -S --noconfirm fd bat zoxide ;;
esac

echo "  git tools"
case "$PKG" in
  apt)
    if ! need lazygit; then
      v=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${v}_Linux_x86_64.tar.gz" \
        && sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit && rm -f /tmp/lazygit.tar.gz
    fi
    if ! need delta; then
      v=$(curl -s "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*')
      curl -Lo /tmp/delta.deb "https://github.com/dandavison/delta/releases/latest/download/git-delta_${v}_amd64.deb" \
        && sudo dpkg -i /tmp/delta.deb && rm -f /tmp/delta.deb
    fi
    ;;
  dnf)
    sudo dnf install -y git-delta
    need lazygit || { sudo dnf copr enable atim/lazygit -y && sudo dnf install -y lazygit; }
    ;;
  pacman) sudo pacman -S --noconfirm lazygit git-delta ;;
esac

need starship || curl -sS https://starship.rs/install.sh | sh -s -- -y
need atuin    || curl -sSf https://setup.atuin.sh | bash
if ! need gh; then
  case "$PKG" in
    apt)    sudo apt install -y gh ;;
    dnf)    sudo dnf install -y gh ;;
    pacman) sudo pacman -S --noconfirm github-cli ;;
  esac
fi
