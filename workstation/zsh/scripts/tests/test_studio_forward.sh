#!/usr/bin/env bash
# Offline checks of studio-forward. A fake ssh and a fake nc stand in for the
# network, so this needs no Studio.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="$HERE/../studio-forward"
FAILS=0

check() {  # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected [$2], got [$3]"
    FAILS=$((FAILS + 1))
  fi
}

cleanup() {
  [ -n "${SANDBOX:-}" ] || return 0
  "$CMD" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

setup() {
  cleanup
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
# A tunnel (-N) logs its args, then lives for FAKE_TUNNEL_SECONDS. Anything else
# logs and exits with FAKE_SSH_CODE.
args="$*"
case " $args " in
  *" -N "*)
    echo "$args" >> "$SANDBOX/tunnels.log"
    exec sleep "${FAKE_TUNNEL_SECONDS:-30}"
    ;;
  *) echo "$args" >> "$SANDBOX/ssh.log"; exit "${FAKE_SSH_CODE:-0}" ;;
esac
FAKE
  cat > "$SANDBOX/bin/nc" <<'FAKE'
#!/usr/bin/env bash
# Open ports are one per line in $SANDBOX/open.
port="${*: -1}"
grep -qx "$port" "$SANDBOX/open" 2>/dev/null
FAKE
  chmod +x "$SANDBOX/bin/ssh" "$SANDBOX/bin/nc"
  export SANDBOX PATH="$SANDBOX/bin:$PATH" STUDIO_FORWARD_DIR="$SANDBOX/state" STUDIO_RETRY_SECONDS=0
  unset FAKE_SSH_CODE FAKE_TUNNEL_SECONDS
}

run() { OUT="$("$CMD" "$@" 2>&1)"; RC=$?; }
count_lines() { touch "$1"; wc -l < "$1" | tr -d ' '; }
# Give the background supervisor time to start ssh.
settle() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ "$(count_lines "$SANDBOX/tunnels.log")" -ge "${1:-1}" ] && return 0; sleep 0.2; done; }

# Starting a tunnel returns at once and binds only to the MacBook's loopback.
setup
run 3000
check "start: exits 0" 0 "$RC"
settle
check "start: loopback only" 1 "$(grep -c -- '-L 127.0.0.1:3000:localhost:3000' "$SANDBOX/tunnels.log")"
check "start: never prompts in the background" 1 "$(grep -c 'BatchMode=yes' "$SANDBOX/tunnels.log")"
check "start: fails if the port cannot bind" 1 "$(grep -c 'ExitOnForwardFailure=yes' "$SANDBOX/tunnels.log")"

# Several ports, and a different local port.
setup
run 3000 13000:5173
check "many: exits 0" 0 "$RC"
settle 2
check "many: second mapping" 1 "$(grep -c -- '-L 127.0.0.1:13000:localhost:5173' "$SANDBOX/tunnels.log")"

# Starting the same tunnel twice leaves one tunnel.
setup
run 3000; settle
run 3000
check "twice: exits 0" 0 "$RC"
check "twice: one tunnel" 1 "$(count_lines "$SANDBOX/tunnels.log")"

# A tunnel that dies comes back.
setup
export FAKE_TUNNEL_SECONDS=0
run 3000
settle 3
check "reconnect: reopened" yes "$([ "$(count_lines "$SANDBOX/tunnels.log")" -ge 3 ] && echo yes || echo no)"

# A busy local port is an error that names the fix.
setup
echo 3000 > "$SANDBOX/open"
run 3000
check "busy: exits 1" 1 "$RC"
check "busy: suggests another port" 1 "$(printf '%s\n' "$OUT" | grep -c '13000:3000')"
check "busy: no tunnel" 0 "$(count_lines "$SANDBOX/tunnels.log")"

# An unreachable Studio is an error, not a silent retry loop.
setup
export FAKE_SSH_CODE=255
run 3000
check "unreachable: exits 1" 1 "$RC"
check "unreachable: no tunnel" 0 "$(count_lines "$SANDBOX/tunnels.log")"

# Bad ports never reach ssh.
setup
for bad in abc 80 70000 '3000;id' '1:2:3'; do
  run "$bad"
  check "bad port [$bad]: exits 1" 1 "$RC"
done
check "bad port: never calls ssh" 0 "$(count_lines "$SANDBOX/ssh.log")"

# No arguments lists tunnels, and stop ends them.
setup
run 3000 5173; settle 2
run
check "list: shows both" 2 "$(printf '%s\n' "$OUT" | grep -cE '(3000|5173) ')"
run stop 3000
check "stop one: exits 0" 0 "$RC"
run
check "stop one: other stays" 1 "$(printf '%s\n' "$OUT" | grep -cE '^localhost:5173 ')"
check "stop one: gone" 0 "$(printf '%s\n' "$OUT" | grep -cE '^localhost:3000 ')"
run stop
run
check "stop all: none left" 1 "$(printf '%s\n' "$OUT" | grep -c 'No tunnels')"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
