# tmuxctl/exec.sh — putting work into a pane: run, send, wait.

readonly TCTL_DEFAULT_TIMEOUT=120
readonly TCTL_WAIT_TIMEOUT=300

# Sleeps in tenths of a second, tightly at first and then lazily, so a command
# that finishes instantly is not charged a fixed polling delay while a ten
# minute build is not polled six thousand times.
tctl_poll_sleep() { # elapsed_tenths
    if [ "$1" -lt 30 ]; then sleep 0.05
    elif [ "$1" -lt 100 ]; then sleep 0.1
    else sleep 0.5; fi
}

# `run` deliberately does NOT scrape the screen for output. Screen scraping
# gets you the prompt, the echoed command, line wrapping at the pane width and
# any colour codes the program emitted. Redirecting to a file inside the pane's
# own shell gets you exactly what the command wrote, plus a real exit code.
cmd_run() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "run: needs a target and a command"
    local target="$1" timeout="$TCTL_DEFAULT_TIMEOUT" background=0
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) timeout="${2:?--timeout needs seconds}"; shift 2 ;;
            --bg|--background) background=1; shift ;;
            --) shift; break ;;
            -*) tctl_die "$TCTL_USAGE" "run: unknown option '$1'" ;;
            *) break ;;
        esac
    done
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "run: needs a command to run"

    local pane state cmd="$*"
    pane="$(tctl_pane "$target")" || exit $?
    state="$(tctl_state "$pane")"
    if [ "$state" != "idle" ]; then
        tctl_die "$TCTL_REFUSED" \
            "$(tctl_label "$pane") is $state (running '$(tctl_fmt "$pane" '#{pane_current_command}')'); a command sent here would be typed into that program. Use 'tmuxctl send' if that is what you meant."
    fi
    [ "$(tctl_fmt "$pane" '#{pane_in_mode}')" = "1" ] && tctl_die "$TCTL_REFUSED" \
        "$(tctl_label "$pane") is in copy mode; press q there or use 'tmuxctl send --keys q' first"

    local dir out rc
    dir="$(mktemp -d "${TMPDIR:-/tmp}/tmuxctl.XXXXXX")" || tctl_die 1 "run: could not create a temp dir"
    out="$dir/out"; rc="$dir/rc"

    # C-c abandons whatever half-typed line may be sitting at the prompt. The
    # pane is known idle, so there is no running process for it to interrupt.
    tm send-keys -t "$pane" C-c 2>/dev/null
    tm send-keys -t "$pane" -l "{ $cmd ; } > '$out' 2>&1 ; printf '%s' \$? > '$rc'" 2>/dev/null
    tm send-keys -t "$pane" Enter 2>/dev/null

    if [ "$background" = "1" ]; then
        if [ "${TCTL_JSON:-0}" = "1" ]; then
            printf '{"ok":true,"background":true,"target":"%s","output_file":"%s","exit_code_file":"%s"}\n' \
                "$(tctl_esc "$(tctl_label "$pane")")" "$(tctl_esc "$out")" "$(tctl_esc "$rc")"
        else
            printf 'started in %s\noutput:    %s\nexit code: %s\n' "$(tctl_label "$pane")" "$out" "$rc"
        fi
        return 0
    fi

    local tenths=0 limit=$(( timeout * 10 ))
    while [ ! -s "$rc" ]; do
        [ "$tenths" -ge "$limit" ] && break
        tctl_poll_sleep "$tenths"
        tenths=$((tenths + 1))
    done

    local code output
    output="$(cat "$out" 2>/dev/null)"
    if [ ! -s "$rc" ]; then
        if [ "${TCTL_JSON:-0}" = "1" ]; then
            printf '{"ok":false,"timed_out":true,"target":"%s","timeout_seconds":%s,"output":%s,"output_file":"%s","exit_code":%s}\n' \
                "$(tctl_esc "$(tctl_label "$pane")")" "$timeout" \
                "$(printf '%s' "$output" | tctl_esc_blob)" "$(tctl_esc "$out")" "$TCTL_TIMEOUT"
        else
            [ -n "$output" ] && printf '%s\n' "$output"
            tctl_note "timed out after ${timeout}s; the command is STILL RUNNING in $(tctl_label "$pane")."
            tctl_note "watch it with: tmuxctl read $(tctl_label "$pane")   stop it with: tmuxctl send $(tctl_label "$pane") --keys C-c"
        fi
        return "$TCTL_TIMEOUT"
    fi

    code="$(cat "$rc" 2>/dev/null)"
    rm -rf "$dir"
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":%s,"target":"%s","exit_code":%s,"output":%s}\n' \
            "$([ "${code:-1}" = "0" ] && echo true || echo false)" \
            "$(tctl_esc "$(tctl_label "$pane")")" "${code:-1}" \
            "$(printf '%s' "$output" | tctl_esc_blob)"
    else
        [ -n "$output" ] && printf '%s\n' "$output"
    fi
    return "${code:-1}"
}

