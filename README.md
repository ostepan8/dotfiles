# dotfiles

Neovim, tmux, and terminal config for macOS and Linux.

## What's included

- **nvim/** - Neovim config (gruvbox, telescope, treesitter, LSP, autocomplete, format-on-save)
- **tmux/** - tmux config (Alt+number window switching, vim-style pane nav, mouse, plugins)
- **starship/** - Minimal prompt with git info
- **mac/setup.sh** - macOS installer (uses Homebrew)
- **linux/setup.sh** - Linux installer (apt/dnf/pacman)

## Install

```bash
git clone https://github.com/ostepan8/neo-vim-config.git
cd neo-vim-config

# macOS
./mac/setup.sh

# Linux
./linux/setup.sh
```

## Tools installed

| Tool | Purpose |
|------|---------|
| neovim | Editor |
| tmux | Terminal multiplexer |
| starship | Shell prompt |
| fzf | Fuzzy finder |
| fd | Fast file search |
| ripgrep | Fast text search |
| bat | cat with syntax highlighting |
| jq | JSON parser |
| lazygit | Git TUI |
| git-delta | Better git diffs |

## Key bindings

### tmux

| Key | Action |
|-----|--------|
| Alt+1-9 | Jump to window N |
| Shift+Left/Right | Prev/next window |
| Ctrl+a then Tab | Last window |
| Alt+h/j/k/l | Switch panes |
| Ctrl+a then \| | Split horizontal |
| Ctrl+a then - | Split vertical |
| Ctrl+a then r | Reload config |

### nvim

| Key | Action |
|-----|--------|
| Space+f | Find files |
| Space+g | Live grep |
| Space+e | Toggle file tree |
| Space+b | List buffers |
| gd | Go to definition |
| K | Hover docs |
| Space+rn | Rename symbol |
| Space+ca | Code actions |
