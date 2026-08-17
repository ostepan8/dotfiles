# Dotfiles restructure — implementation plan

Written 2026-08-16, in response to `RESTRUCTURE-BRIEF.md`. This plan supersedes the
brief's proposed structure where the two differ; differences and reasoning are noted
inline.

Branch: `wt/role-layers` (matches the repo's existing `wt/*` convention).

---

## Assumptions taken

The brief left three questions open. Answers used here, all cheap to reverse before
Phase 3:

1. **Layers compose, they don't exclude.** A machine selects `base + workstation +
   server`, not one profile. The Mac Studio is genuinely both — it runs the lifeos
   server, three WNBA sync jobs and MLX inference while also being the daily
   workstation.
2. **`~/.dotfiles-host` stays the single marker.** No `~/.dotrole`. The host→layers
   mapping becomes tracked data in `hosts/layers.conf`. One file to set per machine,
   one place to review the mapping.
3. **`services/` stays in this repo as an opt-in layer.** lifeos and WNBA are
   deployment, not configuration, but splitting repos now adds a second sync
   mechanism to a fleet that is already under-synced. Isolating them in their own
   layer gets the clarity without the second repo; extracting later is a `git
   filter-repo` away.

---

## Ordering principle

**Build the engine before moving any file.** Phases 1–2 introduce a manifest and an
apply engine that reproduce today's behavior byte-for-byte from today's paths.
Phase 3 then moves files and changes *only manifest paths*. This makes the migration
provably behavior-neutral: if something breaks after Phase 3, it was the move, not
the engine, and the two never have to be debugged together.

The brief put restructuring first. Restructuring first means the reorganized tree and
a rewritten installer land in the same change, with no way to isolate a regression.

---

## Phase 0 — Safety net

No file moves. Landable on `main` independently of everything else.

1. Create `.gitignore` (currently **0 bytes** — the gap that lets the next leak in):
   ```
   .DS_Store
   *.swp
   *.log
   .dotfiles-apply/
   claude/**/settings.local.json
   claude/**/sessions/
   claude/**/projects/
   **/env
   !**/env.template
   ```
2. Add `Makefile` with `make check` — the pre-push scanner. **Anchored** patterns, so
   it does not fire on the four innocent `tailscale` lines in the Brewfile:
   - `onephos\.com`, `tail[0-9a-f]{6,}\.ts\.net`, `\bsk-(proj|ant|live)-[A-Za-z0-9]{16,}`
   - `AKIA[0-9A-Z]{16}`, `ghp_[A-Za-z0-9]{20,}`, `BEGIN [A-Z ]*PRIVATE KEY`
   - RFC1918 addresses (`10\.`, `192\.168\.`, `172\.(1[6-9]|2[0-9]|3[01])\.`)
   Exit non-zero on any hit; allowlist file for known-good placeholders
   (`claude/rules/typescript/security.md`'s `sk-proj-xxxxx` doc example,
   `nephos/env.template`'s `127.0.0.1`).
3. **Fix the one real leak.** `claude/skills/yeelight/references/bulbs.txt` publishes
   a 9-device inventory of the home LAN. Move those addresses to
   `~/.config/yeelight/bulbs.txt` (untracked), ship `bulbs.txt.template`, and update
   `SKILL.md` to read the local file first — mirroring the `nephos/env` pattern that
   already works. `git rm` the tracked copy.
4. Decide on history: the addresses are RFC1918 and already public in git history.
   Rewriting history on a public repo breaks every clone. **Recommendation: don't
   rewrite.** Remove going forward; the exposure is a home LAN topology, not a
   credential, and it is not reachable from outside the network.

*Gate:* `make check` passes on a clean tree.

---

## Phase 1 — Manifest + apply engine (no moves)

### Manifest format

Whitespace-separated columns, `#` comments. **Not TOML** — the engine is bash, and a
TOML parser in bash is a liability. This format is `read`-able natively, greppable,
and diffs cleanly.

```
# layer        mode    source                        dest                                    reload
base           link    zsh/zshrc                     ~/.zshrc                                -
base           link    git/gitconfig                 ~/.gitconfig                            -
base           link    tmux/.tmux.conf               ~/.tmux.conf                            tmux
workstation    link    skhd/skhdrc                   ~/.skhdrc                               skhd
workstation    seed    aerospace/aerospace.toml      ~/.config/aerospace/aerospace.toml      aerospace
workstation    seed    aerospace/displays.env        ~/.config/aerospace/displays.env        -
workstation    render  clangd/config.yaml            ~/Library/Preferences/clangd/config.yaml -
base           tree    claude/skills                 ~/.claude-personal/skills               -
```

### Four modes — the brief's "symlink everything" is unsafe for two of these

| Mode | Behavior | Why it exists |
|---|---|---|
| `link` | symlink source → dest | the default; edits in either place stay in sync |
| `seed` | copy **only if dest absent** | `aerospace.toml` is rewritten at runtime by `set-main-display.sh`; symlinking it means AeroSpace writes into the git repo on every display change — permanently dirty tree, and `sync.sh`'s rebase/push loop would fight the two Macs' monitor layouts against each other every 30 min. `displays.env` is per-machine. |
| `render` | substitute placeholders, then write | `clangd/config.yaml` has `__GCXX__`/`__GTRIPLE__` sed'd with the installed GCC paths |
| `tree` | recursive sync of a directory | `claude/rules`, `claude/skills` |

### Engine (`lib/apply-engine.sh`)

Ports `mac/apply.sh` rather than rewriting it. Its content-hash change detection and
timeout-guarded reloads are hard-won and stay as-is:

- `changed <tag> <files...>` — SHA-based, state in `~/.config/.dotfiles-apply`
- reload functions in `lib/reloads.sh` (`reload_skhd`, `reload_sketchybar`,
  `reload_tmux`, `reload_aerospace`), each fired once per apply when its `reload` tag's
  sources moved
- preserve the existing `command -v` before `changed` ordering — `changed` records the
  new hash as a side effect, so testing it for an uninstalled tool would mark the
  change applied and permanently suppress the reload
- preserve the `dotfiles-sync.plist` self-unload guard

### Claude profile fan-out

Written as explicit repeated manifest lines, one per profile — 12 lines, verbose but
dumb and greppable. No logic in the manifest.

*Gate:* engine exists, manifest describes current layout, nothing has moved.

---

## Phase 2 — Prove behavior-neutrality

1. Snapshot every destination the current scripts touch:
   `find` the ~40 dest paths, record `shasum -a 256` + symlink target + mode.
2. Run the new `apply.sh` (manifest-driven, old paths).
3. Re-snapshot. **Diff must be empty** except intended `link` conversions.
4. Run it twice more — confirm idempotence and that no reload fires on an unchanged
   tick (the bug `apply.sh` was already patched for: bar flash / retile on every sync).

*Gate:* empty diff, second run silent. Do not proceed otherwise.

---

## Phase 3 — Move files (`git mv` only)

Target layout:

```
base/           zsh/ git/ tmux/ starship/ claude/ nvim/
workstation/    aerospace/ sketchybar/ skhd/ ghostty/ clangd/ Brewfile macos/
server/         nvim/ overrides only
services/       lifeos/ wnba/
hosts/          studio.zsh macbook.zsh layers.conf
lib/            apply-engine.sh reloads.sh with-timeout.sh packages/
docs/
manifest.conf  install.sh  apply.sh  sync.sh  Makefile
```

Move table:

| From | To | Note |
|---|---|---|
| `zsh/{zshrc,zsh_plugins.txt}` | `base/zsh/` | |
| `zsh/hosts/*.zsh` | `hosts/` | selected by `~/.dotfiles-host` |
| `zsh/scripts/mlx-chat-clean.py` | `workstation/zsh/scripts/` | MLX is Apple Silicon only |
| `git/`, `tmux/`, `starship/` | `base/` | |
| `claude/` (80 files) | `base/claude/` | |
| `nvim/init.lua` | `base/nvim/` | see nvim note below |
| `aerospace/` (11) | `workstation/aerospace/` | |
| `sketchybar/` (10), `skhd/`, `ghostty/`, `clangd/`, `Brewfile` | `workstation/` | |
| `mac/defaults.sh`, `mac/NvimOpener/` | `workstation/macos/` | bootstrap-only, not in apply |
| `mac/LaunchAgents/com.ostepan.{aerospace-cleanup,display-watcher}.plist` | `workstation/aerospace/agents/` | WM infrastructure |
| `mac/LaunchAgents/com.ostepan.lifeos.*.plist` (3) | `services/lifeos/` | |
| `mac/LaunchAgents/com.ostepan.wnba-*.plist` (3) + `mac/wnba-analytics-engine/` (3) | `services/wnba/` | |
| `mac/lib/with-timeout.sh` | `lib/` | |
| `mac/{apply,sync}.sh` | `apply.sh`, `sync.sh` (top level) | **see Phase 4 shims** |
| `mac/setup.sh` + `linux/setup.sh` | `install.sh` + `lib/packages/{brew,linux}.sh` | |
| `linux/setup-desktop.sh` | **delete** | zero Linux desktops in the fleet; `git log` retains it |

Then update `manifest.conf` source paths — and nothing else. Re-run the Phase 2
snapshot diff; still empty.

**Two deviations from the brief:**

- **nvim goes in `base`, not `workstation`.** `init.lua` is 529 lines / 6 plugins. You
  already install neovim on every Linux box and will SSH in to edit. What's expensive
  headless is the *bootstrap* (treesitter compiles, LSP servers), not the config. Ship
  one `init.lua`; gate the heavy plugin set on `vim.env.DOTFILES_LAYER`. One editor
  config beats a "minimal" second one that rots. `server/nvim/` holds overrides only.
- **`services/` is its own layer**, not part of `workstation` — so "which machines run
  my jobs" stays a separate question from "which machines have my shell."

---

## Phase 4 — The launchd trap (highest-risk step)

Four plists hardcode `$HOME/dotfiles/mac/...`, including the sync agent's own
`exec "$HOME/dotfiles/mac/sync.sh"`. The installed plist in `~/Library/LaunchAgents`
is a *copy*, and `apply.sh` only reinstalls one when it differs.

So merging Phase 3 to `main` naively produces a **self-inflicted bootstrap trap**:

1. Studio's sync agent fires with the old plist → `exec $HOME/dotfiles/mac/sync.sh`
2. that file no longer exists → agent exits non-zero, never runs `apply.sh`
3. the fix is in the repo but nothing is left running to deliver it
4. both Macs need manual repair at the keyboard

Mitigation, in this order:

1. Keep executable shims at `mac/sync.sh` and `mac/apply.sh` that `exec` the new
   top-level scripts. Land these **in the same commit** as the move.
2. Let one full sync cycle (≥30 min) run on both Macs. Confirm via
   `~/Library/Logs/dotfiles-sync.log` that the new plists installed and loaded.
3. Only then remove the shims, in a separate follow-up commit.

Also in this phase — **the live bug the brief did not catch:**

`mac/setup.sh:144` installs Claude config to `~/.claude-{personal,school,work}`;
`mac/apply.sh:130` installs it to `~/.claude`; `zsh/zshrc:102` sets
`CLAUDE_CONFIG_DIR="$HOME/.claude-personal"`. The 30-minute sync has been writing
Claude config to a directory Claude does not read, and `apply.sh` never copied
`skills/` at all. `linux/setup.sh` has **zero** Claude references, so the four servers
have never received any of it — including the nephos skill that is supposed to work
identically everywhere.

The manifest fixes this by construction: one source of truth, `claude/` in `base`,
applied by the same engine on every machine.

---

## Phase 5 — Reproducibility

- Commit `base/nvim/lazy-lock.json` (generated by `:Lazy sync` on the Studio). The
  brief's answer here is right without qualification — lockfile yes, plugin sources
  never.
- Document `:Lazy restore` as the pin-to-fleet-state command in the README.

---

## Phase 6 — Rollout

Strict order, with a gate at each step:

1. **`gpu1`** — expendable. Fresh `install.sh`, confirm base layer lands, confirm
   Claude config now present, confirm no GUI packages install.
2. **`fedora` / `gpu2` / `onephus`** — confirm the arm64 Pi path works too.
3. **MacBook** — `apply.sh` on the existing setup. Nothing should change except link
   conversions.
4. **Mac Studio last** — the working machine. Before merging, either stop the sync
   agent (`launchctl unload ~/Library/LaunchAgents/com.ostepan.dotfiles-sync.plist`)
   or be at the keyboard when it fires. Re-enable after confirming a clean apply.

Merge to `main` only after step 3 passes, since both Macs auto-pull `main` within 30
minutes and `sync.sh` hardcodes `BRANCH="main"`.

---

## Phase 7 — Cleanup

- Rewrite `README.md` around layers (currently documents the `mac/` + `linux/` split).
- Delete the shims from Phase 4.
- `make check` wired into a `pre-push` hook.

---

## Rollback

Cheap at every phase:

- Phases 0–2 add files only; `git checkout main` reverts.
- Phase 3+ — `git checkout main && bash mac/apply.sh` restores prior state, because
  every machine keeps `.backup` copies (`~/.zshrc.backup`, `~/.gitconfig.backup`) and
  the shims keep the old entry points alive.
- The one genuinely manual recovery is the launchd trap; Phase 4's shims exist
  specifically so it cannot happen.

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| launchd plists reference moved paths; sync agent kills itself | **critical** | Phase 4 shims + one confirmed sync cycle before removal |
| Symlinking `aerospace.toml` puts runtime writes in the repo | high | `seed` mode; never `link` |
| Merge to `main` auto-deploys to both Macs within 30 min | high | Merge only after MacBook passes; unload sync agent on Studio |
| `changed` hash side effect suppresses a future reload | medium | Preserve `command -v` before `changed` ordering |
| Claude profile fan-out silently drops a profile | medium | Explicit manifest lines, one per profile; `make check` asserts all 12 |
| `render` mode on a machine without Homebrew GCC | low | Existing guard already skips when the dir is absent |

---

## What this plan does not do

- No history rewrite (Phase 0.4).
- No stow. The three modes above are not expressible in stow, and `aerospace.toml`
  alone rules it out.
- No systemd sync timer for the Linux nodes yet — they stay pull-on-demand. Worth a
  follow-up once the layer split is proven.
