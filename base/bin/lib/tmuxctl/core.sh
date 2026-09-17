# tmuxctl/core.sh — target resolution, pane state, JSON emission.
#
# Everything here is shared by the verb modules. Two ideas carry most of the
# weight:
#
#   1. A TARGET is resolved to a pane id (%N) exactly once, at the top of every
#      command. Downstream code never re-parses user input, so "t-alpha",
#      "t-alpha:2.1" and "%37" behave identically everywhere.
#
#   2. A pane is BUSY when its foreground process is not a shell. This is the
#      guard that stops `run` from typing a shell command into a pane that is
#      running an editor or an agent, where it would be interpreted as
#      keystrokes rather than a command.

# Exit codes. Documented in `tmuxctl schema` and relied on by the tests.
readonly TCTL_OK=0
readonly TCTL_NOMATCH=1
readonly TCTL_USAGE=2
readonly TCTL_REFUSED=3
readonly TCTL_NOTFOUND=4
readonly TCTL_TIMEOUT=5

# Foreground processes that mean "an idle shell waiting at a prompt".
readonly TCTL_SHELLS='zsh|bash|sh|fish|dash|ksh|tcsh|csh|login'

# --- tmux plumbing ---------------------------------------------------------

# All tmux calls go through this so the test suite can point the whole tool at
# a throwaway server instead of the one holding real work.
tm() {
    if [ -n "${TMUXCTL_SOCKET:-}" ]; then
        command tmux -L "$TMUXCTL_SOCKET" "$@"
    else
        command tmux "$@"
    fi
}

tctl_server_up() { tm info >/dev/null 2>&1; }

# --- output ----------------------------------------------------------------

# Errors go to stderr in BOTH modes, deliberately. Most resolution happens
# inside a command substitution (pane="$(tctl_pane ...)"), and anything written
# to stdout from in there is captured as the value rather than shown -- a JSON
# error printed to stdout disappeared completely, leaving only an exit code.
# stderr is never captured, so the message always survives.
tctl_die() { # code message...
    local code="$1"; shift
    if [ "${TCTL_JSON:-0}" = "1" ]; then
        printf '{"ok":false,"error":"%s","exit_code":%s}\n' "$(tctl_esc "$*")" "$code" >&2
    else
        printf 'tmuxctl: %s\n' "$*" >&2
    fi
    exit "$code"
}

tctl_note() { [ "${TCTL_JSON:-0}" = "1" ] || printf '%s\n' "$*" >&2; }

# JSON string escaping, without shelling out once per field: at ~100 panes a
# subprocess per string was the whole runtime of `ls`.
tctl_esc() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//	/\\t}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
}

# Big or arbitrary blobs (captured pane content) go through python, where
# correctness matters more than the fork.
tctl_esc_blob() {
    python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.read()))'
}

# --- target resolution -----------------------------------------------------

# Splits a target into its tmux-canonical form. Session names are matched
# exactly first (=name), then by unique substring -- an ambiguous substring is
# an error rather than a guess, because guessing wrong here means acting on
# somebody else's session.
tctl_canonical() { # target -> canonical tmux target
    local t="$1" sess rest matches count

    case "$t" in
        ''|.|current)
            [ -n "${TMUX_PANE:-}" ] || tctl_die "$TCTL_NOTFOUND" \
                "no target given and not running inside tmux"
            printf '%s' "$TMUX_PANE"
            return 0 ;;
        %*|@*|\$*)
            printf '%s' "$t"
            return 0 ;;
    esac

    case "$t" in
        *:*) sess="${t%%:*}"; rest=":${t#*:}" ;;
        *)   sess="$t"; rest="" ;;
    esac

    if tm has-session -t "=$sess" 2>/dev/null; then
        printf '=%s%s' "$sess" "$rest"
        return 0
    fi

    matches="$(tm list-sessions -F '#{session_name}' 2>/dev/null | grep -F -- "$sess")"
    count="$(printf '%s' "$matches" | grep -c . )"
    [ "$count" -eq 0 ] && tctl_die "$TCTL_NOTFOUND" "no session matching '$sess'"
    [ "$count" -gt 1 ] && tctl_die "$TCTL_NOTFOUND" \
        "'$sess' is ambiguous: $(printf '%s' "$matches" | tr '\n' ' ')"

    printf '=%s%s' "$matches" "$rest"
}

