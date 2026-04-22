#!/usr/bin/env bash
# RAM usage percentage.

TOTAL=$(sysctl -n hw.memsize)
PAGESIZE=$(sysctl -n hw.pagesize)

USED_PAGES=$(vm_stat | awk '
    /Pages active/ { gsub(/\./, ""); active = $3 }
    /Pages wired down/ { gsub(/\./, ""); wired = $4 }
    /Pages occupied by compressor/ { gsub(/\./, ""); compressor = $5 }
    END { print active + wired + compressor }
')
USED=$(( USED_PAGES * PAGESIZE ))
PCT=$(( USED * 100 / TOTAL ))

sketchybar --set "$NAME" icon="🧠" label="${PCT}%"
