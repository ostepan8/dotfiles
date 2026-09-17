# tmuxctl/agg.awk — joins the pane list onto the session list in a single pass.
#
# Doing this in awk rather than bash is not a style choice: the bash version
# ran two `tmux list-panes` calls per session, which on a machine with forty
# sessions is eighty forks for one `ls`. Here both lists are fetched once and
# joined on session name.
#
# Input 1 (panes):    session \t command \t dead
# Input 2 (sessions): name \t windows \t attached \t activity \t path

function esc(x) { gsub(/\\/, "\\\\", x); gsub(/"/, "\\\"", x); return x }

function age(a,   d) {
    d = now - a
    if (d < 0) d = 0
    if (d < 60)    return d "s"
    if (d < 3600)  return int(d / 60) "m"
    if (d < 86400) return int(d / 3600) "h"
    return int(d / 86400) "d"
}

BEGIN { FS = "\t"; n = 0 }

FNR == NR {
    panes[$1]++
    if ($3 != "1" && $2 !~ /^(zsh|bash|sh|fish|dash|ksh|tcsh|csh|login)$/) busy[$1]++
    if ($2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) agents[$1]++
    next
}

{
    name = $1; windows = $2; attached = $3; activity = $4; path = $5
    p = panes[name] + 0; b = busy[name] + 0; a = agents[name] + 0
    state = (b > 0) ? "busy" : "idle"

    if (json) {
        printf "%s{\"type\":\"session\",\"session\":\"%s\",\"windows\":%d,\"panes\":%d," \
               "\"state\":\"%s\",\"attached\":%s,\"busy_panes\":%d,\"agents\":%d," \
               "\"idle_seconds\":%d,\"path\":\"%s\"}",
            (n++ ? "," : ""), esc(name), windows, p, state,
            (attached + 0 ? "true" : "false"), b, a, now - activity, esc(path)
    } else {
        printf "%-28s %3d %5d %-5s %-4s %-6s %s\n",
            name, windows, p, state, (attached + 0 ? "yes" : "no"), age(activity), path
    }
}
