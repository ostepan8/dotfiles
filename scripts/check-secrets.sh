#!/usr/bin/env bash
# check-secrets.sh — pre-push scanner for a PUBLIC dotfiles repo.
#
# Scans tracked files for credentials, fleet identifiers, and private network
# topology. Run by `make check` and (once installed) the pre-push hook.
#
# Design note: the allowlist holds known-PLACEHOLDER *values*, not exempt files.
# Exempting a path would blind the scanner to exactly the directory a leak most
# recently came from (claude/skills/yeelight shipped the real bulb list). With a
# value allowlist, a genuine address in that same file still fires.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; YELLOW=""; DIM=""; OFF=""; }

# ---------------------------------------------------------------------------
# Patterns: "<label>|<extended regex>|<sample that MUST match>"
#
# Anchored deliberately. An earlier draft grepped for bare `tail` to catch the
# tailnet and matched four innocent `tailscale` lines in the Brewfile — a
# scanner that cries wolf is a scanner that gets ignored.
#
# Every pattern carries a sample, verified on each run (see self_test below).
# This exists because the private-address pattern was originally written with
# `\b` word boundaries: those work in BSD `grep -oE` but NOT in `git grep -E`,
# which uses a different engine. The outer filter silently matched nothing, so
# the check reported "clean" while that rule was entirely dead. A scanner that
# cannot fail is worse than no scanner — it produces confidence, not safety.
# ---------------------------------------------------------------------------
PATTERNS=(
  "personal domain|onephos\.com|https://llm.onephos.com/v1"
  # Bare prefix, not just the full *.ts.net host: the tailnet id leaks on its own
  # too (the brief mentioned it unqualified). Safe against the word "tailscale" —
  # 's' is not a hex digit, so `tail` + 6 hex chars cannot match it.
  "tailnet name|tail[0-9a-f]{6,}|tail4f2a9c"
  "Anthropic/OpenAI key|sk-(proj|ant|live)-[A-Za-z0-9_-]{16,}|sk-ant-api03-AbCdEf0123456789XyZ"
  "AWS access key|AKIA[0-9A-Z]{16}|AKIAIOSFODNN7EXAMPLE"
  "GitHub token|gh[pousr]_[A-Za-z0-9]{20,}|ghp_AbCdEf0123456789AbCdEf0123456789"
  "Slack token|xox[abprs]-[A-Za-z0-9-]{10,}|xoxb-1234567890-abcdefghij"
  "private key block|BEGIN [A-Z ]*PRIVATE KEY|-----BEGIN OPENSSH PRIVATE KEY-----"
  "generic api key assignment|(api[_-]?key|secret|password|token)[[:space:]]*[=:][[:space:]]*[\"'][A-Za-z0-9_/+-]{20,}[\"']|api_key = \"abcdefghij0123456789XY\""
  "private network address|(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}|10.0.0.147"
)

# Assert every pattern still fires against its sample, using the SAME engine the
# scan uses (git grep, not the shell's grep). Catches regex-dialect drift.
self_test() {
  local tmp entry label regex sample broken=0
  # Must live INSIDE the repo: `git grep --no-index` rejects a pathspec outside
  # the worktree ("is outside repository"), which would fail every pattern.
  tmp="$(mktemp "$PWD/.secretscan.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  for entry in "${PATTERNS[@]}"; do
    label="${entry%%|*}"
    regex="${entry#*|}"; regex="${regex%|*}"
    sample="${entry##*|}"
    printf '%s\n' "$sample" > "$tmp"
    if ! git grep --no-index -qE "$regex" -- "$tmp" 2>/dev/null; then
      echo "${RED}BROKEN PATTERN${OFF} '$label' no longer matches its own sample:"
      echo "    regex:  $regex"
      echo "    sample: $sample"
      broken=1
    fi
  done
  rm -f "$tmp"
  return $broken
}

# Known-placeholder values. Anything matched that is NOT in this list is real.
ALLOW=(
  "127.0.0.1"        # loopback — nephos env.template, lifeos LaunchAgent
  "0.0.0.0"
  "10.0.0.10"        # yeelight bulbs.txt.template placeholder
  "10.0.0.11"        # yeelight bulbs.txt.template placeholder
  "sk-proj-xxxxx"    # claude/rules/typescript/security.md — "don't do this" example
)

is_allowed() {
  local hit="$1" ok
  for ok in "${ALLOW[@]}"; do [ "$hit" = "$ok" ] && return 0; done
  return 1
}

if ! self_test; then
  echo
  echo "${RED}Refusing to report a result from a scanner that cannot detect.${OFF}"
  exit 2
fi

fail=0
echo "${DIM}scanning $(git ls-files | wc -l | tr -d ' ') tracked files"
echo "${DIM}(${#PATTERNS[@]} patterns, all verified against samples)${OFF}"

for entry in "${PATTERNS[@]}"; do
  label="${entry%%|*}"
  regex="${entry#*|}"; regex="${regex%|*}"

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    file="${line%%:*}"
    rest="${line#*:}"
    lineno="${rest%%:*}"
    content="${rest#*:}"

    # Report the line only if at least one match on it is not a placeholder.
    unallowed=""
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      is_allowed "$hit" || unallowed="$hit"
    done < <(printf '%s' "$content" | grep -oE "$regex" 2>/dev/null)

    [ -z "$unallowed" ] && continue

    if [ "$fail" -eq 0 ]; then
      echo
      echo "${RED}SECRET SCAN FAILED${OFF}"
      echo
    fi
    fail=1
    printf '  %s%s%s  %s:%s\n' "$RED" "$label" "$OFF" "$file" "$lineno"
    printf '    %smatched:%s %s\n' "$DIM" "$OFF" "$unallowed"
    # This file is the ONE justified path exemption: it necessarily contains a
    # sample of every secret shape it detects. Kept to exactly one file — the
    # allowlist above is values, not paths, precisely so no other file can hide.
  done < <(git grep -InE "$regex" -- . ':!scripts/check-secrets.sh' 2>/dev/null)
done

echo
if [ "$fail" -ne 0 ]; then
  echo "${RED}Push blocked.${OFF} Move the value out of the repo (see"
  echo "claude/skills/nephos/env.template for the pattern), or if it is genuinely a"
  echo "placeholder, add it to ALLOW in scripts/check-secrets.sh with a comment."
  exit 1
fi

echo "${GREEN}clean${OFF} — no credentials, fleet identifiers, or private addresses found."
echo "${DIM}note: the owner's own name/email appear intentionally (skhdrc, zshrc,${OFF}"
echo "${DIM}cheatsheet) and are not scanned for.${OFF}"
