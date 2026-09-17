# tmuxctl/inspect.sh — read-only views: ls, tree, status, find, read, grep, agents.

readonly TCTL_PANE_FMT='#{pane_id}	#{session_name}	#{window_index}	#{pane_index}	#{window_name}	#{pane_current_command}	#{pane_current_path}	#{pane_pid}	#{pane_dead}	#{pane_title}'

# Emits one JSON object per pane from a TCTL_PANE_FMT line.
tctl_pane_json() { # the tab-separated fields, already split by the caller
    local id="$1" sess="$2" win="$3" pane="$4" wname="$5" cmd="$6" path="$7" pid="$8" dead="$9"
    shift 9
    local title="$1" state agent
    state="$(tctl_state_of "$cmd" "$dead")"
    agent="$(tctl_agent_kind_of "$cmd" "$title")"
    printf '{"type":"pane","target":"%s:%s.%s","pane_id":"%s","session":"%s","window":%s,"window_name":"%s","pane":%s,"command":"%s","state":"%s","agent":"%s","path":"%s","pid":%s,"title":"%s"}' \
        "$(tctl_esc "$sess")" "$win" "$pane" "$id" "$(tctl_esc "$sess")" "$win" \
        "$(tctl_esc "$wname")" "$pane" "$(tctl_esc "$cmd")" "$state" "$agent" \
        "$(tctl_esc "$path")" "${pid:-0}" "$(tctl_esc "$title")"
}

cmd_ls() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --panes|--tree) cmd_tree; return $? ;;
            *) tctl_die "$TCTL_USAGE" "ls: unknown option '$arg'" ;;
        esac
    done

    tctl_server_up || { tctl_empty sessions; return 0; }

    [ "${TCTL_JSON:-0}" = "1" ] && printf '{"ok":true,"sessions":['
    [ "${TCTL_JSON:-0}" = "1" ] || printf '%-28s %3s %5s %-5s %-4s %-6s %s\n' \
        SESSION WIN PANES STATE ATT IDLE PATH

    awk -v json="${TCTL_JSON:-0}" -v now="$(date +%s)" -f "$TCTL_LIB/agg.awk" \
        <(tm list-panes -a -F '#{session_name}	#{pane_current_command}	#{pane_dead}' 2>/dev/null) \
        <(tm list-sessions -F '#{session_name}	#{session_windows}	#{session_attached}	#{session_activity}	#{session_path}' 2>/dev/null)

    [ "${TCTL_JSON:-0}" = "1" ] && printf ']}\n'
    return 0
}

tctl_empty() { # key
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"%s":[]}\n' "$1"
    else
        printf 'no tmux server running\n'
    fi
}

cmd_tree() {
    tctl_server_up || { tctl_empty panes; return 0; }

    local first=1 id sess win pane wname cmd path pid dead title state agent
    [ "${TCTL_JSON:-0}" = "1" ] && printf '{"ok":true,"panes":['
    while IFS=$'\t' read -r id sess win pane wname cmd path pid dead title; do
        [ -n "$id" ] || continue
        if [ "${TCTL_JSON:-0}" = "1" ]; then
            [ "$first" = "1" ] || printf ','
            first=0
            tctl_pane_json "$id" "$sess" "$win" "$pane" "$wname" "$cmd" "$path" "$pid" "$dead" "$title"
        else
            state="$(tctl_state_of "$cmd" "$dead")"
            agent="$(tctl_agent_kind_of "$cmd" "$title")"
            printf '%-34s %-6s %-14s %-8s %s\n' \
                "$sess:$win.$pane" "$state" "$cmd" "${agent:--}" "$title"
        fi
    done <<TREEEOF
$(tm list-panes -a -F "$TCTL_PANE_FMT" 2>/dev/null)
TREEEOF
    [ "${TCTL_JSON:-0}" = "1" ] && printf ']}\n'
    return 0
}

cmd_status() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "status: needs a target"
    local pane line
    pane="$(tctl_pane "$1")" || exit $?
    line="$(tm list-panes -a -F "$TCTL_PANE_FMT" 2>/dev/null | grep -F "$pane	")"
    [ -n "$line" ] || tctl_die "$TCTL_NOTFOUND" "pane $pane vanished"

    local id sess win p wname cmd path pid dead title
    IFS=$'\t' read -r id sess win p wname cmd path pid dead title <<STEOF
$line
STEOF

    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,'
        tctl_pane_json "$id" "$sess" "$win" "$p" "$wname" "$cmd" "$path" "$pid" "$dead" "$title" \
            | sed 's/^{//; s/}$//'
        printf ',"agent_state":"%s"}\n' "$(tctl_agent_state "$id")"
    else
        printf 'target    %s:%s.%s (%s)\n' "$sess" "$win" "$p" "$id"
        printf 'state     %s\n' "$(tctl_state "$id")"
        printf 'command   %s\n' "$cmd"
        printf 'path      %s\n' "$path"
        printf 'pid       %s\n' "$pid"
        printf 'title     %s\n' "$title"
        local agent
        agent="$(tctl_agent_kind_of "$cmd" "$title")"
        [ -n "$agent" ] && printf 'agent     %s (%s)\n' "$agent" "$(tctl_agent_state "$id")"
    fi
    return 0
}

cmd_find() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "find: needs a query"
    local pane
    pane="$(tctl_pane "$1")" || exit $?
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"target":"%s","pane_id":"%s"}\n' "$(tctl_esc "$(tctl_label "$pane")")" "$pane"
    else
        printf '%s\t%s\n' "$(tctl_label "$pane")" "$pane"
    fi
    return 0
}

