# dotfiles

My complete dev environment for a fresh macOS or Linux machine. Shell, editor, multiplexer, prompt, and supporting CLI tools — installed and configured with one command.

## What's included

- **zsh/** — shell config with lazy-loading (nvm, conda), plugins (autosuggestions, fzf-tab, syntax-highlighting, history-substring-search), fzf + zoxide integration, useful aliases
- **nvim/** — Neovim config (gruvbox, telescope, treesitter, LSP, autocomplete, format-on-save)
- **tmux/** — tmux config (Alt+number window switching, vim-style pane nav, mouse, plugins)
- **starship/** — minimal prompt with git info
- **mac/setup.sh** — macOS installer (Homebrew)
- **linux/setup.sh** — Linux installer (apt/dnf/pacman)

## Install

```bash
git clone https://github.com/ostepan8/dotfiles.git ~/dotfiles
cd ~/dotfiles

# macOS
./mac/setup.sh

# Linux
./linux/setup.sh
```

The installer backs up any existing `~/.zshrc` to `~/.zshrc.backup` the first time it runs.

After install:
1. Open a new terminal — antidote will clone zsh plugins (~10s, one-time).
2. In tmux, press `prefix + I` to install tmux plugins.
3. Launch `nvim` to finish plugin installation.

## Tools installed

| Tool | Purpose |
|------|---------|
| neovim | Editor |
| tmux | Terminal multiplexer |
| starship | Shell prompt |
| antidote | zsh plugin manager |
| fzf | Fuzzy finder (Ctrl+R, Ctrl+T, Alt+C) |
| zoxide | Smart `cd` replacement (`z <fragment>`) |
| fd | Fast file search |
| ripgrep | Fast text search |
| bat | `cat` with syntax highlighting |
| eza | Modern `ls` replacement |
| jq | JSON parser |
| lazygit | Git TUI |
| git-delta | Better git diffs |
| gh | GitHub CLI |

## Zsh features

### Lazy loading
`nvm` and `conda` are stubbed and only loaded on first use. Shell starts in ~120ms instead of ~800ms. Force-load anytime with `load_nvm` or `load_conda`.

### History
50k entries, shared across all open terminals in real time, deduplicated. Prefix a command with a space to keep it out of history (use for secrets).

### Plugins (via antidote)
- **zsh-autosuggestions** — type and see a gray-ghost suggestion from history. `→` accepts.
- **fzf-tab** — `<Tab>` opens a fuzzy-searchable picker for completions.
- **zsh-syntax-highlighting** — colors commands as you type (red = typo).
- **zsh-history-substring-search** — type a fragment, then `↑`/`↓` cycles through every matching history entry.

### fzf shortcuts
| Key | Action |
|-----|--------|
| `Ctrl+R` | Fuzzy history search |
| `Ctrl+T` | Fuzzy file picker (inserts path) |
| `Alt+C` | Fuzzy cd |

### zoxide
`z <fragment>` jumps to the most-visited directory matching the fragment. `zi` opens an interactive picker. Learns as you use regular `cd`.

### Aliases
| Alias | Expands to |
|-------|------------|
| `ll` / `la` | `ls -lh` / `ls -lAh` |
| `..` / `...` / `....` | `cd ..` up 1/2/3 levels |
| `gs` / `gd` / `gco` / `gl` | `git status` / `diff` / `checkout` / pretty log |
| `reload` | `source ~/.zshrc` |
| `ccd` / `ccrd` | `claude --dangerously-skip-permissions` (new / resume) |

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
