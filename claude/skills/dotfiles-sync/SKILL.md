---
name: dotfiles-sync
description: "Mirror every change to the user's dev/computer setup into the dotfiles repo at ~/dotfiles and commit it. Use whenever editing files under ~/.config/, ~/.zshrc, ~/.skhdrc, ~/.tmux.conf, ~/Library/LaunchAgents/, ~/.claude/settings.json (and similar dotfiles), installing/removing brew packages, running defaults write, changing macOS system prefs, or modifying anything under /Applications/* configuration. Triggers on 'set up X on my computer', 'add a hotkey', 'change my shell config', 'install Y globally', 'update aerospace/skhd/ghostty/tmux/nvim/zsh/sketchybar config', or any dev-environment tweak."
---

# Dotfiles Sync

The user keeps their entire dev environment in `~/dotfiles/` (a git repo, remote `ostepan/dotfiles`). Every dev-environment change made on the live machine MUST also be reflected in `~/dotfiles/` and committed in the same task — never leave the repo behind. The dotfiles repo is the source of truth for setting up a fresh machine; if it drifts, the next install loses the change.

## When this skill applies

Apply this skill (without asking) any time work touches:

- `~/.config/aerospace/`, `~/.config/ghostty/`, `~/.config/sketchybar/`, `~/.config/starship.toml`, `~/.config/nvim/`
- `~/.skhdrc`, `~/.zshrc`, `~/.zsh_plugins.txt`, `~/.tmux.conf`
- `~/Library/LaunchAgents/*.plist` (per-user background services)
- `brew install` / `brew uninstall` of any tool that appears in the README's tools table
- `defaults write …` (macOS system tweaks)
- Setting default app handlers (`duti`), Dock contents (`dockutil`)
- Anything that would need to be re-run on a fresh Mac to reproduce the setup

If the change is **machine-specific and shouldn't propagate** (display IDs, machine-name-based paths, secrets, anything in `displays.env`), DO NOT commit it. Confirm with the user instead.

## Repo layout (where things go)

```
~/dotfiles/
├── aerospace/        toml + helper *.sh
├── ghostty/          ghostty config
├── nvim/             init.lua + lazy specs
├── sketchybar/       sketchybarrc + plugins/*.sh
├── skhd/             skhdrc
├── starship/         starship.toml
├── tmux/             .tmux.conf
├── zsh/
│   ├── zshrc          fully shared — identical on every machine, never branch on hostname here
│   ├── zsh_plugins.txt
│   ├── hosts/         per-machine-*type* overrides — macbook.zsh, studio.zsh (see below)
│   └── scripts/       helper scripts a hosts/*.zsh file shells out to (e.g. mlx-chat-clean.py)
├── mac/
│   ├── setup.sh           installer — copies configs, brew installs, loads LaunchAgents
│   ├── defaults.sh        macOS `defaults write` tweaks
│   └── LaunchAgents/      per-user launchd jobs (*.plist)
├── linux/setup.sh    Linux installer
├── docs/             optional notes
└── README.md         tools table + key bindings
```

Match the existing structure. New tool → new top-level dir + entry in `mac/setup.sh` + entry in `README.md`'s tools table.

## Machine-type-specific config (`zsh/hosts/`)

The user runs this repo on two machines — a MacBook and a Mac Studio — that both report `uname == Darwin`, so OS checks alone can't tell them apart. Some zsh config (e.g. a local-model path, a tool only installed on one machine) must apply to one machine type but not the other, while still being tracked and synced like everything else.

**The pattern:**

- `zsh/zshrc` stays fully shared — same file, same content, every machine. Never add `if [[ "$(hostname)" == ... ]]` branches directly in it.
- Machine-type-only config goes in its own file: `zsh/hosts/macbook.zsh`, `zsh/hosts/studio.zsh`. Both are ordinary tracked files — they sync via git exactly like everything else.
- Each physical machine points at the right one via a **local, untracked** marker file: `~/.dotfiles-host`, containing the machine's *type* (`macbook` or `studio`), not a unique device ID. A second Mac Studio would get the exact same marker value and immediately inherit `zsh/hosts/studio.zsh` — no new file, no code change.
- `zsh/zshrc` reads the marker near the end and sources the matching file if it exists:
  ```sh
  if [ -f "$HOME/.dotfiles-host" ] && [ -f "$HOME/dotfiles/zsh/hosts/$(<"$HOME/.dotfiles-host").zsh" ]; then
      source "$HOME/dotfiles/zsh/hosts/$(<"$HOME/.dotfiles-host").zsh"
  fi
  ```
  This reads straight from the `~/dotfiles` checkout at shell-start time — it is **not** copied into `~/.zshrc` by `apply.sh`/`setup.sh`, so no installer change was needed to wire it up.

**Setting up a new machine (or a new machine of an existing type):**
```bash
echo studio > ~/.dotfiles-host    # or: echo macbook > ~/.dotfiles-host
```
One-time, per physical machine, never touched again. If you add a third machine type (e.g. a work laptop), create `zsh/hosts/work-laptop.zsh` and that's it — `zshrc`, `apply.sh`, and `setup.sh` need no changes.

**A `hosts/*.zsh` file can shell out to a helper script** — put those in `zsh/scripts/` (e.g. `zsh/scripts/mlx-chat-clean.py`, invoked by a macbook-only `ccd-airplane` alias). Same rule applies: the script is a normal tracked file referenced by absolute path under `$HOME/dotfiles/…`, not copied anywhere by the installers.

Extend this same marker-file pattern to any other config that needs to diverge by machine type (not just zsh) if the need comes up — don't invent a second mechanism.

