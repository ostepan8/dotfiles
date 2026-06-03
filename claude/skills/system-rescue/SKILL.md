---
name: system-rescue
description: "Diagnose and fix macOS performance/memory issues. Use when the user says their system is slow, frozen, running out of memory, swapping heavily, laggy, hot, or fans are loud. Triggers on 'low memory', 'system slow', 'free up RAM', 'why is my mac slow', 'kill stale processes', or similar resource-pressure complaints."
---

# System Rescue (macOS)

Diagnose memory/CPU pressure on the user's Mac and safely reclaim resources by killing stale processes. The user runs many editor integrations (Zed ACP) and autonomous Claude Code loops that commonly leak long-lived processes — this is usually the root cause.

## Diagnosis — run in parallel

```bash
vm_stat
sysctl hw.memsize vm.swapusage
top -l 1 -n 0 -s 0 | head -15
ps aux | sort -k 4 -rn | head -20         # top mem by %
ps -eo pid,etime,rss,command | awk '/claude/ && !/awk/'   # ALL claude procs with age
```

## Key pressure signals

| Signal | Threshold | Meaning |
|---|---|---|
| `PhysMem` unused | < 1 GB on 64 GB Mac | RAM exhausted |
| `vm.swapusage` used | > 80% of total | Hard swapping, will thrash |
| Pages in compressor | > 2M pages | Severe pressure, paging is constant |
| Load avg | > number of cores | CPU-bound |

## Common culprits on this machine

1. **Stale `claude` CLI processes** — user runs many sessions across tmux/editors and Zed's ACP (`@agentclientprotocol/claude-agent-acp`, `@zed-industries/claude-agent-acp`) spawns a child `claude` per project and doesn't clean up. Often finds 20–40 of these, some weeks old.
2. **Duplicate `tsserver`** — multiple editors (Zed, Cursor, VSCode) each open the same repo (usually `subconscious-co-op`) and spawn their own TypeScript server. Each can be 1–2 GB.
3. **Chrome renderers leaking** — a single tab at >2 GB is usually the worst offender.
4. **Abandoned autonomous loops** — `claude -p --dangerously-skip-permissions --max-turns …` from Jarvis self-improvement or similar. Often in stopped (`T`) state.

## Safety — NEVER kill the current session

Before killing any `claude` process, confirm which one is yours:

```bash
echo "My PID: $$, parent: $PPID"
ps -p $PPID -o pid,ppid,command
```

`$PPID` is the live `claude` session. Also spare any of its direct children (hook scripts running during the rescue).

**Do not kill:**
- The current `claude` session (parent PID from check above) or its children
- `uvicorn main:app` on port 7432 (user's todo-queue server)
- Anything owned by `root` unless clearly a runaway user process re-parented
- Chrome without naming the tab — ask first, the user may have unsaved work

## Fix — ask before killing, then prune

Present findings as a table (before-state metrics + list of stale PIDs with age/RSS) and ask for confirmation. On approval:

```bash
# Stale claude processes (all PIDs EXCEPT current session + its children)
kill <pid1> <pid2> ...

# Force-kill any stuck in T (stopped) state
kill -9 <stopped_pids>

# Duplicate tsservers — keep the newest, kill the rest
kill <old_tsserver_pids>
```

Wait 2–3 seconds, then verify with `vm_stat` + `sysctl vm.swapusage` and report the delta. Load avg may briefly spike as the kernel pages memory back from swap — this is normal and settles within a minute.

## Report format

Always show a before/after table (Free RAM, Compressor, Swap used, Processes) so the user sees the impact. Then flag anything left that needs manual intervention (big Chrome tabs, editor restarts, etc.) and name the likely root cause so the user can prevent recurrence.
