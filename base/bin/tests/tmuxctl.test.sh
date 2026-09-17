#!/usr/bin/env bash
# tmuxctl test suite.
#
# Every test runs against an ISOLATED tmux server on its own socket
# (-L tmuxctl-test-$$), never the one holding the real sessions. A test that
# touched the live server could kill a window with work in it, so the socket
# override is not a convenience -- it is the safety boundary.
#
#   bash tests/tmuxctl.test.sh          run everything
#   bash tests/tmuxctl.test.sh read     run tests whose name matches "read"
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/../tmuxctl"
SOCKET="tmuxctl-test-$$"
FILTER="${1:-}"

export TMUXCTL_SOCKET="$SOCKET"

PASS=0
FAIL=0
FAILED_NAMES=""

cleanup() { tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

# --- assertions ------------------------------------------------------------

ok()   { PASS=$((PASS + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES="$FAILED_NAMES
  - $1"; printf '  \033[31mFAIL\033[0m %s\n     %s\n' "$1" "$2"; }

assert_eq() { # expected actual name
    if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "expected [$1] got [$2]"; fi
}

assert_contains() { # haystack needle name
    case "$1" in
        *"$2"*) ok "$3" ;;
        *) bad "$3" "expected to find [$2] in: $(printf '%s' "$1" | head -c 300)" ;;
    esac
}

assert_not_contains() { # haystack needle name
    case "$1" in
        *"$2"*) bad "$3" "did not expect [$2] in output" ;;
        *) ok "$3" ;;
    esac
}

assert_json() { # text name
    if printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        ok "$2"
    else
        bad "$2" "not valid JSON: $(printf '%s' "$1" | head -c 300)"
    fi
}

# Runs tmuxctl, capturing stdout+stderr into $OUT and the code into $CODE.
ctl() { OUT="$("$BIN" "$@" 2>&1)"; CODE=$?; return 0; }

run_test() { # name function
    case "$1" in
        *"$FILTER"*) ;;
        *) return 0 ;;
    esac
    printf '\n\033[1m%s\033[0m\n' "$1"
    "$2"
}

# --- tests -----------------------------------------------------------------

test_help() {
    ctl help
    assert_eq 0 "$CODE" "help exits 0"
    assert_contains "$OUT" "run" "help lists the run command"

    ctl schema
    assert_eq 0 "$CODE" "schema exits 0"
    assert_json "$OUT" "schema emits valid JSON"
    assert_contains "$OUT" "exit_codes" "schema documents exit codes"

    ctl bogus-command
    assert_eq 2 "$CODE" "unknown command exits 2"
    assert_contains "$OUT" "tmuxctl:" "unknown command explains itself"

    ctl
    assert_eq 2 "$CODE" "no arguments exits 2"
}

test_new_and_ls() {
    ctl new t-alpha
    assert_eq 0 "$CODE" "new creates a session"

    ctl new t-alpha
    assert_eq 0 "$CODE" "new is idempotent"

    ctl ls
    assert_contains "$OUT" "t-alpha" "ls shows the session"

    ctl ls --json
    assert_json "$OUT" "ls --json is valid JSON"
    assert_contains "$OUT" '"session"' "ls --json labels sessions"

    ctl new t-beta --cwd /tmp
    assert_eq 0 "$CODE" "new accepts --cwd"
    ctl ls
    assert_contains "$OUT" "t-beta" "second session appears"
}

test_status_and_find() {
    ctl status t-alpha
    assert_eq 0 "$CODE" "status exits 0"
    assert_contains "$OUT" "idle" "an empty shell reads as idle"

    ctl status t-alpha --json
    assert_json "$OUT" "status --json is valid JSON"

    ctl find alpha
    assert_eq 0 "$CODE" "find resolves a unique substring"
    assert_contains "$OUT" "t-alpha" "find prints the canonical target"

    ctl find t-
    assert_eq 4 "$CODE" "ambiguous find exits 4"

    ctl status nope-nothing
    assert_eq 4 "$CODE" "missing target exits 4"
}

test_run() {
    ctl run t-alpha "echo hello-from-pane"
    assert_eq 0 "$CODE" "run returns the command's exit code"
    assert_contains "$OUT" "hello-from-pane" "run captures stdout"
    assert_not_contains "$OUT" "echo hello-from-pane" "run output excludes the echoed prompt line"

    ctl run t-alpha "echo to-stderr >&2"
    assert_contains "$OUT" "to-stderr" "run captures stderr"

    ctl run t-alpha "false"
    assert_eq 1 "$CODE" "run propagates a nonzero exit code"

    ctl run t-alpha --json "echo jsonrun"
    assert_json "$OUT" "run --json is valid JSON"
    assert_contains "$OUT" '"exit_code"' "run --json reports exit_code"

    ctl run t-alpha --timeout 1 "sleep 5"
    assert_eq 5 "$CODE" "run exits 5 on timeout"
    # the timed-out command is deliberately left running; stop it so later
    # tests find the pane idle.
    "$BIN" send t-alpha --keys C-c >/dev/null 2>&1
    sleep 1
}

test_run_refuses_busy_pane() {
    "$BIN" send t-beta "sleep 30" >/dev/null 2>&1
    sleep 1
    ctl run t-beta "echo nope"
    assert_eq 3 "$CODE" "run refuses a pane that is not an idle shell"
    assert_contains "$OUT" "busy" "refusal says the pane is busy"

    ctl status t-beta
    assert_contains "$OUT" "busy" "status reports the pane as busy"

    "$BIN" send t-beta --keys C-c >/dev/null 2>&1
    sleep 1
    ctl status t-beta
    assert_contains "$OUT" "idle" "pane returns to idle after C-c"
}