# Unlike `run`, this types into whatever is there -- an editor, a REPL, an
# agent -- and never waits for or captures a result. It is the only way to talk
# to a pane that is busy on purpose.
cmd_send() {
    [ $# -ge 2 ] || tctl_die "$TCTL_USAGE" "send: needs a target and something to send"
    local target="$1" keys=0 enter=1 delay=""
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --keys) keys=1; shift ;;
            --no-enter) enter=0; shift ;;
            --delay) delay="${2:?--delay needs seconds}"; shift 2 ;;
            --) shift; break ;;
            -*) tctl_die "$TCTL_USAGE" "send: unknown option '$1'" ;;
            *) break ;;
        esac
    done
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "send: nothing to send"

    local pane
    pane="$(tctl_pane "$target")" || exit $?

    if [ "$keys" = "1" ]; then
        tm send-keys -t "$pane" "$@" || tctl_die 1 "send: tmux rejected those key names"
    else
        tm send-keys -t "$pane" -l "$*" || tctl_die 1 "send: tmux rejected that text"
        if [ "$enter" = "1" ]; then
            # A TUI that repaints on every keystroke (Claude Code, a REPL) can
            # still be redrawing when Enter lands, which submits a half-read
            # line. A beat between the text and the newline costs nothing and
            # removes the race.
            [ -z "$delay" ] && [ -n "$(tctl_agent_kind "$pane")" ] && delay=0.2
            [ -n "$delay" ] && sleep "$delay"
            tm send-keys -t "$pane" Enter
        fi
    fi

    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"target":"%s","sent":"%s"}\n' \
            "$(tctl_esc "$(tctl_label "$pane")")" "$(tctl_esc "$*")"
    fi
    return 0
}

cmd_wait() {
    [ $# -ge 1 ] || tctl_die "$TCTL_USAGE" "wait: needs a target"
    local target="$1" timeout="$TCTL_WAIT_TIMEOUT" pattern=""
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --timeout) timeout="${2:?--timeout needs seconds}"; shift 2 ;;
            --until) pattern="${2:?--until needs a pattern}"; shift 2 ;;
            --idle) shift ;;
            *) tctl_die "$TCTL_USAGE" "wait: unknown option '$1'" ;;
        esac
    done

    local pane tenths=0 limit=$(( timeout * 10 ))
    pane="$(tctl_pane "$target")" || exit $?

    while [ "$tenths" -lt "$limit" ]; do
        if [ -n "$pattern" ]; then
            tm capture-pane -p -J -t "$pane" 2>/dev/null | grep -qE -- "$pattern" && {
                tctl_wait_done "$pane" matched "$tenths"; return 0; }
        else
            case "$(tctl_state "$pane")" in
                idle|dead) tctl_wait_done "$pane" idle "$tenths"; return 0 ;;
            esac
        fi
        tctl_poll_sleep "$tenths"
        tenths=$((tenths + 1))
    done

    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":false,"timed_out":true,"target":"%s","timeout_seconds":%s,"exit_code":%s}\n' \
            "$(tctl_esc "$(tctl_label "$pane")")" "$timeout" "$TCTL_TIMEOUT"
    else
        tctl_note "wait: $(tctl_label "$pane") still busy after ${timeout}s"
    fi
    return "$TCTL_TIMEOUT"
}

tctl_wait_done() { # pane reason tenths
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":true,"target":"%s","reason":"%s","waited_seconds":%s,"state":"%s"}\n' \
            "$(tctl_esc "$(tctl_label "$1")")" "$2" "$(( $3 / 10 ))" "$(tctl_state "$1")"
    fi
}
