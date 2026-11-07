#!/usr/bin/env bash
# Offline checks of studio-attach. A fake ssh and a fake fzf stand in for the
# network and the picker, so this needs no Studio and no terminal.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="$HERE/../studio-attach"
FAILS=0

check() {  # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected [$2], got [$3]"
    FAILS=$((FAILS + 1))
  fi
}

setup() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
# Fake ssh: logs the remote command, then exits with the next code from the
# script of exit codes, or 0 when the script runs out.
printf '%s\n' "${@: -1}" >> "$SANDBOX/ssh.log"
case "${@: -1}" in
  *list-sessions*) [ -f "$SANDBOX/sessions" ] && cat "$SANDBOX/sessions" ;;
  *.sub/ports*) [ -f "$SANDBOX/ticket-ports" ] && cat "$SANDBOX/ticket-ports" ;;
esac
code=$(head -1 "$SANDBOX/codes" 2>/dev/null)
sed -i.bak 1d "$SANDBOX/codes" 2>/dev/null
exit "${code:-0}"
FAKE
  cat > "$SANDBOX/bin/fzf" <<'FAKE'
#!/usr/bin/env bash
cat > "$SANDBOX/fzf.input"
printf '%b' "$FZF_OUTPUT"
exit "${FZF_CODE:-0}"
FAKE
  cat > "$SANDBOX/bin/fake-forward" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$SANDBOX/forward.log"
exit "${FAKE_FORWARD_CODE:-0}"
FAKE
  chmod +x "$SANDBOX/bin/ssh" "$SANDBOX/bin/fzf" "$SANDBOX/bin/fake-forward"
  : > "$SANDBOX/codes"
  : > "$SANDBOX/forward.log"
  printf '# comment\nlisthalo 5173 3001\n' > "$SANDBOX/ports.conf"
  export SANDBOX PATH="$SANDBOX/bin:$PATH" STUDIO_RETRY_SECONDS=0
  export STUDIO_FORWARD_BIN="$SANDBOX/bin/fake-forward" STUDIO_PORTS_CONF="$SANDBOX/ports.conf"
  unset FAKE_FORWARD_CODE
}

run() {  # run <args...>; sets RC and OUT
  OUT="$(env -u TMUX "$CMD" "$@" 2>&1)"
  RC=$?
}

ssh_calls() { touch "$SANDBOX/ssh.log"; grep -c "${1:-.}" "$SANDBOX/ssh.log" || true; }

# A named session attaches or creates, with one reachability check first.
setup
run listhalo
check "named: exits 0" 0 "$RC"
check "named: uses new-session -A" 1 "$(ssh_calls 'tmux -u new-session -A -s listhalo')"

# A lost connection (255) retries. A clean detach (0) stops the loop.
setup
printf '0\n255\n255\n0\n' > "$SANDBOX/codes"
run listhalo
check "lost: exits 0 after reconnect" 0 "$RC"
check "lost: attached three times" 3 "$(ssh_calls 'new-session')"
check "lost: tells the user each time" 2 "$(printf '%s\n' "$OUT" | grep -c 'Reconnecting')"

# A remote failure that is not a lost connection does not retry.
setup
printf '0\n1\n' > "$SANDBOX/codes"
run listhalo
check "remote error: passes the code through" 1 "$RC"
check "remote error: no retry" 1 "$(ssh_calls 'new-session')"

# If the Studio is unreachable at the start, fail with a hint and do not loop.
setup
printf '255\n' > "$SANDBOX/codes"
run listhalo
check "unreachable: exits 1" 1 "$RC"
check "unreachable: no attach" 0 "$(ssh_calls 'new-session')"
check "unreachable: gives the fix" 1 "$(printf '%s\n' "$OUT" | grep -c 'kickstart')"

# The name goes into a remote shell, so reject anything unusual before ssh.
setup
run 'x; rm -rf ~'
check "bad name: exits 1" 1 "$RC"
check "bad name: never calls ssh" 0 "$(ssh_calls)"

# The picker shows the newest session first and attaches the selection.
setup
printf '100 old 1 \n300 new 2 attached\n' > "$SANDBOX/sessions"
export FZF_OUTPUT='\nnew 2w attached\n' FZF_CODE=0
run
check "picker: exits 0" 0 "$RC"
check "picker: newest first" "new" "$(head -1 "$SANDBOX/fzf.input" | awk '{print $1}')"
check "picker: attaches selection" 1 "$(ssh_calls 'new-session -A -s new')"

# A typed name with no match creates that session.
setup
printf '100 old 1 \n' > "$SANDBOX/sessions"
export FZF_OUTPUT='brandnew\n' FZF_CODE=1
run
check "picker new: exits 0" 0 "$RC"
check "picker new: creates it" 1 "$(ssh_calls 'new-session -A -s brandnew')"

# Esc in the picker does nothing.
setup
printf '100 old 1 \n' > "$SANDBOX/sessions"
export FZF_OUTPUT='' FZF_CODE=130
run
check "picker abort: no attach" 0 "$(ssh_calls 'new-session')"

# A session in the config opens its ports with no second terminal.
setup
run listhalo
check "ports: opened for the session" "--quiet 5173 3001" "$(cat "$SANDBOX/forward.log")"
check "ports: still attaches" 1 "$(ssh_calls 'new-session -A -s listhalo')"

setup
run ListHalo
check "ports: name matches in any case" "--quiet 5173 3001" "$(cat "$SANDBOX/forward.log")"

# A session with no ports opens nothing.
setup
run jarvis
check "ports: none for other sessions" 0 "$(wc -l < "$SANDBOX/forward.log" | tr -d ' ')"

# A ticket's web ports come from the ticket. Its database ports stay closed.
setup
printf 'PLATFORM_WEB_PORT=40230\nDEV_POSTGRES_PORT=40201\nDEV_GATEWAY_PORT=40280\nDEV_GATEWAY_ADMIN_PORT=40282\n' > "$SANDBOX/ticket-ports"
run subcon-670
check "ticket: web ports only" "--quiet 40230 40280 40282" "$(cat "$SANDBOX/forward.log")"

# The picker path opens ports too.
setup
printf '100 listhalo 1 \n' > "$SANDBOX/sessions"
export FZF_OUTPUT='\nlisthalo 1w\n' FZF_CODE=0
run
check "picker: opens ports" "--quiet 5173 3001" "$(cat "$SANDBOX/forward.log")"

# A failed tunnel never blocks the session.
setup
export FAKE_FORWARD_CODE=1
run listhalo
check "ports: failure still attaches" 1 "$(ssh_calls 'new-session -A -s listhalo')"
check "ports: failure exits 0" 0 "$RC"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
