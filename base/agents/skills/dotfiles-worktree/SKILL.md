---
name: dotfiles-worktree
description: The way to make ANY change to ~/dotfiles — each change in its own git worktree, landed straight onto origin/main with `dfw`, conflicts resolved, worktree deleted. Lets many sessions change dotfiles at once without stepping on each other. Use whenever a task edits ~/dotfiles or any live config that is symlinked into it (~/.zshrc, ~/.config/*, ~/.claude-personal/*, skills, hooks, manifest.conf), whenever Owen asks for a dotfiles/config/skill/hook change, or when ~/dotfiles has leftover worktrees, a stuck rebase, or a dotfiles merge conflict. Pairs with dotfiles-sync, which says WHERE things go; this says HOW the change lands.
---

# dotfiles-worktree

Never edit files in `~/dotfiles` directly, and never edit a live config that is a
symlink into it. Most live configs (`~/.zshrc`, `~/.config/...`, `~/.claude-personal/...`)
are symlinks into that one checkout. So every session editing "its" file is editing the
same working tree. `sync.sh` also autostashes over that tree every 30 min. That is how
half-merged lockfiles and stray stashes happen. Every change gets its own worktree.

## The loop

```bash
WT=$(dfw start <slug>)        # e.g. dfw start zsh-git-aliases → ~/.cache/dotfiles-worktrees/<slug>
# ...edit files under $WT (same layout as ~/dotfiles), verify them...
dfw land <slug> -m "feat(zsh): add git aliases"
```

`dfw land`:

1. Commits anything uncommitted, using `-m`.
2. Rebases onto the latest `origin/main`. Structured JSON configs merge automatically (see
   below).
3. Pushes to `origin/main`. If another session landed first, it rebases and retries.
   The pre-push `make check` secret scan runs here.
4. Fast-forwards `~/dotfiles` and runs `apply.sh`, so the change is live on this
   machine. Other machines pick it up on their next `sync.sh` tick, or right away with
   `make fleet`.
5. Deletes the worktree and its `df/<slug>` branch.

Landing is the default: Owen asked for dotfiles changes to go all the way to main
without asking. Several changes at once is fine. Give each one its own slug, which
can be several worktrees in one session or one per session.

Pick a slug that names the change (`aerospace-ws-pin`, `claude-kill-guard`).
`dfw start` is idempotent. Re-running it with the same slug returns the existing
worktree, so an interrupted session can resume.

## Verify before landing

The worktree is not live. To check it:
- shell: `zsh -n $WT/base/zsh/zshrc`
- JSON: `python3 -m json.tool $WT/base/claude/settings.json`
- repo checks: `make -C $WT check`
- apply engine: `make -C $WT verify`

For a behaviour you can only see live (a hotkey, a bar item), land it, look at it, and
fix forward with another `dfw start`.

## Conflicts (exit 3)

- `settings.json`, `codex/hooks.json` and `nvim/lazy-lock.json` merge by structure
  through the `dfjson` driver in `.gitattributes`. Keys, hooks and permissions added on
  both sides are all kept.
  - `lazy-lock` pin clashes take the incoming side.
  - When the same setting was changed to two different values, you get normal conflict
    markers.
- Anything else: `dfw land` stops, lists the conflicted files and leaves the rebase open
  in the worktree. For each file:
  1. `git -C $WT diff <file>`. Read both sides and `git log origin/main -3 -- <file>` for
     what the other change wanted.
  2. Edit to keep **both** intents. Never pick a side wholesale. Dropping the other
     session's change is the one unacceptable outcome.
  3. `grep -c '^<<<<<<<\|^>>>>>>>' <file>` must print 0, and the file must still parse
     (`zsh -n`, `json.tool`, …).
  4. `git -C $WT add <file>`.
  5. Re-run `dfw land <slug>`. It continues the rebase and carries on.
- Only if two changes truly contradict each other (both set the same key to different
  values on purpose) do you ask Owen which one wins.

## Other exits and states

| Output | Meaning / action |
|---|---|
| exit 4, `make check` output | The secret scan or exec-bit check refused the push. Fix it in `$WT` (e.g. move a private domain/IP into `~/.config/...` and read it at runtime), commit, re-run `land`. |
| `landed, but ~/dotfiles could not fast-forward` | Someone left uncommitted edits in the main checkout on a file you changed. The change IS on main. Move those edits into their own worktree (`dfw start`, copy them over, `git -C ~/dotfiles checkout -- <file>` only after confirming they are copied), then `git -C ~/dotfiles merge --ff-only origin/main && make -C ~/dotfiles apply`. |
| `locked by another sync` | `sync.sh` was running. The change is on main, and the next sync tick applies it. |
| exit 2 `uncommitted changes` | Commit in `$WT` or pass `-m`. |

## Housekeeping

- `dfw ls` lists open worktrees with `clean` / `dirty` / `CONFLICT` and commits ahead.
  Check it at the start of dotfiles work. A worktree you did not create belongs to
  another session: leave it alone.
- `dfw gc` removes worktrees whose work is already on main and that have nothing
  uncommitted.
- `dfw abort <slug>` discards a worktree and its unlanded commits. Only when Owen says to
  drop that change.

## Tests

`make dfw-test` runs the JSON-merge unit tests and an end-to-end run of parallel
lands, JSON overlap, text conflict and resume against a throwaway origin. Run it after
editing `scripts/dfw` or `scripts/json-merge.py`. Those two are themselves dotfiles, so
change them through a worktree too.
