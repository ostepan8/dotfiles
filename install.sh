#!/usr/bin/env bash
# install.sh — bootstrap a machine, then hand off to apply.sh.
#
# Replaces mac/setup.sh and linux/setup.sh, which each carried their own copy of
# the "which file goes where" list and had drifted apart. Placement now lives in
# manifest.conf and is applied by one engine; this script only does the things
# that must happen BEFORE a config can be applied — packages and plugin managers
# — plus the macOS-only bits that are not file placement at all.
#
# Idempotent and safe to re-run on a machine that is already set up. That is the
# whole point of having one.
#
#   ./install.sh                 bootstrap + apply
#   ./install.sh --no-packages   skip package installation, just apply
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES
cd "$DOTFILES" || exit 1

SKIP_PACKAGES=0
[ "${1:-}" = "--no-packages" ] && SKIP_PACKAGES=1

. "$DOTFILES/lib/reloads.sh"
. "$DOTFILES/lib/engine.sh"

ACTIVE_LAYERS="$(resolve_layers)"
export ACTIVE_LAYERS
OS="$(uname)"

echo "==> machine: ${OS}, layers: $ACTIVE_LAYERS"

# ---------------------------------------------------------------------------
# 1. record the machine type, if it was never set
# ---------------------------------------------------------------------------
if [ ! -f "$HOME/.dotfiles-host" ]; then
  echo
  echo "  No ~/.dotfiles-host — this machine will get the 'base' layer only."
  echo "  To give it more, write a type from hosts/layers.conf, e.g.:"
  echo "      echo studio > ~/.dotfiles-host    # then re-run"
  echo
fi

# ---------------------------------------------------------------------------
# 2. packages
# ---------------------------------------------------------------------------
if [ "$SKIP_PACKAGES" = "1" ]; then
  echo "==> skipping packages (--no-packages)"
else
  echo "==> packages"
  case "$OS" in
    Darwin) . "$DOTFILES/lib/packages/darwin.sh" ;;
    Linux)  . "$DOTFILES/lib/packages/linux.sh" ;;
    *)      echo "  unknown OS '$OS' — skipping packages" ;;
  esac
fi

# ---------------------------------------------------------------------------
# 3. plugin managers — cloned, never vendored
# ---------------------------------------------------------------------------
echo "==> plugin managers"
if [ ! -d "$HOME/.local/share/nvim/lazy/lazy.nvim" ]; then
  git clone --depth=1 https://github.com/folke/lazy.nvim.git \
    "$HOME/.local/share/nvim/lazy/lazy.nvim" && echo "  lazy.nvim"
fi
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone --depth=1 https://github.com/tmux-plugins/tpm \
    "$HOME/.tmux/plugins/tpm" && echo "  tpm"
fi
# antidote: Homebrew provides it on macOS; clone it on Linux.
if [ "$OS" = "Linux" ] && [ ! -d "$HOME/.antidote" ]; then
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote" \
    && echo "  antidote"
fi

# ---------------------------------------------------------------------------
# 4. place every managed file
# ---------------------------------------------------------------------------
echo "==> applying config"
bash "$DOTFILES/apply.sh"

# ---------------------------------------------------------------------------
# 5. macOS workstation extras — not file placement, so not in the manifest
# ---------------------------------------------------------------------------
if [ "$OS" = "Darwin" ] && layer_active workstation; then
  echo "==> macOS defaults and services"
  bash "$DOTFILES/workstation/macos/defaults.sh"

  for ext in command tool zsh bash; do
    duti -s com.mitchellh.ghostty ".$ext" all 2>/dev/null || true
  done

  skhd --start-service 2>/dev/null || true
  brew services start felixkratz/formulae/sketchybar 2>/dev/null || true
  open -a AeroSpace 2>/dev/null || true

  echo "==> NvimOpener.app (Finder -> nvim)"
  bash "$DOTFILES/workstation/macos/NvimOpener/build.sh"
fi

# Bootstrap nvim plugins headlessly so the first real launch is fast.
nvim --headless +qa 2>/dev/null || true

# ---------------------------------------------------------------------------
echo
echo "Done."
echo
echo "Next:"
echo "  1. open a new terminal (first load clones zsh plugins, ~10s one-time)"
echo "  2. in tmux, prefix + I to install tmux plugins"
if [ "$OS" = "Linux" ]; then
  echo "  3. make zsh the default shell:  chsh -s \$(command -v zsh)"
fi
if [ "$OS" = "Darwin" ] && layer_active workstation; then
  cat <<'EOF'

Hotkeys and the window manager need Accessibility permission:
    System Settings -> Privacy & Security -> Accessibility
      - skhd       (/opt/homebrew/bin/skhd)
      - AeroSpace  (/Applications/AeroSpace.app)

Then restart both so the new permissions take effect:
    skhd --restart-service
    killall AeroSpace 2>/dev/null; open -a AeroSpace
EOF
fi
