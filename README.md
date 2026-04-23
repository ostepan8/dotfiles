# dotfiles

My complete dev environment for a fresh macOS or Linux machine. Shell, editor, multiplexer, prompt, and supporting CLI tools — installed and configured with one command.

## What's included

- **zsh/** — shell config with lazy-loading (nvm, conda), plugins (autosuggestions, fzf-tab, syntax-highlighting, history-substring-search), fzf + zoxide integration, useful aliases
- **nvim/** — Neovim config (gruvbox, telescope, treesitter, LSP, autocomplete, format-on-save)
- **tmux/** — tmux config (Alt+number window switching, vim-style pane nav, mouse, plugins)
- **starship/** — minimal prompt with git info
- **ghostty/** — Ghostty terminal config (Gruvbox Dark Hard, JetBrainsMono Nerd Font, transparent titlebar, drop-down quick terminal on `Opt+\``)
- **skhd/** — global hotkey daemon config (`Opt+Space` opens a new Ghostty window on the current workspace; `Opt+B`/`Opt+W` launch Chrome with personal/work profiles; `Opt+S/M/E` launch Slack/Spotify/Finder)
- **aerospace/** — i3-style tiling window manager config (workspaces on `Alt+1-9`, vim-style window focus on `Alt+h/j/k/l`)
- **sketchybar/** — custom top bar (Gruvbox theme) with Aerospace workspace indicators, front-app, CPU, battery, clock
- **mac/setup.sh** — macOS installer (Homebrew) — also runs `mac/defaults.sh`
- **mac/defaults.sh** — macOS system tweaks (Finder, Dock, keyboard, trackpad, screenshot location, etc.)
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
| ghostty | Terminal emulator (replaces Terminal.app; default handler for `.sh`/`.command`/`.tool`/`.zsh`/`.bash`) |
| skhd | Global hotkey daemon (`Opt+Space` → open Ghostty) |
| aerospace | Tiling window manager (keyboard-driven workspaces + window arrangement) |
| sketchybar | Custom top bar with workspace indicators + system stats |
| duti | Set default app handlers for file types (used to make Ghostty the default terminal) |
| dockutil | Manage Dock items from the command line |
| starship | Shell prompt |
| antidote | zsh plugin manager |
| fzf | Fuzzy finder (Ctrl+R, Ctrl+T, Alt+C) |
| zoxide | Smart `cd` replacement (`z <fragment>`) |
| atuin | Shell history database (fuzzy `Ctrl+R`, synced, timestamped) |
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

### Global (skhd + Ghostty)

| Key | Action |
|-----|--------|
| `Opt+Space` | Open new Ghostty window (launches Ghostty if dead) |
| `` Opt+` `` | Toggle Ghostty drop-down quick terminal (only while Ghostty is running) |
| `Opt+B` | Chrome — personal profile (new window on current workspace) |
| `Opt+W` | Chrome — work profile (new window on current workspace) |
| `Opt+S` | Slack |
| `Opt+M` | Spotify |
| `Opt+E` | New Finder window |

### Aerospace (tiling window manager)

| Key | Action |
|-----|--------|
| `Alt+1..9` | Jump to workspace 1..9 |
| `Alt+Shift+1..9` | Move current window to workspace N |
| `Alt+H/J/K/L` | Focus window left/down/up/right |
| `Alt+Shift+H/J/K/L` | Move window in that direction |
| `Alt+-` / `Alt+=` | Shrink / grow focused window |
| `Alt+Shift+=` | Balance window sizes |
| `Alt+/` | Toggle tile orientation (horizontal/vertical) |
| `Alt+,` | Accordion stack layout |
| `Alt+F` | Fullscreen focused window |
| `Alt+Shift+Space` | Toggle float/tile on focused window |
| `Alt+Tab` | Jump to previous workspace (last-used) |
| `Alt+Shift+C` | Reload Aerospace config |

**Conflicts with the tmux config:**
- tmux `Alt+1-9` (window switch) → shadowed by Aerospace. Use tmux's `prefix + N` instead.
- tmux `Alt+h/j/k/l` (pane switch) → shadowed by Aerospace. Use `Ctrl+h/j/k/l` (vim-tmux-navigator) instead.

### Accessibility permissions

After installing, grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility) to:
- `skhd` (at `/opt/homebrew/bin/skhd`)
- `AeroSpace` (at `/Applications/AeroSpace.app`)

### Making Ghostty the default terminal everywhere

`mac/setup.sh` sets Ghostty as the default app for `.sh`/`.command`/`.tool`/`.zsh`/`.bash` files automatically (via `duti`). To also make Ghostty the external terminal in editors:

**Cursor / VS Code** — add to `settings.json`:
```json
"terminal.external.osxExec": "Ghostty.app",
"terminal.explorerKind": "external"
```

**IntelliJ IDEA / JetBrains** — Preferences → Tools → Terminal → set *Shell path* to `/Applications/Ghostty.app/Contents/MacOS/ghostty` (affects internal terminal). For "Open in Terminal" external calls, create an External Tool pointing at Ghostty.

**Dock** — remove Terminal.app, add Ghostty: `dockutil --remove Terminal; dockutil --add /Applications/Ghostty.app`.

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
