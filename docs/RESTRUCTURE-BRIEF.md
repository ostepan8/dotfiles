# Dotfiles restructure — session brief

Written 2026-08-16. The owner's dotfiles have become confusing and need a plan
before anything moves. Nothing here is approved yet — propose, get agreement, then
execute on a branch.

**Repo: `~/dotfiles`, public on GitHub (`git@github.com:ostepan8/dotfiles.git`).**
139 tracked files, 2.7MB.

---

## What is actually there now

```
80 files  claude/        58% of the repo
22 files  mac GUI        aerospace(11), sketchybar(10), skhd(1)
19 files  mac/           apply.sh defaults.sh LaunchAgents lib NvimOpener setup.sh sync.sh
 5 files  zsh/
 2 files  linux/         setup.sh, setup-desktop.sh
 1 file   each: nvim, git, tmux, starship, ghostty, clangd, Brewfile, docs
```

Install is two hand-rolled scripts — `mac/setup.sh` (Homebrew + Brewfile, ~10 steps)
and `linux/setup.sh` (detects apt/dnf/pacman, ~14 steps). No stow, no symlink
manifest, no idempotency guarantees. There is no `lazy-lock.json` committed, so nvim
plugin versions resolve independently on every machine and drift.

## The diagnosis

**The split is on the wrong axis.** The repo divides by OS (`mac/` vs `linux/`), but
OS is not what varies across these machines — role is.

| Machine | OS | Role | Actually needs |
|---|---|---|---|
| Mac Studio | darwin/arm64 | workstation | everything |
| MacBook Pro | darwin/arm64 | workstation | everything |
| fedora | linux/amd64 | **server** | shell, git, tmux |
| gpu1 | linux/amd64 | **server** | shell, git, tmux |
| gpu2 | linux/amd64 | **server** | shell, git, tmux |
| onephus (Pi) | linux/arm64 | **server** | shell, git, tmux |

Two workstations, four headless servers. The two Macs share ~95% of their config and
are split across `mac/` plus six top-level GUI dirs. Meanwhile `linux/setup.sh`
installs neovim and there is a `setup-desktop.sh`, for machines whose lids are
literally shut in a corner.

## Proposed structure (NOT yet approved)

```
base/          every machine, no exceptions
  zsh/ git/ tmux/ starship/ claude/
workstation/   machines with a human in front of them
  nvim/ (+ lazy-lock.json) aerospace/ sketchybar/ skhd/ ghostty/ Brewfile
server/        headless
  minimal editor config, no GUI anything
install.sh     reads ~/.dotrole, symlinks base + one profile
```

Role is read from an explicit `~/.dotrole` file written at setup time, defaulting to
`server` when there is no display. Explicit beats inference — a laptop guessing wrong
is worse than being asked once.

`claude/` belongs in `base/`. It is the largest and most valuable thing in the repo,
and the nephos skill is supposed to work identically everywhere.

## Answers to the three questions the owner asked

**"Do we include plugins?"** Include the *lockfile*, never the plugin sources.
`lazy-lock.json` is one file that makes nvim reproducible; `:Lazy restore` pins any
machine to the same set. Currently neither is committed, which is why machines drift.

**"Different machines, same architecture?"** The layering above, plus a hard rule:
anything machine-specific never enters the repo. The pattern already works elsewhere
— `~/.config/nephos/env` holds addresses and is untracked. Extend it: the shared
`.zshrc` sources `~/.config/local/zshrc` last if it exists. Hostnames, work proxies,
per-machine PATH live there.

**"What does the laptop get?"**

| | Laptop | Reasoning |
|---|---|---|
| Dotfiles (workstation profile) | yes | it is his machine |
| SSH keys to the fleet | yes | already has them |
| Its own vault | yes | macOS Keychain-backed, so it is a *separate* vault; secrets do not sync, which is correct |
| Cloudflare API token | no | that token edits DNS; the laptop never needs it |
| Fleet sudo passwords | only if he wants to admin from it | |

Real constraint: the MacBook is on the `boston-ph` work tailnet and **cannot reach
the nephos fleet at all**. Recommendation was that the laptop stays a *client* of
`llm.<personal-domain>` (public, key-authenticated) rather than becoming a fleet
member. (Domain redacted — this repo is public; the real value lives in
`~/.config/nephos/env`.)

## Risk to design for

The repo is public and `claude/` is 58% of it — the directory most likely to
accumulate a hostname, path, or key over time. It was verified clean once by hand.
Worth a `make check` that greps for the personal domain, the tailnet, usernames,
and `sk-` before every push. (The literal domain and tailnet values that appeared
here have been redacted for the same reason — they now live only in
`scripts/check-secrets.sh` as anchored patterns.)

## How to work

- Propose the structure and get agreement before moving files.
- Do it on a branch. `git mv` so history follows.
- The install must be idempotent and safe to re-run on a machine that is already
  set up — that is the whole point of having one.
- Test on a server node before touching either Mac: `ssh gpu1` is expendable,
  the Mac Studio is the owner's working machine.
