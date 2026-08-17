# claude/

Versioned Claude Code config. Installed by `mac/setup.sh` step [5/8] into each
**profile dir** — `~/.claude-personal`, `~/.claude-school`, `~/.claude-work`.

> ⚠️ Not `~/.claude`. The zshrc export sets `CLAUDE_CONFIG_DIR=~/.claude-personal`
> as the default, and the `ccd` / `ccds` / `ccdw` aliases point at the
> `-personal` / `-school` / `-work` dirs. The vanilla `~/.claude` is never the
> active config, so installing there has no effect.

| File / dir | Installs to | What it is |
|---|---|---|
| `settings.json` | `<profile>/settings.json` | Global Claude Code settings: enabled plugins, `extraKnownMarketplaces`, `effortLevel`, `alwaysThinkingEnabled`, theme, skip-permission flags, and `NODE_EXTRA_CA_CERTS` for corporate CAs. |
| `mcp.json` | `<profile>/.mcp.json` | MCP server registrations (Linear, Notion, etc.). Uses `${NOTION_TOKEN}` so no secret is checked in. |
| `rules/` | `<profile>/rules/` | Custom rule docs included via CLAUDE.md (coding style, git workflow, testing, etc.). |
| `skills/` | `<profile>/skills/` | Versioned Agent Skills (~156KB of `SKILL.md` files + the `clerk` skill plugin). Small enough to track here. |

## Excluded on purpose

- **`settings.local.json`** — machine-local overrides; never versioned.
- **`sessions/`, `projects/`, `cache/`, `statsig/`, `telemetry/`,
  `shell-snapshots/`, `history.jsonl`, `todos/`, `tasks/`, `homunculus/`** —
  runtime / generated state.
- **`plugins/` cache & repos** — re-fetched from `extraKnownMarketplaces` +
  `enabledPlugins` in `settings.json` on first launch.

## Per-machine override pattern

`settings.json` references `NODE_EXTRA_CA_CERTS=/Users/ostepan/system-roots.pem`
which won't exist on a fresh machine. Either:

1. Generate the CA bundle and place it there, or
2. Drop a `<profile>/settings.local.json` that overrides the `env` section.

`.mcp.json` references `${NOTION_TOKEN}` — set that in your shell environment
(or a per-host `.env`) before launching `claude`.
