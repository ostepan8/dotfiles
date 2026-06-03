---
name: claude-mcp-config
description: "Add MCP servers to Claude Code by hand-editing the active config file. CRITICAL: when CLAUDE_CONFIG_DIR is set (Owen's `ccd`/`ccdw`/`ccds` aliases all set it), MCP servers store in $CLAUDE_CONFIG_DIR/.claude.json — NOT ~/.claude.json as the official docs say. Use this whenever wiring up axiom, linear, github, neon, or any MCP server."
---

# Claude Code MCP Server Configuration

## The actual rule (verified empirically on Claude Code 2.1.132)

**MCP storage location depends on `CLAUDE_CONFIG_DIR`:**

| Environment              | MCP config file                          |
|--------------------------|------------------------------------------|
| `CLAUDE_CONFIG_DIR` unset | `~/.claude.json` (the docs' answer)      |
| `CLAUDE_CONFIG_DIR=/path` | `$CLAUDE_CONFIG_DIR/.claude.json`        |

The official docs at `code.claude.com/docs/en/mcp` describe only the default case. They don't mention `CLAUDE_CONFIG_DIR`. **If the user has any `CLAUDE_CONFIG_DIR`-setting alias, you must write to that dir's `.claude.json`, not `~/.claude.json`.**

Owen's `~/.zshrc` aliases (all set `CLAUDE_CONFIG_DIR`):
- `ccd` → `~/.claude-personal/.claude.json`
- `ccds` → `~/.claude-school/.claude.json`
- `ccdw` → `~/.claude-work/.claude.json`

Run `echo $CLAUDE_CONFIG_DIR` in the user's host shell first if unsure which file to edit.

## Why NOT use `claude mcp add` CLI

We tried — it was a 15-turn rabbit hole. On Claude Code 2.1.132 the CLI:
- Reports `"File modified: <path>"` with a path that may or may not match where the running session reads.
- `claude mcp list` and the running `/mcp` UI sometimes disagree depending on whether `CLAUDE_CONFIG_DIR` is set in the parent shell vs. the child invocation.
- The path in tilde-form (`~/.claude-personal`) gets handled differently than expanded form (`$HOME/.claude-personal`) at different layers.

**Skip the CLI. Hand-edit the JSON directly.**

## Procedure

```bash
# 1. Identify the target file
TARGET="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
# If user uses ccd/ccdw/ccds, force the matching dir:
#   ccd  → /Users/ostepan/.claude-personal/.claude.json
#   ccdw → /Users/ostepan/.claude-work/.claude.json
#   ccds → /Users/ostepan/.claude-school/.claude.json

# 2. Backup
cp "$TARGET" "$TARGET.bak.$(date +%s)"

# 3. Edit via Python (json round-trip — file is huge, never line-edit)
python3 << EOF
import json
path = '$TARGET'
with open(path) as f: d = json.load(f)
# User scope (cross-project)
d.setdefault('mcpServers', {})['<NAME>'] = {'type': 'http', 'url': '<URL>'}
# Optional: also local scope for specific cwd(s) belt-and-suspenders
for cwd in ['<CWD1>', '<CWD2>']:
    proj = d.setdefault('projects', {}).setdefault(cwd, {})
    if proj is None: proj = d['projects'][cwd] = {}
    proj.setdefault('mcpServers', {})['<NAME>'] = {'type': 'http', 'url': '<URL>'}
with open(path, 'w') as f: json.dump(d, f, indent=2)
EOF

# 4. Verify with the user's actual env
CLAUDE_CONFIG_DIR=$HOME/.claude-personal claude mcp list | grep <NAME>

# 5. Tell user: COMPLETELY close the terminal window (not just /exit), reopen,
#    cd into target dir, run ccd/ccdw/ccds, then /mcp
```

## Don't forget local scope per-cwd

User scope makes the server *available* in all projects of that identity, but in practice the running `/mcp` UI sometimes only renders local-scope servers per cwd. Add to `projects.<cwd>.mcpServers` for each cwd you actually care about. Example for monorepo work: add to all the variant paths (main checkout, worktrees, alternate organized paths) since they're separate project entries.

## MCP server entry shapes

```jsonc
// HTTP (most hosted MCPs — axiom, linear, github, neon)
{ "type": "http", "url": "https://example.com/mcp" }

// HTTP with bearer
{ "type": "http", "url": "https://...", "headers": { "Authorization": "Bearer ${TOKEN}" } }

// stdio
{ "command": "node", "args": ["/abs/path/to/server.js"], "env": { "API_KEY": "${KEY}" } }
```

## Restart correctly

`/exit` inside Claude Code is NOT enough — close the entire terminal window/tab. Reopen, `cd` into the target dir, run the launcher (`ccd`/`ccdw`/`ccds` etc.), then `/mcp`.

## Known servers and templates

Source of truth: the user's monorepo `.mcp.example.json` (e.g. `~/Desktop/subconscious-monorepo/.mcp.example.json`).

| Server          | Type  | URL / Command                       | Auth         |
|-----------------|-------|-------------------------------------|--------------|
| axiom           | http  | https://mcp.axiom.co/mcp            | OAuth        |
| linear          | http  | https://mcp.linear.app/mcp          | OAuth        |
| context7        | http  | https://mcp.context7.com/mcp        | none         |
| github          | http  | https://api.githubcopilot.com/mcp   | GitHub OAuth |
| neon            | http  | https://mcp.neon.tech/mcp           | OAuth        |
| vercel          | http  | https://mcp.vercel.com              | OAuth        |
| chrome-devtools | stdio | `npx -y chrome-devtools-mcp@latest` | none         |
| playwright      | stdio | `npx @playwright/mcp@latest`        | none         |

## Debugging "I added it and it's not in /mcp"

In order:

1. **Trust dialog accepted for that project?** Most common gotcha — `--dangerously-skip-permissions` (in Owen's `ccd`/`ccdw`/`ccds` aliases) bypasses the trust prompt WITHOUT setting `hasTrustDialogAccepted: true` on the project entry. Claude Code then silently disables Local MCPs + plugins for that cwd. Symptom: `/mcp` shows ONLY claude.ai connectors + computer-use, no Local MCPs section, no plugins. **Fix:** set `hasTrustDialogAccepted: true` in `$CLAUDE_CONFIG_DIR/.claude.json` for the project path. Apply to every variant path of the same repo (worktrees etc.).
2. **Did you write to the right file?** Run `echo $CLAUDE_CONFIG_DIR` in the user's host shell. If set → write to `$CLAUDE_CONFIG_DIR/.claude.json`. If unset → `~/.claude.json`.
3. **Did you write to the cwd's project entry?** User scope alone may not show in `/mcp` per-cwd. Also write to `projects.<cwd>.mcpServers`.
4. **Did you fully kill the terminal**, not just `/exit`?
5. **Is the JSON still valid?** `python3 -m json.tool <file> >/dev/null` should pass.
6. **Verify with the user's exact env**: `CLAUDE_CONFIG_DIR=$HOME/.claude-<dir> claude mcp list | grep <name>` — must show the server.

## Owen's identity setup

```
~/.zshrc:
  function ccd()  { ... env CLAUDE_CONFIG_DIR=~/.claude-personal claude --dangerously-skip-permissions "$@"; }
  function ccdw() { ... env CLAUDE_CONFIG_DIR=~/.claude-work     claude --dangerously-skip-permissions "$@"; }
  function ccds() { ... env CLAUDE_CONFIG_DIR=~/.claude-school   claude --dangerously-skip-permissions "$@"; }
```

`~` is shell-expanded before `env` runs, so the actual env var value is the absolute path. Each identity has its own `.claude.json` that's read for both settings AND MCP servers (contrary to docs).

## Citations

- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp) — official, but only describes the default case (no `CLAUDE_CONFIG_DIR`).
- This skill version learned the hard way on 2026-05-07 setting up Axiom MCP for Owen across multiple sessions.
