---
name: desktop-organizer
description: "Organize the macOS Desktop and locate files. Use when the user asks 'where is...', 'find my...', 'clean up desktop', 'organize files', or wants to know what's on their Desktop. Triggers on file location questions, desktop cleanup requests, or organizing loose files."
---

# Desktop Organizer

The user's Desktop at `/Users/ostepan/Desktop/` is organized into category folders. Nothing lives loose on the Desktop root. This skill helps locate files and maintain the structure.

## Desktop Root Structure

```
~/Desktop/
├── projects/        — all code projects, grouped by category
├── screenshots/     — all screenshots (macOS Cmd+Shift+3/4/5)
├── recordings/      — screen recordings and demo videos
├── documents/       — docs, PDFs, text files, resume
├── code-snippets/   — loose code files not part of a project
├── media/           — images, videos, downloads
├── presentations/   — slides, slide assets, exported PDFs
└── installers/      — DMG/PKG installer files
```

## projects/ Layout

### projects/subconscious/
The user works on the Subconscious AI platform. All repos grouped here:
- `subconscious/` — main repo
- `subconscious-monorepo/` — monorepo (has git worktrees)
- `subconscious-monorepo-worktrees/` — git worktrees for monorepo branches
- `subconscious-monorepos/` — may be stale
- `subconscious-sdk/` — SDK
- `subconscious-benchmarks/` — performance benchmarks
- `subconscious-browser-bench/` — browser benchmarks
- `subconscious-browser-bench-traces/` — trace output
- `subconscious-convex/` — Convex integration
- `_subcon_test/` — test project

### projects/agents/
Agent experiment and production implementations:
- `agent-runner/` — agent execution framework
- `movie-finding-agent/` — movie search agent
- `my-agent/`, `my-agent-name/`, `my-agrnt/` — agent experiments
- `search-agent/` — search agent
- `roku-agent/` — Roku TV control agent

### projects/claude-code/
- `nano-claude-code/` — lightweight Claude Code implementation (Python)
- `claude-code-living-directory/` — living directory project
- `claude-code-living-directory-linux/` — Linux variant
- `claude-code-slides/` — presentation about Claude Code
- `claude-picks/` — Claude-related picks

### projects/web-portfolio/
Portfolio sites and web projects (pre-existing + newly added):
- `desktop-portfolio/`, `owens-portfolio/`, `propslab/`
- `web copy/`, `dev-portfolio/`, `my-portfolio/`, `personal_portfolio/`, `portfolio/`
- `feed-site-1/`, `feed assets/`, `feed vitals/`
- `shelter-link/`, `web-interface/`

### projects/ (standalone, flat)
- `arb-scanner/` — arbitrage scanner
- `Beaver.cpp/` — C++ project
- `google-slides-mcp/` — Google Slides MCP server
- `my-app/`, `my-video/`, `my_cli_project/`
- `oduf/`, `spotify-playlist-parsing/`
- `stepan-password-manager/`, `stripe-sample-code/`
- `struct-output/`, `taskflow-cli/`, `tmux-config/`, `winnible-tracking/`
- `tic-tac-toe/`, `tic_tac_toe/` — duplicate projects
- `testing/` — standalone test dir
- `_stray-node/` — accidental npm install (node_modules, package.json)

### projects/ (pre-existing categories)
- `_archive/`, `_trash/`
- `ai-ml/`, `betting-sports/`, `emergency-sync/`
- `jarvis-projects/`, `learning/`, `misc/`
- `robotics/`, `schedulers/`, `school/`, `utilities/`

## Other Folders

### screenshots/
~101 PNG files. Pattern: `Screenshot YYYY-MM-DD at H.MM.SS AM/PM.png`

### recordings/
8 files. Screen recordings (.mov) + cli-demo.mov.

### documents/
- `Owen Stepan - Official Resume.docx.pdf`
- `SUBCONSCIOUS_SKILL_FEEDBACK.md`, `subconscious-launch-posts.md`
- `design-system.md`, `trigger-video-linkedin-post.md`
- `output.txt`, `sdk-token.txt`, `nonsense`

### code-snippets/
- `calculator.py`, `test-tinkering-fix.py`
- `pandadoc-field-map.ts`, `pandadoc-mapper.ts`, `pandadoc-mapper.spec.ts`

### media/
- `images/` — general images (school ID, charts, stock photos)
- `subconscious_videos/` — demo/marketing videos
- `drone.mp4`, `download.jpg`

### presentations/
- `slides.md` — slide content
- `slide-imgs/` — slide image assets
- `final.pdf` — exported presentation

### installers/
- `Zed-aarch64 (3).dmg`

---

## How to Use This Skill

### Finding Files

When the user asks "where is X":
1. Check this map first for known locations
2. Use `find /Users/ostepan/Desktop/ -maxdepth 4 -iname "*query*"` for fuzzy search
3. Use `mdfind -onlyin /Users/ostepan/Desktop/ "query"` for Spotlight search (content + metadata)
4. Check `~/Documents`, `~/Downloads`, and `~/` if not found on Desktop

### Organizing New Items

When new files appear on Desktop root (macOS drops screenshots, downloads, etc. here):

| Pattern | Destination |
|---------|-------------|
| `Screenshot *.png` | `screenshots/` |
| `Screen Recording *.mov` | `recordings/` |
| `.dmg` / `.pkg` | `installers/` |
| Loose `.py`/`.ts`/`.js` | `code-snippets/` or create project in `projects/` |
| `.pdf` / `.doc` / `.md` / `.txt` | `documents/` |
| Images / videos | `media/` |
| New git project | `projects/` (pick appropriate subcategory) |
| Subconscious-related | `projects/subconscious/` |

### Important Notes

- **Worktrees**: `projects/subconscious/subconscious-monorepo-worktrees/` has git worktrees linked to `projects/subconscious/subconscious-monorepo/`. If either moves, update the absolute paths in `.git` files and `.git/worktrees/*/gitdir`.
- **Sensitive files**: `documents/sdk-token.txt` may contain secrets. Confirm before moving/sharing.
- **Always confirm before**: deleting anything, moving project directories, touching token/secret files.
