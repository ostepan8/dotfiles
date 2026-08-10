---
name: new-project
description: "Spin up a new project the way this machine organizes them — pick the right folder under ~/Desktop/Projects, create the directory + git repo, start a named tmux session, launch Claude Code inside it, and open a new Ghostty window attached to that session. Use whenever the user says 'new project', 'start a project', 'set up a project for X', 'make me a repo for X', 'spin up X', or asks to get a fresh idea into a working environment. Also use when an existing folder needs its tmux + Claude session created."
---

# New Project

One command turns an idea into a working environment:

```
~/Desktop/Projects/<slug>/   ← directory + git repo + README
        ↓
tmux session "<slug>"        ← window 1 "claude" (Claude Code running)
        ↓                      window 2 "shell" (plain shell, same dir)
new Ghostty window           ← already attached to that session
```

The whole thing is one script: `newproj` (on PATH, symlinked from
`scripts/newproj.sh` in this skill).

## The fast path

```bash
newproj <project-name>
```

That is usually the entire job. Run it and report where things landed — do not
hand-roll the mkdir / tmux / attach steps.

## Choosing where it goes

The one judgment call. Defaults, in order of preference:

| Kind of thing | Location |
|---|---|
| Real project — anything with a git history, code, or a future | `~/Desktop/Projects/<slug>` (the default) |
| Throwaway single-page web demo | `~/Desktop/Web-Experiments/` (`--path`, usually `--no-git`) |
| Scratch / one-off experiment | `~/Desktop/Projects/misc/<slug>` |

Rules of thumb:

- Default to `~/Desktop/Projects/<slug>` unless the user names a location.
- Derive a short kebab-case slug from what the user described (`"a bot that
  tracks WNBA lines"` → `wnba-line-bot`). The slug is also the tmux session
  name, so keep it typeable — that name is what `ta <slug>` completes on later.
- Check first whether the project already exists: `ls ~/Desktop/Projects`. If it
  does, run `newproj` on it anyway — it reuses the directory and the session
  instead of clobbering either, so it doubles as "give this folder a session".
- Ambiguous between two homes and the user is present? Ask. Otherwise pick the
  default and say which you picked.

## Options

```bash
newproj <name>                        # default: ~/Desktop/Projects/<name>, git, ccd
newproj misc/scratch                  # slashes nest under the root; session = "scratch"
newproj <name> --root ~/code          # different root
newproj <name> --path ~/Desktop/Web-Experiments/thing
newproj <name> --cmd ccdw             # work profile (ccd personal, ccds school, none = no Claude)
newproj <name> --prompt "scaffold a Next.js app with Tailwind"
newproj <name> --session api          # tmux session name != folder name
newproj <name> --no-git --no-readme   # skip scaffolding
newproj <name> --no-window            # create it all, attach later with: ta <name>
newproj <name> --dry-run              # print the plan, touch nothing
```

`--prompt` is worth reaching for: it hands the new Claude session its first
instruction, so the window opens already working instead of waiting at an
empty prompt.

## Behavior worth knowing

- **Idempotent.** Existing directory → reused. Existing tmux session → reused,
  and nothing is typed into it (no stray `ccd` in a session you're using).
- **Already attached?** If a terminal is attached to that session, no second
  window opens. If run from inside tmux at a real terminal, it switches the
  current client instead of nesting.
- **The Ghostty window** comes from `open -na Ghostty --args -e tmux attach -t
  <session>`. It exits cleanly when the session ends, so no orphan processes.
  AppleScript window-opening is *not* usable here — it needs assistive access
  that `osascript` doesn't have from a script.
- **Claude is started by typing into the pane**, after waiting for the shell to
  finish booting, because `ccd` is a zsh function from `~/.zshrc`, not a binary.
  That also means the shell survives when Claude exits.

## After it runs

Report the directory, the session name, and that the window is open. Then, if
the user described what they're building, keep going in *this* session only if
they asked you to — otherwise the new Claude window is where that work belongs.

## Related

- `ta <name>` — attach to the session later (tab-completes live session names)
- `tmux ls` — see every project session
- Changes to this skill or its script must be mirrored into `~/dotfiles`
  (see the `dotfiles-sync` skill); the script is symlinked onto PATH by
  `mac/setup.sh`.
