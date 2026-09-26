#!/usr/bin/env bash
# Feeds synthetic transcripts to the Stop hooks and checks exit code + stderr.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/base/claude/hooks/verify-gate.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0; n=0

# transcript <tool_use JSON>... → path. First line is the user prompt.
transcript() {
  local f="$TMP/t$RANDOM.jsonl" final="$1"; shift
  echo '{"type":"user","message":{"content":"do it"}}' > "$f"
  for tu in "$@"; do
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use",%s}]}}\n' "$tu" >> "$f"
  done
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$final" >> "$f"
  echo "$f"
}

# expect <name> <want_exit> <want_stderr_regex|""> <active> <transcript>
expect() {
  n=$((n+1))
  local err; err=$(printf '{"transcript_path":"%s","stop_hook_active":%s}' "$5" "$4" | "$HOOK" 2>&1 >/dev/null); local rc=$?
  if [[ $rc -ne $2 ]] || { [[ -n $3 ]] && ! grep -qE "$3" <<<"$err"; }; then
    echo "FAIL $1: exit $rc (want $2), stderr: ${err:-<empty>}"; fail=1
  fi
}

EDIT='"name":"Bash","input":{"command":"cat > /x/watch.sh <<EOF\nhi\nEOF"}'
expect "unchecked edit blocks with a reason" 2 "Not done yet: you edited watch.sh" false "$(transcript done "$EDIT")"
expect "never blocks twice" 0 "" true "$(transcript done "$EDIT")"
expect "unverified admission passes" 0 "" false "$(transcript "unverified: needs a device" "$EDIT")"
expect "running the edited script by path counts" 0 "" false \
  "$(transcript done "$EDIT" '"name":"Bash","input":{"command":"~/runs/x/watch.sh foo"}')"
expect "go test counts" 0 "" false "$(transcript done "$EDIT" '"name":"Bash","input":{"command":"go test ./..."}')"
UI='"name":"Edit","input":{"file_path":"/x/App.tsx"}'
expect "UI edit needs a visual check" 2 "screenshot" false \
  "$(transcript done "$UI" '"name":"Bash","input":{"command":"npm run build"}')"
expect "copying the edited file is not a check" 2 "Not done yet" false \
  "$(transcript done "$EDIT" '"name":"Bash","input":{"command":"cp /x/watch.sh /y/"}')"
expect "no edits passes" 0 "" false "$(transcript done)"

[[ $fail -eq 0 ]] && echo "hooks: $n/$n passed" || exit 1
