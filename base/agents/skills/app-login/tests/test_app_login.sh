#!/usr/bin/env bash
# Offline checks of app-login's argument handling. The live path (docker, a browser,
# the vault) is exercised by hand; see SKILL.md.
set -uo pipefail
A="$(cd "$(dirname "$0")/.." && pwd)/app-login"
export APPLOGIN_CACHE; APPLOGIN_CACHE=$(mktemp -d); trap 'rm -rf "$APPLOGIN_CACHE"' EXIT
fail=0; n=0
check() { # name, want_exit, want_output_regex, args...
  local name="$1" want="$2" re="$3"; shift 3; n=$((n+1))
  local out; out=$(cd "$APPLOGIN_CACHE" && "$A" "$@" 2>&1); local rc=$?
  if [ $rc -ne "$want" ] || ! grep -qE "$re" <<<"$out"; then echo "FAIL $name: exit $rc (want $want): $out"; fail=1; fi
}
for f in "$A" "$(dirname "$A")/apps/"*.sh; do bash -n "$f" || { echo "FAIL syntax $f"; fail=1; }; done
node --check "$(dirname "$A")/browser.mjs" || { echo "FAIL syntax browser.mjs"; fail=1; }
check "lists recipes"        0 '^atlas$'                 --list
check "usage without args"   2 'usage|app-login <app>'
check "unknown app"          1 "no recipe for 'nope'"    nope shot home
check "prod is never up"     1 'never started'           atlas --prod up
check "no local copy yet"    1 'run: app-login atlas up' atlas shot home
check "eval needs js"        1 'needs a route and an expression' atlas eval home
check "run needs a script"   1 'run needs a script'      atlas run
check "up outside a repo"    1 'not in a git repo'       atlas up
[ $fail -eq 0 ] && echo "app-login: $n/$n passed" || exit 1
