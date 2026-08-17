#!/usr/bin/env bash
# Recurring Kalshi + Polymarket price-snapshot + injury-report capture,
# plus balldontlie official standings and sportsbook game odds, plus
# the-odds-api current odds + final-score cross-check, for the
# wnba-analytics-engine project. All of these are either append-only time
# series or a frequently-changing current-state snapshot, so this is
# intentionally run more often than the daily ESPN sync / weekly
# balldontlie-season-sync.sh -- the whole point is building real intra-day
# line-movement AND status history:
#   - injury snapshot only has value at the moment it's true; ESPN's
#     /injuries feed is current-state only, no historical backfill exists,
#     so missing a capture window is lost history, not just staleness.
#   - balldontlie's /wnba/v1/odds only exposes a rolling recent window (not
#     full season history), same "lost if missed" property as injuries --
#     backfill-odds here pulls a short trailing window every run.
#   - the-odds-api's CURRENT odds (snapshot-odds-api) has the same "rolling
#     window, missed capture = lost line-movement data" property -- unlike
#     balldontlie's odds, the-odds-api also has a REAL historical archive
#     (see backfill-odds-api-history), but that's a manual/one-off command,
#     NOT run here, same convention as balldontlie's --season backfills.
#   - the-odds-api's final scores (snapshot-odds-api-scores) are a
#     cross-check against games.home_score/away_score, not a source of
#     truth on their own (see db/migrations/0021_odds_api_game_scores.sql)
#     -- running it on this cadence keeps that check's data reasonably
#     fresh without needing its own separate schedule.
#   - official standings shift on every completed game, not just weekly;
#     backfill-standings is a cheap upsert (~13 rows), safe to run often.
# No-ops if the project isn't present on this machine, Postgres isn't up,
# or (for the balldontlie/the-odds-api calls) the relevant API key isn't
# configured.
set -euo pipefail

PROJECT_DIR="$HOME/Desktop/projects/betting-sports/wnba-analytics-engine"
[ -d "$PROJECT_DIR" ] || exit 0

cd "$PROJECT_DIR"
docker compose exec -T postgres pg_isready -U wnba -d wnba_engine >/dev/null 2>&1 || exit 0

uv run wnba-engine snapshot-kalshi
uv run wnba-engine snapshot-polymarket
uv run wnba-engine snapshot-injuries

if [ -f .env ]; then
    SEASON="$(date +%Y)"
    SINCE="$(date -v-2d +%Y-%m-%d 2>/dev/null || date -d '2 days ago' +%Y-%m-%d)"
    UNTIL="$(date +%Y-%m-%d)"
    uv run wnba-engine backfill-standings --season "$SEASON"
    uv run wnba-engine backfill-odds --since "$SINCE" --until "$UNTIL"
    uv run wnba-engine snapshot-odds-api
    uv run wnba-engine snapshot-odds-api-scores
fi
