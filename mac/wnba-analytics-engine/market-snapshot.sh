#!/usr/bin/env bash
# Recurring Kalshi + Polymarket price-snapshot capture for the
# wnba-analytics-engine project. Snapshots are append-only time series, so
# this is intentionally run more often than the daily ESPN sync -- the
# whole point is building real intra-day line-movement history.
# No-ops if the project isn't present on this machine or Postgres isn't up.
set -euo pipefail

PROJECT_DIR="$HOME/Desktop/projects/betting-sports/wnba-analytics-engine"
[ -d "$PROJECT_DIR" ] || exit 0

cd "$PROJECT_DIR"
docker compose exec -T postgres pg_isready -U wnba -d wnba_engine >/dev/null 2>&1 || exit 0

uv run wnba-engine snapshot-kalshi
uv run wnba-engine snapshot-polymarket
