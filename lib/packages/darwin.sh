#!/usr/bin/env bash
# Package bootstrap for macOS. Ported from mac/setup.sh.
#
# Only ever runs on a workstation: every Mac in this fleet has a human in front
# of it. The Brewfile lives in workstation/ for the same reason.
set -uo pipefail

need() { command -v "$1" >/dev/null 2>&1; }

if ! need brew; then
  echo "  installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "  brew update"
brew update

echo "  brew bundle"
brew bundle --file="$DOTFILES/workstation/Brewfile"

# Rokit manages per-project Roblox tools (rojo/stylua/selene) pinned in each
# project's rokit.toml. Its installer appends `. "$HOME/.rokit/env"` to ~/.zshenv
# so the tools land on PATH in new shells.
if ! need rokit && [ ! -x "$HOME/.rokit/bin/rokit" ]; then
  echo "  installing rokit"
  curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
  "$HOME/.rokit/bin/rokit" self-install
fi

# luau-lsp: the Luau language server, wired into nvim's servers list. Not in
# Homebrew — fetch the prebuilt macOS binary into ~/.local/bin (already on PATH).
if ! need luau-lsp; then
  echo "  installing luau-lsp"
  mkdir -p "$HOME/.local/bin"
  tmp="$(mktemp -d)"
  if gh release download --repo JohnnyMorganz/luau-lsp --pattern 'luau-lsp-macos.zip' \
       --dir "$tmp" 2>/dev/null; then
    unzip -o "$tmp/luau-lsp-macos.zip" -d "$tmp" >/dev/null
    bin="$(find "$tmp" -name luau-lsp -type f | head -1)"
    chmod +x "$bin"
    mv -f "$bin" "$HOME/.local/bin/luau-lsp"
    xattr -d com.apple.quarantine "$HOME/.local/bin/luau-lsp" 2>/dev/null || true
  else
    echo "  WARN: could not download luau-lsp (needs authenticated gh); install manually"
  fi
  rm -rf "$tmp"
fi
