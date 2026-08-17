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

# Prefer the distro package for everything it actually ships. The upstream
# curl installers and .deb downloads below are fallbacks for older releases —
# and the .deb URLs were hardcoded to amd64, which silently produced no zoxide,
# atuin or delta on the aarch64 Pi while reporting success.
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"

# is this installable from the distro?
#
# Deliberately pipeline-free. The first version ended in `| grep -q`, and this
# script runs under `set -o pipefail`: grep -q exits at the first match, the
# producer takes SIGPIPE and returns 141, and pipefail propagates that as the
# pipeline's status. So have_pkg reported "not available" for EVERY package on a
# distro that had all of them, and the fallbacks silently took over — which is
# how the Pi ended up with a curl-installed atuin and no delta at all.
have_pkg() {
  local out
  case "$PKG" in
    apt)
      out="$(apt-cache policy "$1" 2>/dev/null)"
      case "$out" in *"Candidate: "[0-9]*) return 0 ;; *) return 1 ;; esac
      ;;
    dnf)    dnf -q list --available "$1" >/dev/null 2>&1 || dnf -q list --installed "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
  esac
}

pkg_install() {
  case "$PKG" in
    apt)    sudo apt install -y "$@" ;;
    dnf)    sudo dnf install -y "$@" ;;
    pacman) sudo pacman -S --noconfirm "$@" ;;
  esac
}

echo "  terminal tools"
case "$PKG" in
  apt)
    pkg_install fd-find bat
    # Debian ships these under alternate names to avoid collisions.
    need fdfind && ! need fd  && sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
    need batcat && ! need bat && sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
    ;;
  dnf)    pkg_install fd-find bat ;;
  pacman) pkg_install fd bat ;;
esac

echo "  git tools"
# lazygit and delta: distro package when available, arch-correct download if not.
if ! need lazygit; then
  if have_pkg lazygit; then pkg_install lazygit
  elif [ "$PKG" = "dnf" ]; then sudo dnf copr enable atim/lazygit -y && sudo dnf install -y lazygit
  else
    case "$ARCH" in
      amd64|x86_64) LG_ARCH=Linux_x86_64 ;;
      arm64|aarch64) LG_ARCH=Linux_arm64 ;;
      *) LG_ARCH="" ;;
    esac
    if [ -n "$LG_ARCH" ]; then
      v=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -fsSLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${v}_${LG_ARCH}.tar.gz" \
        && sudo tar xf /tmp/lazygit.tar.gz -C /usr/local/bin lazygit && rm -f /tmp/lazygit.tar.gz
    else
      echo "  WARN: no lazygit build for $ARCH"
    fi
  fi
fi

if ! need delta; then
  if   have_pkg git-delta; then pkg_install git-delta
  elif have_pkg git_delta; then pkg_install git_delta
  else echo "  WARN: no git-delta package for this distro/arch — skipping"
  fi
fi

# zoxide and atuin ship in modern Debian/Fedora. Only fall back to the upstream
# installers when they do not — those append to ~/.zshrc, which is a symlink
# into this repo, so they dirty tracked config for the whole fleet.
if ! need zoxide; then
  if have_pkg zoxide; then pkg_install zoxide
  else curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  fi
fi

if ! need atuin; then
  if have_pkg atuin; then pkg_install atuin
  else curl -sSf https://setup.atuin.sh | bash
  fi
fi

need starship || curl -sS https://starship.rs/install.sh | sh -s -- -y
if ! need gh; then
  case "$PKG" in
    apt)    sudo apt install -y gh ;;
    dnf)    sudo dnf install -y gh ;;
    pacman) sudo pacman -S --noconfirm github-cli ;;
  esac
fi
