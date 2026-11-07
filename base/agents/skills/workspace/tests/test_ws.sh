#!/usr/bin/env bash
# Offline checks of ws and stack against a throwaway git origin.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; WS="$HERE/../scripts/ws"; STACK="$HERE/../scripts/stack"
FAILS=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2], got [$3]"; FAILS=$((FAILS + 1)); fi; }
exists() { [ -e "$1" ] && echo yes || echo no; }
S="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$S"' EXIT
export HOME="$S/home" WS_NO_TMUX=1; mkdir -p "$HOME"
git init -q -b main "$S/seed"; git -C "$S/seed" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
printf '.env\n' > "$S/seed/.gitignore"; git -C "$S/seed" add .gitignore; git -C "$S/seed" -c user.name=t -c user.email=t@t commit -q -m two
git clone -q --bare "$S/seed" "$S/origin.git"
mkdir -p "$S/store/web"; echo SECRET=1 > "$S/store/web/.env"

W="$S/spaces/demo"
"$WS" new demo "$W" "$S/origin.git" main --env-from "$S/store" >/dev/null; RC=$?
check "new: exits 0" 0 "$RC"
for p in AGENTS.md CLAUDE.md docs/README.md scripts/wt .claude/skills repos/origin worktrees/origin/dev; do check "new: has $p" yes "$(exists "$W/$p")"; done
check "new: registers the name" "$W" "$(readlink "$HOME/workspaces/demo")"
check "new: CLAUDE points at AGENTS" "@AGENTS.md" "$(cat "$W/CLAUDE.md")"
check "new: dev checkout has env" "SECRET=1" "$(cat "$W/worktrees/origin/dev/web/.env")"
check "new: repo is a real clone, not a link" no "$([ -L "$W/repos/origin" ] && echo yes || echo no)"
check "new: dev branch" demo-dev "$(git -C "$W/worktrees/origin/dev" branch --show-current)"

# Running it again keeps your edits.
echo mine > "$W/AGENTS.md"; "$WS" new demo "$W" "$S/origin.git" main >/dev/null; RC=$?
check "again: exits 0" 0 "$RC"; check "again: keeps edits" mine "$(cat "$W/AGENTS.md")"

# scripts/wt makes a task worktree with env, from any folder.
(cd "$W/worktrees/origin/dev/web" && "$W/scripts/wt" fix-thing >/dev/null); RC=$?
check "wt: exits 0" 0 "$RC"; check "wt: branch" fix-thing "$(git -C "$W/worktrees/origin/fix-thing" branch --show-current)"
check "wt: copies env" "SECRET=1" "$(cat "$W/worktrees/origin/fix-thing/web/.env" 2>/dev/null)"
"$W/scripts/wt" 'bad;name' >/dev/null 2>&1; check "wt: rejects a bad name" 1 "$?"

"$WS" new 'x;y' "$S/z" "$S/origin.git" main >/dev/null 2>&1; check "new: rejects a bad name" 1 "$?"

# stack finds the workspace from a deep folder.
printf '#!/bin/sh\necho "stack got $*"\n' > "$W/scripts/stack"; chmod +x "$W/scripts/stack"
check "stack: from a deep folder" "stack got start" "$(cd "$W/worktrees/origin/dev/web" && "$STACK" start)"
check "stack: by name from anywhere" "stack got status" "$(cd "$S" && "$STACK" demo status)"
OUT="$(cd "$S" && "$STACK" start 2>&1)"; RC=$?
check "stack: outside a workspace fails" 1 "$RC"; check "stack: says what to do" 1 "$(printf '%s\n' "$OUT" | grep -c 'workspace')"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
