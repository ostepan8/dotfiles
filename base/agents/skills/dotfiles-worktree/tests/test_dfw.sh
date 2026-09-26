#!/usr/bin/env bash
# Integration test for dfw against a throwaway origin — touches nothing real.
#   bash tests/test_dfw.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DFW="$HERE/../scripts/dfw"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export DFW_REPO="$TMP/checkout" DFW_ROOT="$TMP/wt" DFW_LOCK="$TMP/lock" DFW_APPLY="touch $TMP/applied"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null   # the user's global config must not change the outcome

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$DFW_REPO" 2>/dev/null
cd "$DFW_REPO" || exit 1
git checkout -q -b main
mkdir -p base/claude
printf '{\n  "model": "opus",\n  "permissions": {\n    "allow": [\n      "Read"\n    ]\n  }\n}\n' > base/claude/settings.json
printf 'line one\nline two\nline three\n' > zshrc
echo 'base/claude/settings.json merge=dfjson' > .gitattributes
git add -A && git commit -qm init && git push -q -u origin main

echo "parallel changes to different files and to the same JSON"
A="$("$DFW" start alpha)"; B="$("$DFW" start beta)"; C="$("$DFW" start gamma)"
check "start prints distinct worktree paths" '[ -d "$A" ] && [ -d "$B" ] && [ "$A" != "$B" ]'
check "start is idempotent" '[ "$("$DFW" start alpha)" = "$A" ]'

python3 - "$A/base/claude/settings.json" <<'EOF'
import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["permissions"]["allow"].append("Bash(ls:*)"); d["hooks"] = {"Stop": []}
open(p, "w").write(json.dumps(d, indent=2) + "\n")
EOF
python3 - "$B/base/claude/settings.json" <<'EOF'
import json, sys; p = sys.argv[1]; d = json.load(open(p)); d["permissions"]["allow"].append("WebSearch"); d["outputStyle"] = "terse"
open(p, "w").write(json.dumps(d, indent=2) + "\n")
EOF
echo 'alias g=git' >> "$C/zshrc"

"$DFW" land alpha -m "feat: alpha" >/dev/null 2>&1; check "alpha lands" '[ $? -eq 0 ]'
"$DFW" land gamma -m "feat: gamma" >/dev/null 2>&1; check "gamma lands" '[ $? -eq 0 ]'
"$DFW" land beta  -m "feat: beta"  >/dev/null 2>&1; check "beta lands through a JSON overlap" '[ $? -eq 0 ]'

git -C "$DFW_REPO" fetch -q
S="$(git -C "$DFW_REPO" show origin/main:base/claude/settings.json)"
check "settings.json keeps both permissions" 'grep -q "Bash(ls:\*)" <<<"$S" && grep -q WebSearch <<<"$S"'
check "settings.json keeps both top-level keys" 'grep -q outputStyle <<<"$S" && grep -q hooks <<<"$S"'
check "main checkout fast-forwarded" '[ "$(git -C "$DFW_REPO" rev-parse HEAD)" = "$(git -C "$DFW_REPO" rev-parse origin/main)" ]'
check "apply ran" '[ -f "$TMP/applied" ]'
check "worktrees removed" '[ ! -d "$A" ] && [ ! -d "$B" ] && [ ! -d "$C" ]'
check "branches deleted" '[ -z "$(git -C "$DFW_REPO" branch --list "df/*")" ]'
check "lock released" '[ ! -d "$DFW_LOCK" ]'

echo "a real text conflict stops, then resumes after resolution"
D="$("$DFW" start delta)"; E="$("$DFW" start epsilon)"
sed -i.bak 's/line two/line two (delta)/' "$D/zshrc" && rm "$D/zshrc.bak"
sed -i.bak 's/line two/line two (epsilon)/' "$E/zshrc" && rm "$E/zshrc.bak"
"$DFW" land delta -m "feat: delta" >/dev/null 2>&1
"$DFW" land epsilon -m "feat: epsilon" >/dev/null 2>&1; code=$?
check "conflict exits 3" '[ $code -eq 3 ]'
check "ls shows the conflict" '"$DFW" ls | grep -q "epsilon.*CONFLICT"'
printf 'line one\nline two (delta) (epsilon)\nline three\nalias g=git\n' > "$E/zshrc"
git -C "$E" add zshrc
"$DFW" land epsilon >/dev/null 2>&1; check "re-running land continues and lands" '[ $? -eq 0 ]'
check "resolution is on main" 'git -C "$DFW_REPO" show origin/main:zshrc | grep -q "(delta) (epsilon)"'

echo "guards"
F="$("$DFW" start phi)"; echo x > "$F/new"
"$DFW" land phi >/dev/null 2>&1; check "dirty worktree without -m refuses (exit 2)" '[ $? -eq 2 ]'
"$DFW" abort phi >/dev/null 2>&1; check "abort removes it" '[ ! -d "$F" ]'
"$DFW" start 'Bad Slug' >/dev/null 2>&1; check "bad slug rejected" '[ $? -eq 2 ]'
echo 'local edit' > "$DFW_REPO/untracked-note"
G="$("$DFW" start psi)"; echo y >> "$G/zshrc"
"$DFW" land psi -m "feat: psi" >/dev/null 2>&1; check "unrelated dirt in main checkout does not block" '[ $? -eq 0 ]'
check "...and the checkout still fast-forwarded" '[ "$(git -C "$DFW_REPO" rev-parse HEAD)" = "$(git -C "$DFW_REPO" rev-parse origin/main)" ]'

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
