# tmuxctl/lifecycle.sh — creating and destroying: new, window, split, kill, rename.

# Create-or-attach, never create-a-duplicate. Asking for a session that already
# exists is a no-op that still exits 0, so a caller can open with `new` without
# first checking whether it needs to.
cmd_new() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "new: needs a session name"
    local name="$1" cwd="" command="" attach=0
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --cwd|-c) cwd="${2:?--cwd needs a directory}"; shift 2 ;;
            --cmd)    command="${2:?--cmd needs a command}"; shift 2 ;;
            --attach) attach=1; shift ;;
            *) tctl_die "$TCTL_USAGE" "new: unknown option '$1'" ;;
        esac
    done

    local existed=0
    if tm has-session -t "=$name" 2>/dev/null; then
        existed=1
    else
        [ -n "$cwd" ] && [ ! -d "$cwd" ] && tctl_die "$TCTL_USAGE" "new: no such directory '$cwd'"
        if [ -n "$command" ]; then
            tm new-session -d -s "$name" ${cwd:+-c "$cwd"} "$command" \
                || tctl_die 1 "new: tmux refused to create '$name'"
        else
            tm new-session -d -s "$name" ${cwd:+-c "$cwd"} \
                || tctl_die 1 "new: tmux refused to create '$name'"
        fi
    fi

    local pane
    pane="$(tm display-message -p -t "=$name:" '#{pane_id}')"
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"session":"%s","target":"%s","pane_id":"%s","created":%s}\n' \
            "$(tctl_esc "$name")" "$(tctl_esc "$(tctl_label "$pane")")" "$pane" \
            "$([ "$existed" = "1" ] && echo false || echo true)"
    else
        printf '%s\t%s\t%s\n' "$(tctl_label "$pane")" "$pane" \
            "$([ "$existed" = "1" ] && echo existing || echo created)"
    fi

    # Attaching takes over this terminal, so it is opt-in and pointless for a
    # caller that is not a human at a keyboard.
    [ "$attach" = "1" ] && exec tm attach-session -t "=$name"
    return 0
}

cmd_window() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "window: needs a session target"
    local target="$1" name="" cwd="" command=""
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --name|-n) name="${2:?--name needs a value}"; shift 2 ;;
            --cwd|-c)  cwd="${2:?--cwd needs a directory}"; shift 2 ;;
            --cmd)     command="${2:?--cmd needs a command}"; shift 2 ;;
            *) tctl_die "$TCTL_USAGE" "window: unknown option '$1'" ;;
        esac
    done

    local canon pane
    canon="$(tctl_canonical "$target")" || exit $?
    # -P -F reports the pane that was just created. Asking the session for its
    # active pane afterwards does not work: -d means the new window is never
    # selected, so that question returns whichever window was already in front.
    pane="$(tm new-window -d -P -F '#{pane_id}' -t "$canon" \
        ${name:+-n "$name"} ${cwd:+-c "$cwd"} ${command:+"$command"})" \
        || tctl_die 1 "window: tmux refused to create a window in '$target'"
    tctl_report_created "$pane"
}

cmd_split() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "split: needs a target"
    local target="$1" dir="-h" cwd="" command=""
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--horizontal) dir="-h"; shift ;;
            -v|--vertical)   dir="-v"; shift ;;
            --cwd|-c) cwd="${2:?--cwd needs a directory}"; shift 2 ;;
            --cmd)    command="${2:?--cmd needs a command}"; shift 2 ;;
            *) tctl_die "$TCTL_USAGE" "split: unknown option '$1'" ;;
        esac
    done

    local pane new
    pane="$(tctl_pane "$target")" || exit $?
    new="$(tm split-window -d -P -F '#{pane_id}' "$dir" -t "$pane" ${cwd:+-c "$cwd"} ${command:+"$command"})" \
        || tctl_die 1 "split: tmux refused to split '$target'"
    tctl_report_created "$new"
}

tctl_report_created() { # pane_id
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"target":"%s","pane_id":"%s","created":true}\n' \
            "$(tctl_esc "$(tctl_label "$1")")" "$1"
    else
        printf '%s\t%s\tcreated\n' "$(tctl_label "$1")" "$1"
    fi
    return 0
}

# Killing is the one irreversible thing here: tmux-resurrect restores the SHAPE
# of a session, not the processes inside it, so a session killed by mistake is
# gone. Hence the refusal on anything busy or attached unless --force is
# explicit.
cmd_kill() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "kill: needs a target"
    local target="$1" force=0
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f) force=1; shift ;;
            *) tctl_die "$TCTL_USAGE" "kill: unknown option '$1'" ;;
        esac
    done

    local kind canon pane label busy attached
    kind="$(tctl_kind "$target")"
    canon="$(tctl_canonical "$target")" || exit $?
    pane="$(tctl_pane "$target")" || exit $?
    label="$(tctl_label "$pane")"

    if [ "$force" = "0" ]; then
        busy="$(tm list-panes -s -t "$canon" -F '#{pane_current_command}' 2>/dev/null \
            | grep -vcE "^($TCTL_SHELLS)$")"
        [ "$kind" = "pane" ] && { busy=0; [ "$(tctl_state "$pane")" = "busy" ] && busy=1; }
        [ "${busy:-0}" -gt 0 ] && tctl_die "$TCTL_REFUSED" \
            "$label has $busy pane(s) running something; nothing restores a killed process. Re-run with --force if you are sure."
        attached="$(tctl_fmt "$pane" '#{session_attached}')"
        [ "${attached:-0}" != "0" ] && tctl_die "$TCTL_REFUSED" \
            "$label is attached to a client. Re-run with --force if you are sure."
    fi

    case "$kind" in
        session) tm kill-session -t "$canon" ;;
        window)  tm kill-window  -t "$canon" ;;
        pane)    tm kill-pane    -t "$pane"  ;;
    esac || tctl_die 1 "kill: tmux refused to kill '$target'"

    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"killed":"%s","kind":"%s"}\n' "$(tctl_esc "$label")" "$kind"
    else
        printf 'killed %s (%s)\n' "$label" "$kind"
    fi
    return 0
}

cmd_rename() {
    [ $# -ge 2 ] || tctl_die "$TCTL_USAGE" "rename: needs a target and a new name"
    local target="$1" newname="$2" kind canon
    kind="$(tctl_kind "$target")"
    canon="$(tctl_canonical "$target")" || exit $?

    case "$kind" in
        session) tm rename-session -t "$canon" "$newname" ;;
        *)       tm rename-window  -t "$canon" "$newname" ;;
    esac || tctl_die 1 "rename: tmux refused to rename '$target'"

    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"renamed":"%s","to":"%s","kind":"%s"}\n' \
            "$(tctl_esc "$target")" "$(tctl_esc "$newname")" "$kind"
    else
        printf 'renamed %s -> %s (%s)\n' "$target" "$newname" "$kind"
    fi
    return 0
}
