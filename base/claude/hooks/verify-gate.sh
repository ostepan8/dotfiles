#!/usr/bin/env bash
# verify-gate.sh — a Stop hook: do not report done on code nobody ran.
#
# In 60 days, 20 prompts were some form of "it doesn't work / did you even test
# it / use playwright": the surveillance dashboard, jarvis and the TV, the
# carousel on a big monitor, the video editor. Each time the session had edited
# code and stopped without looking at the result.
#
# Reads the transcript since the user's last prompt. Blocks once (exit 2) when
# code was edited and nothing after the last edit checked it — a test, a build,
# a curl, a log read, a screenshot. UI files need a visual check specifically.
# Lets the stop through when the final message says plainly that the work is
# unverified, and never blocks twice in a row (stop_hook_active).
#
# Fails OPEN on anything unexpected. Escape hatch: VERIFY_GATE=off
set -uo pipefail

[ "${VERIFY_GATE:-}" = "off" ] && exit 0
input=$(cat 2>/dev/null || true)
command -v python3 >/dev/null 2>&1 || exit 0

HOOK_INPUT="$input" python3 - <<'PY' 2>/dev/null
import json, os, re, sys

try:
    hook = json.loads(os.environ["HOOK_INPUT"])
except Exception:
    sys.exit(0)
if hook.get("stop_hook_active"):
    sys.exit(0)
path = hook.get("transcript_path") or ""
if not os.path.isfile(path):
    sys.exit(0)

CODE = re.compile(r"\.(tsx?|jsx?|mjs|go|py|rs|swift|kt|css|scss|html|vue|svelte|sh|sql)$")
UI = re.compile(r"\.(tsx|jsx|css|scss|html|vue|svelte)$")
BASH_WRITE = re.compile(r"(?:cat|tee)\s+>{1,2}\s*([^\s<;&|]+)|sed\s+-i\S*\s+(?:'[^']*'|\"[^\"]*\")\s+([^\s;&|]+)")
CHECK = re.compile(
    r"\b(test|pytest|vitest|jest|playwright|go (?:test|vet|build|run)|cargo|tsc|"
    r"npm run|pnpm|bun (?:run|test)|make|curl|wget|nephos (?:logs|ps)|journalctl|"
    r"tail|screencapture|agent-browser|lint|eslint|ruff|mypy|node |python3? \S+\.py)\b|(?:^|[\s;&|])(?:\./|bash |sh )\S+")
VISUAL_TOOL = re.compile(r"playwright.*(screenshot|snapshot)|browser_take_screenshot|browser_snapshot")
VISUAL_BASH = re.compile(r"playwright|agent-browser|screenshot|screencapture")
UNVERIFIED = re.compile(r"(?i)\b(unverified|not verified|haven'?t (?:tested|verified|run)|did(?:n'?t| not) (?:test|verify|run)|could(?:n'?t| not) (?:test|verify))\b")

events = []
for line in open(path, errors="ignore"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    msg = d.get("message") or {}
    content = msg.get("content")
    if d.get("type") == "user" and not d.get("isMeta"):
        if isinstance(content, str) or (isinstance(content, list) and any(c.get("type") == "text" for c in content)):
            events = []
            continue
    if d.get("type") != "assistant" or not isinstance(content, list):
        continue
    for c in content:
        if c.get("type") == "text":
            events.append(("text", c.get("text", "")))
        elif c.get("type") == "tool_use":
            events.append(("tool", c.get("name", ""), c.get("input") or {}))

pending, pending_ui, last_text = set(), set(), ""
for ev in events:
    if ev[0] == "text":
        last_text = ev[1]
        continue
    _, name, inp = ev
    edited = []
    if name in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        edited = [inp.get("file_path", "")]
    elif name == "Bash":
        cmd = inp.get("command", "")
        edited = [a or b for a, b in BASH_WRITE.findall(cmd)]
        if CHECK.search(cmd):
            pending.clear()
        if VISUAL_BASH.search(cmd):
            pending_ui.clear()
    elif VISUAL_TOOL.search(name):
        pending.clear()
        pending_ui.clear()
    elif name == "Read" and re.search(r"\.(png|jpe?g|webp)$", inp.get("file_path", "")):
        pending_ui.clear()
    elif name in ("Agent", "Task"):
        pending.clear()
    for f in edited:
        if CODE.search(f or ""):
            pending.add(f)
            if UI.search(f):
                pending_ui.add(f)

if (not pending and not pending_ui) or UNVERIFIED.search(last_text):
    sys.exit(0)

files = sorted(pending | pending_ui)
shown = ", ".join(os.path.basename(f) for f in files[:5]) + (" …" if len(files) > 5 else "")
how = []
if pending_ui:
    how.append("UI changed: open it with playwright and screenshot it at phone (390px) and wide (1920px) widths, then look at the screenshots.")
if pending - pending_ui:
    how.append("Run what you changed: the tests, a build, a curl against the service, or its logs after a real request.")
sys.stderr.write(
    "Not done yet: you edited " + shown + " after the last check, and nothing since has exercised it.\n"
    + "\n".join("- " + h for h in how)
    + "\nIf it genuinely cannot be verified from here, say so plainly in your final message (e.g. \"unverified: …\") and stop.\n")
sys.exit(2)
PY
