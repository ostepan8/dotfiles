#!/usr/bin/env bash
# Recurring ESPN box-score sync for the wnba-analytics-engine project.
# No-ops if the project isn't present on this machine (e.g. a second Mac
# that doesn't do this data-engineering work) or Docker/Postgres isn't up.
set -euo pipefail

PROJECT_DIR="$HOME/Desktop/projects/betting-sports/wnba-analytics-engine"
[ -d "$PROJECT_DIR" ] || exit 0

cd "$PROJECT_DIR"
docker compose exec -T postgres pg_isready -U wnba -d wnba_engine >/dev/null 2>&1 || exit 0

uv run wnba-engine sync-recent
