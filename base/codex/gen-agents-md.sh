#!/usr/bin/env bash
# Regenerate base/codex/AGENTS.md from the shared rules in base/claude/rules.
#
# Codex reads AGENTS.md; Claude reads rules/. Rather than maintain the standards
# twice and let them drift, AGENTS.md is generated from the same rule files.
#
# Only the tool-neutral rules are included. agents.md, hooks.md and
# performance.md describe Claude Code's own subagents, hook events and model
# routing — none of which exist in Codex, so shipping them would be actively
# misleading rather than merely redundant.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RULES="$REPO/base/claude/rules/common"
OUT="$REPO/base/codex/AGENTS.md"

PORTABLE=(coding-style testing security git-workflow development-workflow patterns)

{
  echo "# Agent instructions"
  echo
  echo "GENERATED FILE — do not edit by hand."
  echo "Regenerate with \`base/codex/gen-agents-md.sh\` after changing anything in"
  echo "\`base/claude/rules/common/\`. Source of truth is those rule files, so Claude"
  echo "(via rules/) and Codex (via this file) never drift apart."
  echo
  for r in "${PORTABLE[@]}"; do
    [ -f "$RULES/$r.md" ] || { echo "missing rule: $r.md" >&2; exit 1; }
    echo "<!-- from base/claude/rules/common/$r.md -->"
    cat "$RULES/$r.md"
    echo
  done
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines from ${#PORTABLE[@]} rule files)"