test_read_and_grep() {
    "$BIN" run t-alpha "echo needle-in-haystack" >/dev/null 2>&1
    ctl read t-alpha
    assert_eq 0 "$CODE" "read exits 0"
    assert_contains "$OUT" "needle-in-haystack" "read shows recent pane output"

    ctl read t-alpha -n 2
    assert_eq 0 "$CODE" "read honours -n"

    ctl grep needle-in-haystack
    assert_eq 0 "$CODE" "grep exits 0 when it matches"
    assert_contains "$OUT" "t-alpha" "grep names the pane that matched"

    ctl grep definitely-not-present-anywhere
    assert_eq 1 "$CODE" "grep exits 1 when nothing matches"
}

test_wait() {
    "$BIN" send t-alpha "sleep 2" >/dev/null 2>&1
    ctl wait t-alpha --timeout 10
    assert_eq 0 "$CODE" "wait returns once the pane goes idle"

    "$BIN" send t-alpha "sleep 30" >/dev/null 2>&1
    sleep 1
    ctl wait t-alpha --timeout 1
    assert_eq 5 "$CODE" "wait exits 5 on timeout"
    "$BIN" send t-alpha --keys C-c >/dev/null 2>&1
    sleep 1

    "$BIN" send t-alpha "echo marker-appeared" >/dev/null 2>&1
    ctl wait t-alpha --until "marker-appeared" --timeout 10
    assert_eq 0 "$CODE" "wait --until matches pane content"
}

test_layout() {
    ctl window t-alpha --name extra
    assert_eq 0 "$CODE" "window adds a window"
    ctl tree --json
    assert_contains "$OUT" "extra" "the new window is listed"

    ctl split t-alpha:extra
    assert_eq 0 "$CODE" "split adds a pane"
    PANES="$(tmux -L "$SOCKET" list-panes -t t-alpha:extra | wc -l | tr -d ' ')"
    assert_eq 2 "$PANES" "the window now holds two panes"

    ctl rename t-beta t-gamma
    assert_eq 0 "$CODE" "rename renames a session"
    ctl ls
    assert_contains "$OUT" "t-gamma" "renamed session is listed"
}

test_kill() {
    ctl kill t-gamma
    assert_eq 0 "$CODE" "kill removes an idle session"
    ctl ls
    assert_not_contains "$OUT" "t-gamma" "killed session is gone"

    "$BIN" new t-busy >/dev/null 2>&1
    "$BIN" send t-busy "sleep 30" >/dev/null 2>&1
    sleep 1
    ctl kill t-busy
    assert_eq 3 "$CODE" "kill refuses a busy session without --force"
    ctl kill t-busy --force
    assert_eq 0 "$CODE" "kill --force removes it anyway"

    ctl kill nope-nothing
    assert_eq 4 "$CODE" "killing a missing target exits 4"
}

test_targets() {
    ctl status t-alpha:extra
    assert_eq 0 "$CODE" "session:window resolves"
    ctl status t-alpha:extra.1
    assert_eq 0 "$CODE" "session:window.pane resolves"

    PANE_ID="$(tmux -L "$SOCKET" list-panes -t t-alpha:extra -F '#{pane_id}' | head -1)"
    ctl status "$PANE_ID"
    assert_eq 0 "$CODE" "a raw %pane-id resolves"
}

test_regressions() {
    # An error in --json mode used to be swallowed: tctl_die printed to stdout,
    # which is captured when resolution happens inside a command substitution.
    OUT="$("$BIN" status no-such-session --json 2>&1 >/dev/null)"; CODE=$?
    assert_contains "$OUT" '"ok":false' "a --json error reaches stderr"
    assert_json "$OUT" "the --json error is valid JSON"
    OUT="$("$BIN" status no-such-session --json 2>/dev/null)"
    assert_eq "" "$OUT" "nothing bogus is written to stdout on error"

    # `window` reported the session's already-active pane, not the new window.
    ctl window t-alpha --name regress-w --cmd "sleep 42"
    assert_eq 0 "$CODE" "window with --cmd succeeds"
    # The canonical target uses window INDEX, so check the reported pane really
    # lives in the new window rather than the one that was already in front.
    WNAME="$(tmux -L "$SOCKET" display-message -p -t "$(printf '%s' "$OUT" | cut -f1)" '#{window_name}')"
    assert_eq "regress-w" "$WNAME" "window reports the window it created"
    ctl status t-alpha:regress-w
    assert_contains "$OUT" "busy" "the --cmd is actually running in it"
    "$BIN" kill t-alpha:regress-w --force >/dev/null 2>&1

    # A window/pane scope for grep must not widen back to the whole session.
    ctl grep needle-in-haystack -t t-alpha:extra
    assert_eq 1 "$CODE" "grep -t on another window does not search the session"
}

test_agents() {
    ctl agents
    assert_eq 0 "$CODE" "agents exits 0 even with no agent panes"
    ctl agents --json
    assert_json "$OUT" "agents --json is valid JSON"
}

# --- driver ----------------------------------------------------------------

if [ ! -x "$BIN" ]; then
    printf 'tmuxctl.test: %s is missing or not executable\n' "$BIN" >&2
    exit 1
fi

run_test "help and schema"            test_help
run_test "new and ls"                 test_new_and_ls
run_test "status and find"            test_status_and_find
run_test "run"                        test_run
run_test "run refuses busy pane"      test_run_refuses_busy_pane
run_test "read and grep"              test_read_and_grep
run_test "wait"                       test_wait
run_test "layout"                     test_layout
run_test "kill"                       test_kill
run_test "targets"                    test_targets
run_test "regressions"                test_regressions
run_test "agents"                     test_agents

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { printf 'failed:%s\n' "$FAILED_NAMES"; exit 1; }
