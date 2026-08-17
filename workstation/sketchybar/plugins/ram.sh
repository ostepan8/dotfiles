#!/usr/bin/env bash
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
if [ "$PCT" -gt 85 ]; then COLOR=0xffcc241d
elif [ "$PCT" -gt 65 ]; then COLOR=0xffd79921
else COLOR=0xff689d6a
fi
sketchybar --set "$NAME" icon="RAM" icon.color="$COLOR" icon.font="SF Pro:Bold:11.0" label="${PCT}%"
