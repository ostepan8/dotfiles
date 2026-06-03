---
name: edit-in-nvim
description: Open one or more files in nvim inside a new, detached tmux window so the current Claude session is not interrupted. Use whenever the user says "open in nvim", "edit in nvim", "let me edit X", "open X in vim/neovim", or asks to edit a file you just created (especially markdown). The user works inside tmux and wants to flip to nvim with their tmux prefix, not have nvim take over Claude's pane.
---

# edit-in-nvim

The user runs Claude Code inside tmux and edits files in nvim. Naively running `nvim <file>` from Bash either hangs (no TTY) or, via `tmux new-window` without `-d`, yanks focus away from Claude. This skill opens the file(s) in a new tmux window that stays in the background.

## When to invoke

Trigger on any of:

- "open <file> in nvim" / "in vim" / "in neovim"
- "edit <file>" after you just created or modified it
- "let me edit this" / "lemme edit" referring to a file in conversation
- Direct invocation: `/edit-in-nvim <file>`

Do NOT use this for files you (Claude) need to read or modify — use `Read` / `Edit` for that. This is only for handing the file to the user for human editing.

## Preflight

Run these checks once at the start. If any fail, fall back to suggesting `!nvim <file>` and explain why.

```bash
# 1. Inside tmux?  (TMUX env var is set when attached)
[ -n "$TMUX" ] && echo "in tmux" || echo "no tmux"

# 2. nvim installed?
command -v nvim
```

If not in tmux, tell the user to run `!nvim <file>` themselves — there is no way to launch a TUI from a non-TTY shell.

## The command

For a single file:

```bash
tmux new-window -d -n nvim "nvim <absolute-or-relative-path>"
```

Key flags:

- `-d` — detached. Creates the window but keeps the user's focus on Claude's window. Without this, focus jumps to nvim and the user has to manually switch back.
- `-n nvim` — names the window so it is easy to spot in the tmux status bar.
- No `-t <session>` needed when run from inside tmux; it goes to the current session.

For multiple files in one nvim instance (tabs or buffers):

```bash
tmux new-window -d -n nvim "nvim -p file1.md file2.md file3.md"   # tab pages
# or
tmux new-window -d -n nvim "nvim file1.md file2.md file3.md"      # buffers
```

For multiple files in separate windows (one per file):

```bash
for f in file1.md file2.md file3.md; do
  tmux new-window -d -n "nvim:$(basename "$f")" "nvim '$f'"
done
```

Default to a single nvim with `-p` (tab pages) when the user passes more than one file, unless they ask for separate windows.

## After launching

Tell the user briefly:

- The window was created detached.
- How to switch: tmux prefix + `n` (next), `p` (previous), or the window number shown in the status bar.
- That `:q` in nvim closes the window and drops them back automatically.

Do not over-explain. One short sentence is plenty.

## Edge cases

- **File path with spaces:** wrap in single quotes inside the tmux command string: `tmux new-window -d -n nvim "nvim '/path/with spaces/file.md'"`.
- **Relative paths:** they resolve against Claude's cwd, which is the same cwd as the tmux pane Claude runs in — so relative paths work. Prefer them for readability.
- **File does not exist yet:** nvim will open it as a new buffer; this is fine and expected when the user wants to start fresh.
- **User is not in tmux:** suggest `!nvim <file>` and stop. Do not try AppleScript or terminal-spawning hacks unless the user specifically asks for that.
- **User wants `vim` instead of `nvim`:** swap the binary. Same flags work.

## Why this skill exists

Documented after a session where:
1. Claude ran `nvim file` directly — would have hung.
2. Claude ran `tmux new-window` without `-d` — stole focus from the Claude pane.
3. Claude ran `tmux new-window -d` — worked cleanly.

The `-d` flag is the whole point. Don't forget it.
