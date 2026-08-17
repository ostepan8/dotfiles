#!/usr/bin/env bash
# Weekly balldontlie season-level backfill for wnba-analytics-engine:
# advanced player stats, advanced team stats, play-by-play, shot-zone
# efficiency splits, and player-prop sportsbook odds.
# All season-level or per-completed-game data (not per-day like the ESPN
# box-score sync), so weekly is enough. Upserted / ON CONFLICT DO NOTHING
# on the ingest side, safe to re-run. No-ops if the project isn't present
# on this machine, Postgres isn't up, or the balldontlie API key isn't
# configured (paid API, key lives in .env, gitignored -- see .env.example).
#
# Game-level sportsbook odds and official standings are NOT here -- both
# change frequently enough (rolling recent-only odds window; standings
# shift on every completed game) that they live in the 2-hourly
# market-and-injury-snapshot.sh instead. Player-prop odds stay weekly:
# backfill-player-prop-odds queries per-game_id across the whole season,
# too heavy to run every 2 hours, and props are tied to completed games
# rather than needing intra-day freshness the way current odds/standings do.
set -euo pipefail

PROJECT_DIR="$HOME/Desktop/projects/betting-sports/wnba-analytics-engine"
[ -d "$PROJECT_DIR" ] || exit 0

cd "$PROJECT_DIR"
[ -f .env ] || exit 0
docker compose exec -T postgres pg_isready -U wnba -d wnba_engine >/dev/null 2>&1 || exit 0

SEASON="$(date +%Y)"
uv run wnba-engine backfill-advanced-stats --season "$SEASON"
uv run wnba-engine backfill-team-advanced-stats --season "$SEASON"
uv run wnba-engine backfill-plays --season "$SEASON"
uv run wnba-engine backfill-shot-zones --season "$SEASON"
uv run wnba-engine backfill-player-prop-odds --season "$SEASON"
