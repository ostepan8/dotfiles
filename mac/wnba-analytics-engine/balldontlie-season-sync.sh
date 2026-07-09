#!/usr/bin/env bash
# Weekly balldontlie season-level backfill for wnba-analytics-engine:
# advanced player stats, play-by-play, and shot-zone efficiency splits.
# All season-level or per-completed-game data (not per-day like the ESPN
# box-score sync), so weekly is enough. Upserted / ON CONFLICT DO NOTHING
# on the ingest side, safe to re-run. No-ops if the project isn't present
# on this machine, Postgres isn't up, or the balldontlie API key isn't
# configured (paid API, key lives in .env, gitignored -- see .env.example).
set -euo pipefail

PROJECT_DIR="$HOME/Desktop/projects/betting-sports/wnba-analytics-engine"
[ -d "$PROJECT_DIR" ] || exit 0

cd "$PROJECT_DIR"
[ -f .env ] || exit 0
docker compose exec -T postgres pg_isready -U wnba -d wnba_engine >/dev/null 2>&1 || exit 0

SEASON="$(date +%Y)"
uv run wnba-engine backfill-advanced-stats --season "$SEASON"
uv run wnba-engine backfill-plays --season "$SEASON"
uv run wnba-engine backfill-shot-zones --season "$SEASON"
