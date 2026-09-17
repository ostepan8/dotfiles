---
name: tmux
description: "Look at, drive and manage this machine's tmux sessions, windows and panes through the `tmuxctl` command. Use whenever a task involves tmux at all — listing or finding sessions, seeing what is running somewhere, reading a pane's output, running a command inside a specific pane or project directory, starting or killing sessions, or checking on the other Claude Code sessions that are open (which are working, which are waiting for input, which are just restored shells). Triggers on 'tmux', 'my sessions', 'what's running in X', 'that other Claude', 'the pane where', 'attach', 'kill that session', 'run this in the X session', 'is the build still going'."
---

# tmux, through tmuxctl

Do not call `tmux` directly. Use `tmuxctl` (on PATH). Raw tmux has overlapping
verbs, a positional target syntax that silently fuzzy-matches, output meant for
eyes, and — the reason this wrapper exists — no way to tell a shell waiting at a
prompt apart from a pane running an editor or a Claude Code session, where a
"command" is just keystrokes.

**First call, every time: `tmuxctl schema`.** It returns the whole surface as
JSON — every command, what it mutates, what it refuses, what each exit code
means. `tmuxctl help` is the same thing for a human.

## The shape of it

```
tmuxctl <command> [target] [options] [--json]
```

A target is `session`, `session:window`, `session:window.pane`, a raw `%pane`
id, or `.` for the current pane. A session name can be any unique substring;
an ambiguous one is an error, never a guess.

`--json` works on every command and is what to use when parsing.

## What to reach for

| Question | Call |
|---|---|
| what sessions exist | `tmuxctl ls --json` |
| what is running anywhere | `tmuxctl tree --json` |
| what is that pane doing | `tmuxctl status <target> --json` |
| what is on its screen | `tmuxctl read <target> [-n 40] [--history]` |
| which pane shows this error | `tmuxctl grep 'Error:' --json` |
| which agents need me | `tmuxctl agents --json` |
| run something there | `tmuxctl run <target> '<cmd>' --json` |
| type into something running | `tmuxctl send <target> 'text'` |
| wait for it to finish | `tmuxctl wait <target> --timeout 600` |
| make/remove | `tmuxctl new\|window\|split\|rename\|kill` |

## run vs send — the distinction that matters

`run` is for a pane sitting at a shell prompt. It redirects to a file inside
that shell rather than scraping the screen, so it returns the command's real
stdout+stderr and its real exit code, with no prompt, wrapping or colour codes.
It **refuses** (exit 3) any pane that is not an idle shell.

`send` types raw text or keys into whatever is there — an editor, a REPL, a
running agent — and neither waits nor captures. It is the deliberate way to do
what `run` refuses.

If `run` returns exit 3, do not "work around" it by using `send` with the same
shell command; read the refusal, which names what is actually running there.

## Other Claude Code sessions

`tmuxctl agents` is the one call that makes sense of them:

- **working** — busy on a task (`✳` in its title, which is the task)
- **waiting** — blocked on the user, needs an answer
- **ready** — running, idle at its prompt
- **stale** (`--stale`) — *not* an agent: a pane tmux-resurrect restored, showing
  an old Claude screen with nothing behind it but a shell

A live Claude Code pane reports a version string (`2.1.274`) as its foreground
command, because the binary is named after its version. That is how live and
stale are told apart; do not trust the pane title alone.

To answer a waiting agent: `tmuxctl send <target> 'your answer'`, then
`tmuxctl read <target> -n 40` to see what it did.

## Rules

- **Never kill without asking.** `kill` refuses busy or attached targets, and
  `--force` overrides that — but nothing restores a killed process.
  tmux-resurrect restores layout, not work. Ask the user first, every time.
- **Do not attach.** `--attach` takes over the terminal. An agent has no use
  for it; give the user the command instead.
- Long jobs: `run ... --bg` returns immediately with the output and exit-code
  file paths, or `run ... --timeout N` then `wait`. A `run` that times out
  leaves the command running and says so.
- `tmux-reap` (separate tool) retires empty sessions. Prefer it over hand-killing
  a list of sessions, and read its dry run first.

## Source

`~/dotfiles/base/bin/tmuxctl`, modules in `lib/tmuxctl/`, tests in
`bash ~/dotfiles/base/bin/tests/tmuxctl.test.sh` (runs against a throwaway tmux
server, never the real one).