# The pane a target points at: for a session or window target that is the
# ACTIVE pane, which is what a human means by "that session".
tctl_pane() { # target -> %pane_id
    local canon pane
    canon="$(tctl_canonical "$1")" || exit $?
    # A bare "=name" does not resolve as a target-PANE -- tmux only honours the
    # exact-match prefix once the target carries a window separator, so
    # display-message quietly returns nothing. "=name:" means the same session
    # and does resolve.
    case "$canon" in
        %*|@*|\$*|*:*) ;;
        *) canon="$canon:" ;;
    esac
    pane="$(tm display-message -p -t "$canon" '#{pane_id}' 2>/dev/null)"
    [ -n "$pane" ] || tctl_die "$TCTL_NOTFOUND" "no pane at target '$1'"
    printf '%s' "$pane"
}

# What level of the tree the user named, so `kill` knows whether they meant a
# pane, a window or a whole session.
tctl_kind() { # target -> session|window|pane
    case "$1" in
        %*) printf 'pane' ;;
        @*) printf 'window' ;;
        \$*) printf 'session' ;;
        .|current|'') printf 'pane' ;;
        *.*) printf 'pane' ;;
        *:*) printf 'window' ;;
        *) printf 'session' ;;
    esac
}

tctl_fmt() { # pane_id format -> value
    tm display-message -p -t "$1" "$2" 2>/dev/null
}

# --- pane state ------------------------------------------------------------

# These four take values the caller ALREADY has, so a loop over a hundred panes
# does not fork tmux five more times per pane -- the difference between
# `tmuxctl agents` taking 1.4s and taking 0.05s on this machine.
#
# idle: a shell at a prompt, safe to send a command to.
# busy: something else has the foreground -- an editor, a build, an agent.
# dead: the process exited and the pane is being kept around.
tctl_is_shell() {
    case "$1" in
        zsh|bash|sh|fish|dash|ksh|tcsh|csh|login) return 0 ;;
        *) return 1 ;;
    esac
}

tctl_state_of() { # command dead -> idle|busy|dead
    [ "${2:-0}" = "1" ] && { printf 'dead'; return 0; }
    if tctl_is_shell "$1"; then printf 'idle'; else printf 'busy'; fi
}

# Claude Code compiles to a binary named after its version, so a live agent
# pane reports a foreground command like "2.1.274" rather than anything
# recognisable. A pane showing a Claude title while its command is a plain
# shell is the opposite case: a layout restored by tmux-resurrect, with the old
# screen contents painted back but no agent behind them -- worth reporting
# separately, because sending to one of those types into a bare shell.
tctl_agent_kind_of() { # command title -> claude|stale|''
    [ "$1" = "claude" ] && { printf 'claude'; return 0; }
    if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf 'claude'; return 0; fi
    case "$2" in
        *Claude*|*✳*) printf 'stale' ;;
    esac
}

# Claude Code writes its state into the pane title, which is the only status
# signal available from outside the process.
tctl_agent_state_of() { # title -> working|waiting|ready
    case "$1" in
        *"Action Required"*|*"[ ! ]"*) printf 'waiting' ;;
        *✳*) printf 'working' ;;
        *) printf 'ready' ;;
    esac
}

# Single-pane conveniences, one tmux call each.
tctl_state() { # pane_id -> idle|busy|dead
    local d
    d="$(tctl_fmt "$1" '#{pane_current_command}	#{pane_dead}')"
    tctl_state_of "${d%%	*}" "${d##*	}"
}

tctl_agent_kind() { # pane_id -> claude|stale|''
    local d
    d="$(tctl_fmt "$1" '#{pane_current_command}	#{pane_title}')"
    tctl_agent_kind_of "${d%%	*}" "${d#*	}"
}

tctl_agent_state() { # pane_id -> working|waiting|ready
    tctl_agent_state_of "$(tctl_fmt "$1" '#{pane_title}')"
}

tctl_label() { # pane_id -> session:window.pane
    tctl_fmt "$1" '#{session_name}:#{window_index}.#{pane_index}'
}

tctl_human_age() { # epoch_seconds -> "3h"
    local age=$(( $(date +%s) - ${1:-0} ))
    [ "$age" -lt 0 ] && age=0
    if   [ "$age" -lt 60 ]    ; then printf '%ds' "$age"
    elif [ "$age" -lt 3600 ]  ; then printf '%dm' $(( age / 60 ))
    elif [ "$age" -lt 86400 ] ; then printf '%dh' $(( age / 3600 ))
    else printf '%dd' $(( age / 86400 )); fi
}
