#!/usr/bin/env bash
# Weekly balldontlie advanced-stats backfill for wnba-analytics-engine.
# Season-level (not per-game) data -- balldontlie's advanced/four-factors
# stats accrue as the season progresses, but there's no reason to re-check
# daily like the ESPN box-score sync. Upserted (ON CONFLICT DO UPDATE),
# safe to re-run. No-ops if the project isn't present on this machine,
# Postgres isn't up, or the balldontlie API key isn't configured (paid
# API, key lives in .env, gitignored -- see .env.example).
set -euo pipefail

PROJECT_DIR="$HOME/Desktop/projects/betting-sports/wnba-analytics-engine"
[ -d "$PROJECT_DIR" ] || exit 0

cd "$PROJECT_DIR"
[ -f .env ] || exit 0
docker compose exec -T postgres pg_isready -U wnba -d wnba_engine >/dev/null 2>&1 || exit 0

uv run wnba-engine backfill-advanced-stats --season "$(date +%Y)"
