---
name: fleet
description: One-shot health report for Owen's nephos fleet — which nodes are up, what's stopped or restarting, failing jobs, and live GPU/VRAM/RAM/disk pressure per machine. Use for "how is nephos doing", "how's the fleet", "what's running on fedora/gpu1/gpu2/the studio", "is gpu1 ok", "are the machines saturated", "what nodes are free", or before deciding where to put new work. Read-only.
---

# fleet

Run the snapshot first, before any ad-hoc ssh:

```bash
~/.agents/skills/fleet/scripts/fleet-status
```

It runs `nephos nodes`, `nephos ps`, `nephos jobs` and an ssh probe of every Linux node
in parallel (about 10s total, 12s cap per dead node), then prints:

- **NODES**: every registered node
- **LIVE PRESSURE**: RAM, disk, GPU util and VRAM per node, and memory pressure on the Studio
- **STOPPED / RESTARTING / OFFLINE**: anything not running, restart counts, and nodes the control plane has lost
- **FAILED JOBS**: the most recent failure per job name
- **RUNNING**: service count per node

## Answering

- Lead with what needs attention: an offline node, a job that fails on every run, a node
  near its VRAM or RAM limit. If nothing does, say "healthy" in one line.
- VRAM in use on a node with no running nephos services means something is running
  outside nephos (sglang, llama.cpp, a jarvis model). Name it with
  `ssh <node> nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv`.
- A stopped `llm-*` tier on the Studio is usually on purpose (tiers start on demand).
  Don't report it as broken.
- To dig into one service: `nephos logs <name>`. For a job: `nephos job logs <id>`.
- Keep it short. Owen reads this on their phone.