## Deploying to a remote machine over SSH — check before you copy

When this skill's flow is executed on a *second* machine reached via `ssh <host>` (e.g. pushing a change from one Mac and pulling it on the other), **never chain a blind `cp -f <repo file> <live location>` directly after `git pull`** in one command. `git pull --rebase --autostash` can succeed at the rebase while still failing to re-apply the autostash (a real conflict between your incoming change and uncommitted local WIP on that machine) — the command's overall exit code does not reliably reflect that failure. Blindly copying the working-tree file afterward can put raw `<<<<<<<` conflict markers straight into a live config file (e.g. `~/.zshrc`), breaking every new shell on that machine.

Before deploying anything after a remote pull:
1. Check `git status --short` on the remote for unmerged (`UU`) paths.
2. If a file has conflict markers, resolve them explicitly — don't guess; if the conflict involves uncommitted local work you don't have context on, stop and ask the user how to reconcile rather than picking a side.
3. Only copy a file to its live location once you've confirmed it has no conflict markers (e.g. `grep -c '^<<<<<<<' <file>` returns `0`).

## The flow (every time)

1. **Make the live change** under `~/.config/…`, `~/Library/LaunchAgents/…`, etc.
2. **Verify it actually works** before mirroring.
3. **Diff live vs repo** to see what really changed:
   ```bash
   diff ~/.config/<tool>/<file> ~/dotfiles/<tool>/<file>
   ```
4. **Copy the changed files into `~/dotfiles/`**:
   ```bash
   cp ~/.config/<tool>/<file> ~/dotfiles/<tool>/<file>
   ```
5. **If it's a new install/launchd job/macOS default**, also wire it into the relevant installer:
   - New brew package → add `brew install …` line to `mac/setup.sh`
   - New LaunchAgent → already auto-loaded by the `mac/LaunchAgents/*.plist` loop in `mac/setup.sh` (just drop the plist in `mac/LaunchAgents/`)
   - New `defaults write` → add to `mac/defaults.sh`
   - New `duti` / `dockutil` → add to `mac/setup.sh`
   - User-visible feature → update the README tools table or key-binding section
6. **Commit in `~/dotfiles/`** using the conventional-commits format already in the log:
   ```
   feat(<scope>): <subject>
   fix(<scope>): <subject>
   chore(<scope>): <subject>
   ```
   Scope = the top-level dir touched (`aerospace`, `skhd`, `zsh`, `mac`, `nvim`, `tmux`, `ghostty`, `sketchybar`). Multi-line body explains the *why* (the bug, the workflow, the constraint) — not the *what*.
7. **Do NOT push** unless the user asks. Local commits are the contract; pushing is theirs to trigger.

## Known drift to ignore

These files are intentionally regenerated by helper scripts on the live machine and will always differ from the repo — do **not** sync these diffs:

| File | Why it drifts |
|---|---|
| `~/.config/aerospace/aerospace.toml` `outer.top` line | Rewritten by `set-main-display.sh` on every Cmd+Opt+[ / ] / \\ swap to track whichever monitor is currently main |
| `~/.config/aerospace/displays.env` | Persistent macOS display IDs — only valid on this machine |
| Anything under `~/.zshrc.backup` | One-time backup, never propagated |

When you see a diff that's purely one of these, leave it alone.

## Never-commit guardrails

- No secrets — API keys, tokens, passwords, OAuth credentials, `.env` contents.
- No machine-specific identifiers — display IDs, hostnames, hardware UUIDs, account-specific paths.
- No personal data — email content, browser history, anything from `~/Library/Application Support/`.
- If unsure whether a change is portable across machines, ask.

## Commit message style (from existing log)

```
feat(aerospace): per-main-display top gap, rewritten on every swap
fix(aerospace): restart sketchybar after main-display swap
feat(aerospace): bind alt-shift-\\ to send focused window to laptop
refactor(aerospace): unify monitor bindings on bracket-trio [ ] \
chore(ghostty): clean up ineffective non-global Opt+` binding
feat(zsh): alias e=exit
```

Lowercase subject, no trailing period, scope in parens. Keep subject under ~70 chars; put detail in the body.

## Quick reference — full sync of all known configs

If something seems out of sync and you want to confirm:

```bash
for f in aerospace/aerospace.toml ghostty/config skhd/skhdrc tmux/.tmux.conf \
         starship/starship.toml zsh/zshrc zsh/zsh_plugins.txt \
         sketchybar/sketchybarrc nvim/init.lua; do
  live=~/.config/$(echo "$f" | sed 's|.*/||')
  case "$f" in
    skhd/skhdrc)         live=~/.skhdrc ;;
    tmux/.tmux.conf)     live=~/.tmux.conf ;;
    zsh/zshrc)           live=~/.zshrc ;;
    zsh/zsh_plugins.txt) live=~/.zsh_plugins.txt ;;
    nvim/init.lua)       live=~/.config/nvim/init.lua ;;
    sketchybar/*)        live=~/.config/sketchybar/sketchybarrc ;;
    aerospace/*)         live=~/.config/aerospace/aerospace.toml ;;
    ghostty/*)           live=~/.config/ghostty/config ;;
    starship/*)          live=~/.config/starship.toml ;;
  esac
  diff -q "$live" ~/dotfiles/"$f" 2>/dev/null
done
```

Anything that prints means the live config has drifted from the repo.

## TL;DR

**Live change → mirror to `~/dotfiles` → wire into `mac/setup.sh` if needed → commit. Same task, every time. Don't push.**
