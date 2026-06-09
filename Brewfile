# Brewfile — declarative package list, installed with `brew bundle`.
#
# After install (or when adding things), run `brew bundle --file=Brewfile`
# from this repo root. Removing a line and running `brew bundle cleanup
# --file=Brewfile` will show what's installed but no longer declared.

# ---- taps ----
tap "felixkratz/formulae"            # sketchybar
tap "nikitabobko/tap"                # aerospace
tap "koekeishiya/formulae"           # skhd
tap "jakehilborn/jakehilborn"        # displayplacer

# ---- core developer tools ----
brew "neovim"
brew "git"
brew "git-lfs"
brew "tmux"
brew "node"
brew "python"
brew "ripgrep"

# ---- LSP servers & formatters ----
brew "pyright"
brew "llvm"
brew "black"
brew "clang-format"

# ---- Roblox / Luau dev ----
# lune: standalone Luau runtime for running logic/tests outside Studio.
# rojo/stylua/selene are pinned per-project via rokit (see mac/setup.sh).
# luau-lsp (language server) isn't in brew — setup.sh fetches the release binary.
brew "lune"

# ---- terminal tools ----
brew "fzf"
brew "fd"
brew "jq"
brew "bat"
brew "eza"
brew "gh"
brew "starship"
brew "zoxide"
brew "atuin"

# ---- git tooling ----
brew "lazygit"
brew "git-delta"

# ---- networking ----
# tailscale: mesh VPN to reach home machines (SSH, file transfer) from anywhere.
# The CLI daemon needs root, so after `brew bundle` run once:
#   sudo brew services start tailscale   # root LaunchDaemon, persists across reboots
#   sudo tailscale up                    # prints a login URL to authenticate
brew "tailscale"

# ---- zsh plugin manager ----
brew "antidote"

# ---- window mgr / hotkeys / bar ----
brew "sketchybar"
brew "skhd"
brew "duti"                          # set default file handlers
brew "dockutil"                      # manage Dock items from CLI

# displayplacer powers the alt-ctrl-[/]/enter bindings that swap which
# monitor is the macOS "main display". After install, run
# `displayplacer list` and copy the persistent display IDs into
# aerospace/displays.env on this machine.
brew "displayplacer"

# ---- casks ----
cask "ghostty"
cask "aerospace"
cask "google-chrome"
