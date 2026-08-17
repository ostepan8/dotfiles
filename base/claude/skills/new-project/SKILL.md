---
name: new-project
description: "Spin up a new project the way this machine organizes them — pick the right folder, create the directory + git repo, optionally create and push a GitHub repo, seed a stack .gitignore, start a named tmux session, launch Claude Code inside it, and open a new Ghostty window attached to that session. Use whenever the user says 'new project', 'start a project', 'set up a project for X', 'make me a repo for X', 'spin up X', or asks to get a fresh idea into a working environment. Also use when an existing folder needs its tmux + Claude session created."
---

# New Project

One command turns an idea into a working environment:

```
<root>/<slug>/               ← directory + git repo + README + stack .gitignore
        ↓                      optional GitHub repo, created and pushed
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

## Interactive vs. how you run it

At a terminal, `newproj <name>` asks four short questions — stack, GitHub repo
(then visibility), Claude profile, opening task — with Enter accepting the
default on all but visibility.

**You will never see those questions.** Prompting requires a TTY on stdin and
stdout, which the Bash tool doesn't have, so every unanswered question silently
takes its default: no stack, **no GitHub repo**, personal Claude, no opening
task. That's the trap to avoid — running `newproj foo` on the user's behalf
quietly skips the GitHub repo they'd have said yes to at a terminal.

So when you run it, either:

- **Decide in chat and pass flags** — `--stack`, `--github private|public|none`,
  `--cmd`, `--prompt`. Ask the user the questions the script would have asked,
  in conversation, whenever the answers aren't already obvious from what they
  said. "Make me a repo for X" is a yes to `--github`; ask which visibility.
- **Or hand the terminal back** — tell the user to run `newproj <name>`
  themselves if they'd rather answer the prompts directly. That is genuinely
  faster for them than a round of chat questions.

Add `-y` to state explicitly that defaults are intended.

## Choosing where it goes

The one judgment call — and the one place to not assume.

**The project root differs per machine.** These dotfiles run on more than one
computer and they do *not* share a folder layout, so never hardcode
`~/Desktop/Projects` (that's one machine's habit) in a path you hand the user or
write into a file. Ask the script:

```bash
newproj --show-root          # the root this machine resolves to
newproj --dry-run <name>     # the exact directory it would create
```

Resolution order: `--root`/`--path` → `$NEWPROJ_ROOT` (set in
`zsh/hosts/<type>.zsh`) → `~/.config/newproj/root` (machine-local, untracked) →
first existing of `~/Desktop/Projects ~/Projects ~/projects ~/code ~/dev ~/src
~/Developer` → `~/Projects`. If a machine wants a different home, set it once in
`~/.config/newproj/root` rather than passing `--root` every time.

With the root resolved, sort the project into it:

| Kind of thing | Location |
|---|---|
| Real project — anything with a git history, code, or a future | `<root>/<slug>` (the default) |
| Scratch / one-off experiment | `<root>/misc/<slug>` |
| Throwaway single-page web demo | a siblings-of-root dir if the machine has one (this Mac: `~/Desktop/Web-Experiments/`) via `--path`, usually `--no-git` |

Rules of thumb:

- Default to `<root>/<slug>` unless the user names a location.
- Confirm the sibling directory exists before using `--path` for one — those are
  machine-specific too. `ls` the parent first.
- Derive a short kebab-case slug from what the user described (`"a bot that
  tracks WNBA lines"` → `wnba-line-bot`). The slug is also the tmux session
  name, so keep it typeable — that name is what `ta <slug>` completes on later.
- Check first whether the project already exists: `ls "$(newproj --show-root)"`. If it
  does, run `newproj` on it anyway — it reuses the directory and the session
  instead of clobbering either, so it doubles as "give this folder a session".
- Ambiguous between two homes and the user is present? Ask. Otherwise pick the
  default and say which you picked.

## Options

```bash
newproj <name>                        # <resolved root>/<name>, git, ccd
newproj --show-root                   # where this machine puts projects
newproj misc/scratch                  # slashes nest under the root; session = "scratch"
newproj <name> --root ~/code          # different root, just this once
newproj <name> --path /exact/dir
newproj <name> --github private       # create + push a GitHub repo (private|public|none)
newproj <name> --stack python         # node|python|rust|go|roblox|web|none → .gitignore
newproj <name> --cmd ccdw             # work profile (ccd personal, ccds school, none = no Claude)
newproj <name> --prompt "scaffold a Next.js app with Tailwind"
newproj <name> --session api          # tmux session name != folder name
newproj <name> -y                     # ask nothing, take defaults
newproj <name> --no-git --no-readme   # skip scaffolding
newproj <name> --no-window            # create it all, attach later with: ta <name>
newproj <name> --dry-run              # print the plan, touch nothing
```

`--prompt` is worth reaching for: it hands the new Claude session its first
instruction, so the window opens already working instead of waiting at an
empty prompt. When `--stack` is also set, the stack is prepended as context
("This is a python project. …") so the new session doesn't have to infer it
from an empty directory.

**`--stack` seeds a `.gitignore` and nothing else** — no `npm init`, `uv init`,
or cargo scaffold. The right tool per stack is a real choice (npm vs bun, uv vs
poetry) and guessing wrong leaves a mess to undo; the Claude session that opens
is better placed to do it properly. If the user wants the stack actually
scaffolded, that belongs in `--prompt`.

**`--github`** runs `gh repo create <slug> --<visibility> --source . --remote
origin --push`, committing what's there first as `chore: initial commit`. It is
skipped with a warning — never a hard failure — if `gh` is missing, logged out,
the name is taken, or the network is down. An existing `origin` is left alone.

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
- **The folder-trust prompt is auto-confirmed**, but only for a directory this
  run just created. A pre-existing folder is left for the user to vet.
- **Nothing is destructive.** Existing `README.md`, `.gitignore`, git repo, and
  `origin` are all left as they are; only missing pieces get filled in.

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
