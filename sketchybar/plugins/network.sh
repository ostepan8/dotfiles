#!/usr/bin/env bash
# Download / upload speed on the primary interface (en0).
# Stores previous byte counts in a cache file to compute delta.

CACHE=/tmp/sketchybar_net_cache
IFACE=en0

read BYTES_IN BYTES_OUT <<< "$(netstat -ibn | awk -v iface="$IFACE" '
    $1 == iface && $3 !~ /Link/ { print $7, $10; exit }
')"
[ -z "$BYTES_IN" ] && BYTES_IN=0
[ -z "$BYTES_OUT" ] && BYTES_OUT=0

NOW=$(date +%s)
IN_RATE=0
OUT_RATE=0

if [ -f "$CACHE" ]; then
    source "$CACHE"
    DELTA=$((NOW - OLD_TIME))
    if [ "$DELTA" -gt 0 ]; then
        IN_RATE=$(( (BYTES_IN - OLD_IN) / DELTA / 1024 ))
        OUT_RATE=$(( (BYTES_OUT - OLD_OUT) / DELTA / 1024 ))
        [ "$IN_RATE" -lt 0 ] && IN_RATE=0
        [ "$OUT_RATE" -lt 0 ] && OUT_RATE=0
    fi
fi

{
    echo "OLD_IN=$BYTES_IN"
    echo "OLD_OUT=$BYTES_OUT"
    echo "OLD_TIME=$NOW"
} > "$CACHE"

sketchybar --set "$NAME" label="↓${IN_RATE}K ↑${OUT_RATE}K"
