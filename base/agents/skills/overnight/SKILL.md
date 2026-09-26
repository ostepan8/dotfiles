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
  "claude --dangerously-skip-permissions '/goal $(cat $DIR/GOAL.md | tr '\n' ' ') Log each step to $DIR/PROGRESS.md.'; \
   ~/.agents/skills/overnight/scripts/notify \"$RUN: claude exited — see $DIR\" 4; exec zsh"
```

- Put the definition of done and the baseline **in the goal**. With no baseline, "it
  worked" can't be checked in the morning.
- The `notify` in the tmux command fires however the session ends, crash included, so
  Owen hears about an early death right away instead of in the morning.
- Tell Owen the tmux session name and how to attach: `tmux attach -t $RUN`.

## 3. Heartbeat

Schedule a check (CronCreate, or a nephos schedule) every 60–90 min that reads the tail of
`PROGRESS.md` and confirms the tmux pane is still producing output. When progress has
stalled (no new checkpoint in 2 intervals), send `notify "<run> stalled at: <last step>" 4`.

## 4. The morning report

When the goal is met or the run gives up, write `$DIR/REPORT.md`, then
`notify "<run> done: <one-line verdict>"`. The report contains:

1. **Verdict** in one line: worked, partly worked, or didn't, measured against the "done means" line.
2. **Evidence**: the numbers against the baseline, the exact command that reproduces
   them, and the paths to logs and artifacts.
3. **What changed**: commits and branches.
4. **Open questions** that were deferred during the night.

When Owen asks "did it work?", answer from REPORT.md and PROGRESS.md, not from memory.
