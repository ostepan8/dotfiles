#!/usr/bin/env bash
# Now-playing for Spotify AND Apple Music, plus transport controls.
#   media.sh              → render (track label + control state; hides when idle)
#   media.sh prev|next|playpause  → act on the active player (wired to clicks)
#
# The single `media` item runs this on update_freq and drives its sibling
# control items (media.back / media.play / media.next) too, so only one script
# does the polling.

CONTROLS=(media.back media.play media.next)

# Echo "<App> <state>" for whichever player is most relevant: a *playing* app
# wins; otherwise a *paused* running app; else nothing.
active_player() {
    local app state
    for app in Spotify Music; do
        [ "$(osascript -e "application \"$app\" is running" 2>/dev/null)" = "true" ] || continue
        state=$(osascript -e "tell application \"$app\" to player state as string" 2>/dev/null)
        [ "$state" = "playing" ] && { echo "$app playing"; return; }
    done
    for app in Spotify Music; do
        [ "$(osascript -e "application \"$app\" is running" 2>/dev/null)" = "true" ] || continue
        state=$(osascript -e "tell application \"$app\" to player state as string" 2>/dev/null)
        [ "$state" = "paused" ] && { echo "$app paused"; return; }
    done
    echo ""
}

hide_all() {
    sketchybar --set media drawing=off
    local c
    for c in "${CONTROLS[@]}"; do sketchybar --set "$c" drawing=off; done
}

# --- Click actions ---------------------------------------------------------
case "${1:-}" in
    prev|next|playpause)
        read -r APP _ <<<"$(active_player)"
        [ -z "$APP" ] && exit 0
        case "$1" in
            prev)      osascript -e "tell application \"$APP\" to previous track" 2>/dev/null ;;
            next)      osascript -e "tell application \"$APP\" to next track"     2>/dev/null ;;
            playpause) osascript -e "tell application \"$APP\" to playpause"        2>/dev/null ;;
        esac
        # Fall through to re-render immediately after acting.
        ;;
esac

# --- Render ----------------------------------------------------------------
read -r APP STATE <<<"$(active_player)"
if [ -z "$APP" ]; then
    hide_all
    exit 0
fi

TRACK=$(osascript -e "tell application \"$APP\" to name of current track as string" 2>/dev/null)
ARTIST=$(osascript -e "tell application \"$APP\" to artist of current track as string" 2>/dev/null)
COMBINED="$ARTIST — $TRACK"
[ "$COMBINED" = " — " ] && COMBINED="$TRACK"
[ "${#COMBINED}" -gt 42 ] && COMBINED="${COMBINED:0:39}..."

# Play/pause glyph reflects state: ⏸ while playing, ▶ while paused.
if [ "$STATE" = "playing" ]; then PLAY_ICON="⏸"; else PLAY_ICON="▶"; fi

sketchybar --set media.back drawing=on icon="⏮" icon.color=0xffebdbb2 label.drawing=off \
    --set media.play drawing=on icon="$PLAY_ICON" icon.color=0xff98971a label.drawing=off \
    --set media.next drawing=on icon="⏭" icon.color=0xffebdbb2 label.drawing=off \
    --set media drawing=on icon.drawing=off label="$COMBINED" label.color=0xff689d6a
