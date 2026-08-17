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

# Verify a binary actually runs, and remove it if not.
#
# A wrong-architecture binary still satisfies `command -v`, so `need <tool>`
# returns true forever and the correct package can never install. That happened
# on the aarch64 Pi: the amd64 fallback dropped an x86-64 lazygit into
# /usr/local/bin, which looked installed and silently shadowed the working apt
# build. Anything fetched by architecture gets checked.
verify_bin() {
  local name="$1" path
  path="$(command -v "$name" 2>/dev/null)" || return 1
  if "$path" --version >/dev/null 2>&1; then
    return 0
  fi
  echo "  WARN: $path does not execute here (wrong arch?) — removing"
  sudo rm -f "$path"
  return 1
}

pkg_install() {
  case "$PKG" in
    apt)    sudo apt install -y "$@" ;;
    dnf)    sudo dnf install -y "$@" ;;
    pacman) sudo pacman -S --noconfirm "$@" ;;
  esac
}


# Neovim must be 0.11+: the config uses nvim-treesitter's main branch, and
# telescope and nvim-lspconfig both hard-require 0.11. Debian trixie ships
# 0.10.4 with no backport, so the Pi loaded with five errors and those plugins
# simply did not work.
#
# Upstream publishes per-arch tarballs, so this is a general version floor
# rather than a Pi-specific workaround: any distro too far behind gets the
# official build, and distros that are current keep their package.
NVIM_MIN_MINOR=11
ensure_nvim() {
  local cur minor arch url tmp
  cur="$(nvim --version 2>/dev/null | head -1 | sed -n 's/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p')"
  minor="${cur#*.}"
  if [ -n "$cur" ] && [ "${minor:-0}" -ge "$NVIM_MIN_MINOR" ] 2>/dev/null; then
    return 0
  fi
  echo "  neovim ${cur:-none} is below 0.$NVIM_MIN_MINOR — installing the upstream build"

  case "$ARCH" in
    amd64|x86_64)  arch=x86_64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) echo "  WARN: no upstream neovim build for $ARCH — leaving the distro version"; return 0 ;;
  esac

  url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  if ! curl -fsSL "$url" -o "$tmp/nvim.tar.gz"; then
    echo "  WARN: could not download $url"; rm -rf "$tmp"; return 0
  fi
  tar xzf "$tmp/nvim.tar.gz" -C "$tmp" || { echo "  WARN: bad tarball"; rm -rf "$tmp"; return 0; }

  # Install beside the distro copy rather than over it: /usr/local/bin precedes
  # /usr/bin on PATH, so this wins without fighting dpkg or breaking apt upgrades.
  sudo rm -rf /opt/nvim
  sudo mv "$tmp/nvim-linux-${arch}" /opt/nvim
  sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -rf "$tmp"

  hash -r 2>/dev/null || true

  # Verify the OUTCOME, not just that the steps ran. The first version of this
  # function announced "installing the upstream build", then aborted on an
  # unbound $ARCH (it was called before ARCH was defined) and left 0.10.4 in
  # place — with no warning, because the abort happened mid-function. Check the
  # version actually moved and say so plainly if it did not.
  local now
  now="$(nvim --version 2>/dev/null | head -1 | sed -n 's/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p')"
  if [ "${now#*.}" -ge "$NVIM_MIN_MINOR" ] 2>/dev/null && verify_bin nvim; then
    echo "  neovim now $(nvim --version | head -1) (from /opt/nvim)"
  else
    echo "  WARN: neovim is still ${now:-unknown} — upstream install did not take."
    echo "        expected /usr/local/bin/nvim -> /opt/nvim/bin/nvim"
  fi
}
ensure_nvim


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
verify_bin lazygit >/dev/null 2>&1 || true
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
      verify_bin lazygit || echo "  WARN: no working lazygit for $ARCH"
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