cmd_read() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "read: needs a target"
    local target="$1" lines="" history=0
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--lines) lines="${2:?-n needs a number}"; shift 2 ;;
            --history|--all) history=1; shift ;;
            *) tctl_die "$TCTL_USAGE" "read: unknown option '$1'" ;;
        esac
    done

    local pane text
    pane="$(tctl_pane "$target")" || exit $?
    if [ "$history" = "1" ]; then
        text="$(tm capture-pane -p -J -S - -t "$pane" 2>/dev/null)"
    else
        text="$(tm capture-pane -p -J -t "$pane" 2>/dev/null)"
    fi
    # capture-pane pads to the pane height; trailing blank lines are noise.
    text="$(printf '%s\n' "$text" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"
    [ -n "$lines" ] && text="$(printf '%s\n' "$text" | tail -n "$lines")"

    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"target":"%s","state":"%s","content":%s}\n' \
            "$(tctl_esc "$(tctl_label "$pane")")" "$(tctl_state "$pane")" \
            "$(printf '%s\n' "$text" | tctl_esc_blob)"
    else
        printf '%s\n' "$text"
    fi
    return 0
}

cmd_grep() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "grep: needs a pattern"
    local pattern="$1" history=0 icase="" scope=""
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --history|--all) history=1; shift ;;
            -i) icase="-i"; shift ;;
            -t|--target) scope="${2:?-t needs a target}"; shift 2 ;;
            *) tctl_die "$TCTL_USAGE" "grep: unknown option '$1'" ;;
        esac
    done

    # -s would widen a window or pane target back out to its whole session,
    # silently searching more than was asked for.
    local listing hits=0 id label text match
    if [ -n "$scope" ]; then
        case "$(tctl_kind "$scope")" in
            session) listing="$(tm list-panes -s -t "$(tctl_canonical "$scope")" -F '#{pane_id}' 2>/dev/null)" ;;
            window)  listing="$(tm list-panes -t "$(tctl_canonical "$scope")" -F '#{pane_id}' 2>/dev/null)" ;;
            pane)    listing="$(tctl_pane "$scope")" || exit $? ;;
        esac
    else
        listing="$(tm list-panes -a -F '#{pane_id}' 2>/dev/null)"
    fi

    [ "${TCTL_JSON:-0}" = "1" ] && printf '{"ok":true,"matches":['
    local first=1
    for id in $listing; do
        if [ "$history" = "1" ]; then
            text="$(tm capture-pane -p -J -S - -t "$id" 2>/dev/null)"
        else
            text="$(tm capture-pane -p -J -t "$id" 2>/dev/null)"
        fi
        match="$(printf '%s\n' "$text" | grep $icase -F -- "$pattern")" || continue
        [ -n "$match" ] || continue
        hits=$((hits + 1))
        label="$(tctl_label "$id")"
        if [ "${TCTL_JSON:-0}" = "1" ]; then
            [ "$first" = "1" ] || printf ','
            first=0
            printf '{"target":"%s","pane_id":"%s","lines":%s}' \
                "$(tctl_esc "$label")" "$id" "$(printf '%s\n' "$match" | tctl_esc_blob)"
        else
            printf '\033[1m%s\033[0m (%s)\n' "$label" "$id"
            printf '%s\n' "$match" | sed 's/^/    /'
        fi
    done
    [ "${TCTL_JSON:-0}" = "1" ] && printf ']}\n'

    [ "$hits" -gt 0 ] && return 0
    [ "${TCTL_JSON:-0}" = "1" ] || tctl_note "no pane matched '$pattern'"
    return "$TCTL_NOMATCH"
}

# The reason this tool exists on a machine running dozens of agent panes: one
# call that answers "which agents are alive, which are stuck waiting on me, and
# which of these Claude-looking panes are just restored screenshots".
cmd_agents() {
    local include_stale=0 arg
    for arg in "$@"; do
        case "$arg" in
            --stale|--all) include_stale=1 ;;
            *) tctl_die "$TCTL_USAGE" "agents: unknown option '$arg'" ;;
        esac
    done
    tctl_server_up || { tctl_empty agents; return 0; }

    local first=1 printed=0 id sess win pane wname cmd path pid dead title kind state
    [ "${TCTL_JSON:-0}" = "1" ] && printf '{"ok":true,"agents":['
    while IFS=$'\t' read -r id sess win pane wname cmd path pid dead title; do
        [ -n "$id" ] || continue
        kind="$(tctl_agent_kind_of "$cmd" "$title")"
        [ -n "$kind" ] || continue
        [ "$kind" = "stale" ] && [ "$include_stale" = "0" ] && continue
        if [ "$kind" = "stale" ]; then state=stale; else state="$(tctl_agent_state_of "$title")"; fi
        if [ "${TCTL_JSON:-0}" = "1" ]; then
            [ "$first" = "1" ] || printf ','
            first=0
            printf '{"target":"%s:%s.%s","pane_id":"%s","session":"%s","kind":"%s","state":"%s","version":"%s","path":"%s","title":"%s"}' \
                "$(tctl_esc "$sess")" "$win" "$pane" "$id" "$(tctl_esc "$sess")" "$kind" "$state" \
                "$(tctl_esc "$cmd")" "$(tctl_esc "$path")" "$(tctl_esc "$title")"
        else
            [ "$printed" = "0" ] && printf '%-34s %-8s %-9s %s\n' TARGET STATE VERSION TITLE
            printed=1
            printf '%-34s %-8s %-9s %s\n' "$sess:$win.$pane" "$state" "$cmd" "$title"
        fi
    done <<AGEOF
$(tm list-panes -a -F "$TCTL_PANE_FMT" 2>/dev/null)
AGEOF
    [ "${TCTL_JSON:-0}" = "1" ] && printf ']}\n'
    [ "${TCTL_JSON:-0}" = "1" ] || [ "$printed" = "1" ] || printf 'no agent panes\n'
    return 0
}
