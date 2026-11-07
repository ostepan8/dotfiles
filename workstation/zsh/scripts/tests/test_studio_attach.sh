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
  chmod +x "$SANDBOX/bin/ssh" "$SANDBOX/bin/fzf"
  : > "$SANDBOX/codes"
  export SANDBOX PATH="$SANDBOX/bin:$PATH" STUDIO_RETRY_SECONDS=0
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

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
