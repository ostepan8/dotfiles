#!/usr/bin/env bash
# macOS output volume + mute state (SF Symbols speaker icons).

if [ "$SENDER" = "volume_change" ]; then
    VOL="$INFO"
else
    VOL=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
fi

MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)

if [ "$MUTED" = "true" ] || [ "$VOL" = "0" ] || [ -z "$VOL" ]; then
    ICON="􀊠"             # speaker.slash
    COLOR=0xff928374
elif [ "$VOL" -ge 60 ]; then
    ICON="􀊩"             # speaker.wave.3
    COLOR=0xffebdbb2
elif [ "$VOL" -ge 30 ]; then
    ICON="􀊧"             # speaker.wave.2
    COLOR=0xffebdbb2
else
    ICON="􀊥"             # speaker.wave.1
    COLOR=0xffebdbb2
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="${VOL}%"
