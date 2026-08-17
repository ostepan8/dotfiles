#!/usr/bin/env bash
# Weather via wttr.in — no API key; location auto-detected by IP.
# Text-icon style ("WX") to match the CPU/RAM/TIME items. Temp colored by value.
# Click opens the macOS Weather app.

RAW=$(curl -s --max-time 8 'https://wttr.in/?format=%t' 2>/dev/null)

# wttr returns e.g. "+77°F". On any network hiccup it returns empty or an HTML
# error page — in that case leave the previously-shown value untouched rather
# than flashing junk into the bar.
case "$RAW" in
    *°*) ;;                        # looks like a temperature
    *) exit 0 ;;                   # garbage / offline — keep last value
esac

TEMP="${RAW#+}"                    # strip wttr's leading + on positive temps
NUM=$(printf '%s' "$TEMP" | grep -Eo '\-?[0-9]+' | head -1)

COLOR=0xff689d6a                   # green — comfortable
if [ -n "$NUM" ]; then
    if   [ "$NUM" -ge 85 ]; then COLOR=0xffcc241d   # red — hot
    elif [ "$NUM" -ge 60 ]; then COLOR=0xffd79921   # yellow — warm
    elif [ "$NUM" -le 32 ]; then COLOR=0xff458588   # blue — freezing
    fi
fi

sketchybar --set "$NAME" \
    icon="WX" \
    icon.font="SF Pro:Bold:11.0" \
    icon.color=0xffb16286 \
    label="$TEMP" \
    label.color="$COLOR" \
    drawing=on
