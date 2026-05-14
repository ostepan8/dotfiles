# claude/

Versioned Claude Code config. Installed by `mac/setup.sh` step [5/8] into
`~/.claude/`.

| File / dir | Installs to | What it is |
|---|---|---|
| `settings.json` | `~/.claude/settings.json` | Global Claude Code settings: `alwaysThinkingEnabled`, `effortLevel`, plugin marketplaces, `NODE_EXTRA_CA_CERTS` for corporate CAs. |
| `mcp.json` | `~/.claude/.mcp.json` | MCP server registrations (Linear, Notion, local todo-queue). Uses `${NOTION_TOKEN}` so no secret is checked in. |
| `rules/` | `~/.claude/rules/` | Custom rule docs that get included via CLAUDE.md (coding style, git workflow, testing, etc.). |

## Excluded on purpose

- **`~/.claude/skills/`** — ~38MB of generated/cloned skills. Not
  versioned here; tracked separately if at all.
- **`~/.claude/settings.local.json`** — machine-local overrides; never
  versioned.
- **`~/.claude/sessions/`, `~/.claude/projects/`, `~/.claude/cache/`** —
  runtime state.

## Per-machine override pattern

`settings.json` references `NODE_EXTRA_CA_CERTS=/Users/ostepan/system-roots.pem`
which won't exist on a fresh machine. Either:

1. Generate the CA bundle and place it there, or
2. Drop a `~/.claude/settings.local.json` that overrides the `env` section.

`.mcp.json` references `${NOTION_TOKEN}` — set that in your shell
environment (or a per-host `.env`) before launching `claude`.
