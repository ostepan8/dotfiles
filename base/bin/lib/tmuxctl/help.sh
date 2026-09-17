# tmuxctl/help.sh — the self-description an agent reads before doing anything.

cmd_help() {
    cat <<'HELP'
tmuxctl — one verb-per-line interface to tmux, safe for agents to drive.

USAGE
  tmuxctl <command> [target] [options] [--json]

TARGETS  (anywhere a <target> is asked for)
  mysession              a session, by exact name or unique substring
  mysession:2            a window
  mysession:2.1          a pane
  %37  @12  $3           raw tmux ids (pane, window, session)
  .                      the pane tmuxctl is running in

LOOK
  ls [--panes]           sessions: windows, panes, busy/idle, agents, idle time
  tree                   every pane in every session
  status <target>        one pane: state, command, cwd, pid, title, agent info
  find <query>           resolve a fuzzy name to a canonical target
  read <target> [-n N] [--history]
                         what is on that pane's screen right now
  grep <text> [-i] [--history] [-t <target>]
                         find the pane that has that text on screen
  agents [--stale]       every live Claude Code pane and whether it is
                         working / waiting on input / ready

ACT
  run <target> <command> [--timeout SECS] [--bg]
                         run a shell command IN that pane, wait, return its
                         real stdout+stderr and its real exit code
  send <target> <text> [--no-enter] [--delay SECS]
  send <target> --keys C-c Escape ...
                         type into whatever is running there (editor, REPL,
                         agent). No output is captured; nothing is waited for.
  wait <target> [--timeout SECS] [--until REGEX]
                         block until the pane goes idle, or until its screen
                         matches REGEX

MANAGE
  new <name> [--cwd DIR] [--cmd CMD] [--attach]     create-or-reuse a session
  window <target> [--name N] [--cwd DIR] [--cmd C]  add a window
  split <target> [-h|-v] [--cwd DIR] [--cmd C]      add a pane
  rename <target> <new-name>
  kill <target> [--force]                           refuses busy/attached

EXIT CODES
  0 ok   1 no match   2 usage   3 refused   4 target not found   5 timed out
  `run` instead exits with the COMMAND's own code; use --json when you need to
  tell a command's exit 2 apart from a usage error.

NOTES
  --json           machine-readable output for every command. Errors are
                   emitted as JSON on STDERR, so a failed call never puts
                   anything unexpected on stdout.
  TMUXCTL_SOCKET   operate on another tmux server (the test suite uses this)
  tmuxctl schema   the same surface as JSON, for an agent to read in one call

run vs send: `run` is for a shell sitting at a prompt and refuses anything
else, because a shell command sent to a pane running an editor is not a
command, it is keystrokes. `send` is the deliberate way to do that.
HELP
    return 0
}

cmd_schema() {
    cat <<'SCHEMA'
{
  "tool": "tmuxctl",
  "summary": "Verb-per-line control of tmux sessions, windows and panes, with machine-readable output.",
  "target_grammar": {
    "session": "name | unique substring of a name",
    "window": "session:window-index-or-name",
    "pane": "session:window.pane-index",
    "ids": "%pane, @window, $session",
    "self": "."
  },
  "global_options": {
    "--json": "emit JSON instead of text; available on every command. Error objects are written to STDERR, never stdout.",
    "TMUXCTL_SOCKET": "env var selecting a non-default tmux server"
  },
  "exit_codes": {
    "0": "success",
    "1": "ran fine, found nothing (e.g. grep matched no pane)",
    "2": "usage error",
    "3": "refused on purpose: precondition not met (busy pane, attached session)",
    "4": "target not found, or an ambiguous fuzzy name",
    "5": "timed out",
    "note": "run exits with the wrapped command's own exit code; read exit_code from --json to disambiguate"
  },
  "commands": [
    {"name": "ls", "args": ["[--panes]"], "mutates": false,
     "returns": "one row per session: windows, panes, idle|busy, attached, agent count, idle time, path"},
    {"name": "tree", "args": [], "mutates": false,
     "returns": "one row per pane across all sessions"},
    {"name": "status", "args": ["<target>"], "mutates": false,
     "returns": "state (idle|busy|dead), command, path, pid, title, agent kind and agent state"},
    {"name": "find", "args": ["<query>"], "mutates": false,
     "returns": "canonical target and pane id; exits 4 if ambiguous"},
    {"name": "read", "args": ["<target>", "[-n N]", "[--history]"], "mutates": false,
     "returns": "pane screen contents; --history includes scrollback"},
    {"name": "grep", "args": ["<text>", "[-i]", "[--history]", "[-t <target>]"], "mutates": false,
     "returns": "panes whose screen contains the text, with the matching lines; exits 1 on no match"},
    {"name": "agents", "args": ["[--stale]"], "mutates": false,
     "returns": "live Claude Code panes with state working|waiting|ready; --stale also lists restored panes that only look like agents",
     "detail": "a live Claude Code pane reports a version string (e.g. 2.1.274) as its foreground command; a pane showing a Claude title under a plain shell is a tmux-resurrect restoration with no agent behind it"},
    {"name": "run", "args": ["<target>", "<command>", "[--timeout SECS]", "[--bg]"], "mutates": true,
     "returns": "the command's stdout+stderr and its exit code",
     "refuses": "panes that are not an idle shell (exit 3), because the text would be typed into whatever is running there",
     "detail": "output is redirected to a file inside the pane's shell rather than scraped off the screen, so it is free of prompts, wrapping and colour codes"},
    {"name": "send", "args": ["<target>", "<text>|--keys <key>...", "[--no-enter]", "[--delay SECS]"], "mutates": true,
     "returns": "nothing; does not wait and does not capture output",
     "detail": "the only way to talk to a busy pane: an editor, a REPL, or a running agent"},
    {"name": "wait", "args": ["<target>", "[--timeout SECS]", "[--until REGEX]"], "mutates": false,
     "returns": "returns when the pane goes idle, or when its screen matches REGEX; exit 5 on timeout"},
    {"name": "new", "args": ["<name>", "[--cwd DIR]", "[--cmd CMD]", "[--attach]"], "mutates": true,
     "returns": "target and pane id; idempotent, reuses an existing session of that name"},
    {"name": "window", "args": ["<target>", "[--name N]", "[--cwd DIR]", "[--cmd C]"], "mutates": true},
    {"name": "split", "args": ["<target>", "[-h|-v]", "[--cwd DIR]", "[--cmd C]"], "mutates": true},
    {"name": "rename", "args": ["<target>", "<new-name>"], "mutates": true},
    {"name": "kill", "args": ["<target>", "[--force]"], "mutates": true, "destructive": true,
     "refuses": "busy or attached targets without --force",
     "detail": "irreversible: tmux-resurrect restores layout, never the processes that were running"}
  ],
  "recipes": [
    {"goal": "what is running anywhere", "call": "tmuxctl tree --json"},
    {"goal": "which agents need me", "call": "tmuxctl agents --json"},
    {"goal": "run a build somewhere and read the result", "call": "tmuxctl run myproj 'npm run build' --timeout 600 --json"},
    {"goal": "start a long job without blocking", "call": "tmuxctl run myproj 'make all' --bg --json, then tmuxctl wait myproj --timeout 3600"},
    {"goal": "reply to a waiting Claude pane", "call": "tmuxctl send myproj:2.1 'yes, go ahead'"},
    {"goal": "find where an error is showing", "call": "tmuxctl grep 'Error:' --json"}
  ]
}
SCHEMA
    return 0
}
