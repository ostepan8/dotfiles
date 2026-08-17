# dotfiles

My complete dev environment for a fresh macOS or Linux machine. Shell, editor, multiplexer, prompt, and supporting CLI tools — installed and configured with one command.

## Layout

The repo splits by **role**, not by OS. OS is not what varies across this fleet:
the two Macs are ~95% identical to each other, the four Linux nodes are ~95%
identical to each other, and what actually differs is whether a human is sitting
in front of the machine.

```
base/          every machine       zsh git tmux starship nvim claude
workstation/   human in front      aerospace sketchybar skhd ghostty clangd Brewfile macos
server/        headless            overrides only (deliberately near-empty)
services/      opt-in jobs         lifeos wnba
hosts/         per machine type    studio.zsh macbook.zsh layers.conf
lib/           the apply engine    engine reloads render packages agents
manifest.conf  which file goes where
install.sh     bootstrap a machine, then apply
apply.sh       put config in place; idempotent, safe to re-run
sync.sh        pull/push + apply, every 30 min via launchd
```

Layers **compose**. A machine gets the union of everything listed for its type
in `hosts/layers.conf` — the Mac Studio is `base workstation services`, because
it is both the daily driver and the host of the lifeos server, three WNBA sync
jobs and MLX inference.

## How placement works

`manifest.conf` is the single source of truth. Adding a config file is a new
row, not new code:

```
# layer      mode    source                  dest                     reload
base         link    base/zsh/zshrc          ~/.zshrc                 -
workstation  copy    workstation/aerospace/aerospace.toml  ~/.config/aerospace/aerospace.toml  aerospace
```

| Mode | Behavior | Why |
|---|---|---|
| `link` | symlink | the default — edits on either side stay in sync |
| `copy` | copy, gated on the source hash moving | `aerospace.toml` is tracked *and* rewritten at runtime by `set-main-display.sh`; a symlink would aim those writes at the git repo |
| `seed` | copy only if absent | `displays.env` holds this machine's display IDs |
| `render` | generate from a template | clangd needs the installed GCC's paths |
| `tree` | recursive | `claude/rules`, `claude/skills` |
| `agent` | install + reload a launchd plist | |
| `exec` | executable symlink onto PATH | `newproj`, `yt-transcribe` |

## Install

```bash
git clone https://github.com/ostepan8/dotfiles.git ~/dotfiles
cd ~/dotfiles

echo studio > ~/.dotfiles-host    # or macbook, gpu1, fedora... see hosts/layers.conf
./install.sh
```

`~/.dotfiles-host` holds a machine *type*, not a device id, and lives outside the
repo so it never syncs. A machine with no marker gets `base` only — a safe
default, so a new server node comes up with a working shell and nothing GUI is
ever attempted on a headless box.

Both `install.sh` and `apply.sh` are idempotent and safe to re-run. Existing
files are backed up once to `<name>.backup` before being replaced.

```bash
make dry-run   # show what would change on this machine
make apply     # apply
make test      # secret scan + engine verification
```

## Neovim plugins

`base/nvim/lazy-lock.json` is committed — the lockfile, never the plugin
sources. `:Lazy restore` pins any machine to the same set. Without it, every
machine resolved plugin versions independently on first launch and drifted.

## Machine-specific values

Nothing machine-specific enters this repo — it is public. The pattern is a
tracked `*.template` plus an untracked real file:

- `~/.config/nephos/env` — fleet addresses and endpoints
- `~/.config/aerospace/displays.env` — this machine's display IDs
- `hosts/<type>.zsh` — config shared by all machines of one type

`make check` scans every tracked file for credentials, the personal domain, the
tailnet and RFC1918 addresses before a push, and `make hooks` installs it as a
`pre-push` hook. Every pattern carries a sample it must match, so a rule that
silently stops matching fails the run instead of reporting "clean".

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

### Host-type overrides
`base/zsh/zshrc` is fully shared and identical on every machine. For config that should only apply to *one type* of machine (e.g. a local model path that only exists on the Mac Studio), add it to `hosts/macbook.zsh` or `hosts/studio.zsh` instead of the shared file — both are still committed and synced normally.

Each machine picks which one to load via a one-line marker file that lives outside the repo (so it's never synced):

```bash
echo studio > ~/.dotfiles-host    # on the Mac Studio
echo macbook > ~/.dotfiles-host   # on the MacBook
```

The marker holds a *type*, not a unique device id — a second Mac Studio just gets the same `echo studio > ~/.dotfiles-host` and immediately inherits every studio-only setting, since `hosts/studio.zsh` syncs like any other file in the repo. Add more types (e.g. `hosts/work-laptop.zsh`) the same way — no changes to `zshrc`, `apply.sh`, or `install.sh` needed.

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
| `newproj` / `np` | New project: asks stack / GitHub repo / Claude profile / first task, then makes the dir + git + optional GitHub repo + tmux session + Claude + attached Ghostty window (`newproj <name>`; `-y` to skip the questions, `--help` for flags) |
| `nts` / `tns` | `tmux new-session -s <name>` |
| `ta [name]` | `tmux attach` (tab-completes live session names) |

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

### Multi-monitor setup notes

If using 2+ external monitors with Aerospace + sketchybar, **arrange all externals to the LEFT of the main laptop display** in System Settings → Displays. Externals positioned to the right of main tend to cause flickering / Spotify-type glitches during workspace switches. This is a macOS coordinate-system quirk (negative X coords work more reliably than positive ones for tiling WMs).

### Making Ghostty the default terminal everywhere

`install.sh` sets Ghostty as the default app for `.sh`/`.command`/`.tool`/`.zsh`/`.bash` files automatically (via `duti`). To also make Ghostty the external terminal in editors:

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
