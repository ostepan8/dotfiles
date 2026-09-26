---
name: overnight
description: Set up long-running autonomous work that survives Owen leaving — an overnight research loop, a multi-hour build/benchmark, "work until it's done", "I'm going to sleep, by morning I expect X", "run this for 10 hours", "don't come back until it works". Makes the run observable (checkpoint log, heartbeat, phone alert on finish or death) and ends with a morning report that proves the result. Use together with the `nephos` skill when the work is a batch job that belongs on the fleet.
---

# overnight

The failures this prevents, all real: "it's the morning and I don't see the tmux history",
"it ended super quickly and never reported back any statistics", "did we get it to work
or not?", and seven "continue" prompts in a row. A long run needs to prove it is alive
while it runs and prove its result when it ends.

## 1. Choose where it runs

| Work | Where |
|---|---|
| a deterministic script (benchmarks, scraping, training, batch inference) | a **nephos job**: `nephos run` with a job manifest (see the `nephos` skill). It gets queueing, per-GPU serialization, logs, and an ntfy alert on completion for free. |
| agentic work (research, implement, iterate) | a **Claude session in a named tmux session** on the Studio (or the node that has the hardware) |

## 2. Agentic runs: start them properly

```bash
RUN=<short-name>-$(date +%m%d); DIR=~/runs/$RUN; mkdir -p $DIR
cat > $DIR/GOAL.md <<'MD'
# Goal: <one sentence>
## Done means (checkable): <tests pass / metric >= X vs baseline Y / PR merged>
## Baseline to beat: <number + how measured>
## Rules: checkpoint to PROGRESS.md after every step; commit work as you go; never stop to ask — record the question in PROGRESS.md and pick the safe default.
MD
tmux new-session -d -s "$RUN" -c <repo> \
  "claude --dangerously-skip-permissions '/goal Complete everything in $DIR/GOAL.md (read it first). Log each step to $DIR/PROGRESS.md. Done only when $DIR/REPORT.md proves every Done-means item.'; \
   ~/.agents/skills/overnight/scripts/notify \"$RUN: claude exited — see $DIR\" 4; exec zsh"
```

- Put the definition of done and the baseline **in the goal**. With no baseline, "it
  worked" can't be checked in the morning.
- The `notify` in the tmux command fires however the session ends, crash included, so
  Owen hears about an early death right away instead of in the morning.
- Tell Owen the tmux session name and how to attach: `tmux attach -t $RUN`.

## 3. Heartbeat

**The session that launched the run is its supervisor: keeping the run alive is your job.**
Don't hand that job to a cron and walk away. Start the watcher in the background
(Bash with `run_in_background`):

```bash
~/.agents/skills/overnight/scripts/watch "$RUN"
```

It exits as soon as the run needs attention: the session died, it has been idle for 3 min,
`PROGRESS.md` has gone an hour without a checkpoint, or `REPORT.md` exists. Its exit wakes
you. Handle it with the steps below, then restart the watcher. Keep an hourly CronCreate
check as a backstop in case the watcher itself dies. **Unstick the run yourself before
paging Owen**: he wants to be woken only after self-repair has failed.

1. Read the terminal (`tmux capture-pane -pt $RUN -S -200`) and the tail and mtime of
   `PROGRESS.md`. If it is still working, do nothing.
2. If it is stuck (idle prompt, `/goal` no longer active, a blocking dialog, an error loop, a
   rate limit that has since cleared, or no new checkpoint since the last check), unstick
   it: answer or dismiss the prompt, or `tmux send-keys -t $RUN "Continue toward the goal in
   $DIR/GOAL.md. Last checkpoint: <x>. <hint>" Enter`. If the session is dead, restart it
   with a `/goal` that points at GOAL.md. Log the intervention in `PROGRESS.md`.
3. Re-read the pane about 3 minutes later. Only if it still isn't moving, send
   `notify "<run> stuck: <what's wrong + what you tried>" 4`.
4. Delete the check once `REPORT.md` exists.

`/goal` rejects a condition longer than 4000 characters, so keep the long spec in GOAL.md
and send `/goal` a short condition that points at that file. A new folder also shows a
"trust this folder?" prompt, and the session sits blocked until someone answers it.

## 4. The morning report

When the goal is met or the run gives up, write `$DIR/REPORT.md`, then
`notify "<run> done: <one-line verdict>"`. The report contains:

1. **Verdict** in one line: worked, partly worked, or didn't, measured against the "done means" line.
2. **Evidence**: the numbers against the baseline, the exact command that reproduces
   them, and the paths to logs and artifacts.
3. **What changed**: commits and branches.
4. **Open questions** that were deferred during the night.

When Owen asks "did it work?", answer from REPORT.md and PROGRESS.md, not from memory.
