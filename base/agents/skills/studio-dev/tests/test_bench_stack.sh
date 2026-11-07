#!/usr/bin/env bash
# Offline checks of bench-stack's env file, the part that keeps dev off real data.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="$HERE/../scripts/bench-stack"
FAILS=0

check() {  # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1: expected [$2], got [$3]"
    FAILS=$((FAILS + 1))
  fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bench-runner"
cat > "$SANDBOX/bench-runner/.env" <<'ENV'
REDIS_URL=rediss://default:real-secret@prod.example.io:6379
BENCH_REDIS_PREFIX=prod
BENCH_STORE_BACKEND=redis
R2_ACCESS_KEY_ID=real-r2-id
R2_SECRET_ACCESS_KEY=real-r2-secret
R2_BUCKET=real-bucket
PUBLIC_PROXY_BASE_URL=https://prod.example.io
E2B_API_KEY=runner-e2b
DAYTONA_API_KEY=runner-daytona
SUBCONSCIOUS_API_KEY=runner-sub
ENV
export BENCH_DIR="$SANDBOX/bench-runner"
ENVFILE="$SANDBOX/.dev/bench.env"
has() { grep -c -- "$1" "$ENVFILE" || true; }

# The default holds no secrets at all, and Redis is local.
"$CMD" __write-env
check "default: local Redis" 1 "$(has '^REDIS_URL=redis://127.0.0.1:')"
check "default: own Redis prefix" 1 "$(has '^BENCH_REDIS_PREFIX=dev')"
check "default: no remote Redis" 0 "$(has 'prod.example')"
check "default: no R2" 0 "$(has '^R2_')"
check "default: no runner keys" 0 "$(has 'runner-')"
check "default: private file" 600 "$(stat -f %Lp "$ENVFILE")"

# --keys adds runner keys only, never Redis, R2 or the public proxy.
"$CMD" __write-env --keys
check "keys: adds E2B" 1 "$(has '^E2B_API_KEY=runner-e2b')"
check "keys: adds Subconscious" 1 "$(has '^SUBCONSCIOUS_API_KEY=runner-sub')"
check "keys: still local Redis" 1 "$(has '^REDIS_URL=redis://127.0.0.1:')"
check "keys: no remote Redis or proxy" 0 "$(has 'prod.example')"
check "keys: no R2" 0 "$(has '^R2_')"

# Unknown commands fail clearly.
OUT="$("$CMD" nonsense 2>&1)"; RC=$?
check "usage: exits 1" 1 "$RC"
check "usage: names the commands" 1 "$(printf '%s\n' "$OUT" | grep -c 'start')"

[ "$FAILS" -eq 0 ] && echo "all passed" || { echo "$FAILS failed"; exit 1; }
