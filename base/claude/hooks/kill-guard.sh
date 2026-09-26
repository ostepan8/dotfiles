#!/usr/bin/env bash
# kill-guard.sh — a PreToolUse hook: no command that takes down every session.
#
# On 2026-09-14 a tmux-config test ended in `tmux kill-server`, which killed
# every tmux session on the machine — including the Claude sessions running in
# them. On 2026-09-20 everything died again. Agents also reach for `pkill -f`
# (45 times in 60 days) with patterns like `claude` or `node` that match far
# more than the process they mean.
#
# Blocks: tmux kill-server, killall, kill -1 / kill -9 -1, and pkill/pgrep-kill
# whose pattern is a bare broad name. A pkill -f with a specific pattern (a path,
# a port, a script name) passes. Fails OPEN on anything unexpected.
# To run anyway, put KILL_GUARD=off in the command itself.
set -uo pipefail

allow() { exit 0; }
block() { echo "$1" >&2; exit 2; }

input=$(cat 2>/dev/null || true)
command -v python3 >/dev/null 2>&1 || allow

reason=$(printf '%s' "$input" | python3 -c '
import json, re, shlex, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit()
if d.get("tool_name") != "Bash":
    sys.exit()
cmd = (d.get("tool_input") or {}).get("command", "")
if "KILL_GUARD=off" in cmd:
    sys.exit()

BROAD = {"tmux", "claude", "node", "python", "python3", "zsh", "bash", "sh", "ssh",
         "sshd", "nephos", "go", "bun", "npm", "pnpm", "ollama", "docker", "java",
         "ruby", "vim", "nvim", "ghostty", "Terminal", "launchd", "agent", "server"}

for part in re.split(r"[;&|\n]+|\$\(|`", cmd):
    try:
        words = shlex.split(part, posix=True)
    except ValueError:
        words = part.split()
    while words and ("=" in words[0] or words[0] in ("sudo", "timeout", "gtimeout", "env", "exec")):
        words = words[1:]
        if words and re.fullmatch(r"\d+[smh]?", words[0]):
            words = words[1:]
    if not words:
        continue
    prog = words[0].rsplit("/", 1)[-1]
    args = words[1:]
    if prog == "tmux" and ("-L" in args or "-S" in args):
        continue
    if prog == "tmux" and "kill-server" in args:
        print("tmux kill-server kills every tmux session on the machine, including the Claude sessions inside them. Kill the one session you made: tmux kill-session -t <name>. For a test server, use its own socket: tmux -L test ... kill-server.")
        sys.exit()
    if prog == "killall":
        print("killall hits every process with that name. Find the one you mean (pgrep -fl <specific pattern>) and kill its PID.")
        sys.exit()
    targets = list(args)
    if targets[:1] in (["-s"], ["-n"]):
        targets = targets[2:]
    elif targets and re.fullmatch(r"-(?:[A-Z]+|\d+)", targets[0]):
        targets = targets[1:]
    if prog == "kill" and any(t in ("-1", "0") for t in targets if t != "--"):
        print("kill -1 / kill 0 signals every process you own or the whole group. Kill a specific PID.")
        sys.exit()
    if prog == "pkill":
        pats = [a for a in args if not a.startswith("-")]
        pat = pats[-1] if pats else ""
        core = pat.strip("^$ ").lower()
        if not core or core in {b.lower() for b in BROAD} or len(core) < 5:
            print("pkill pattern %r is broad enough to hit other sessions and services. Use a specific pattern (a full script path, a port, a unique flag), or pgrep -fl first and kill the PID." % pat)
            sys.exit()
' 2>/dev/null)

[ -n "$reason" ] || allow
block "BLOCKED by kill-guard: ${reason}

If you are certain, put KILL_GUARD=off in the command itself."
