---
name: nephos-admin
description: >-
  Operating and maintaining Owen's nephos cloud itself — the control-room side, NOT
  using it (that's the `nephos` skill). Use when the task is: building and
  distributing the nephos binary across the fleet (`self-update`), starting or
  restarting the control plane, adding/removing/onboarding a NODE, configuring or
  restarting inference TIERS (editing gateway-config, `llm up/down`), minting/scoping
  gateway API keys, managing the web dashboard/admin panel (`nephos ui`), setting up
  public exposure (Cloudflare Tunnel / `tailscale serve`), or diagnosing why the
  fleet/control-plane/an agent is misbehaving. Trigger on "update nephos", "rebuild
  nephos", "ship the nephos binary", "self-update the fleet", "restart the control
  plane", "add a node to my cloud", "onboard a node", "configure a tier / model",
  "add an inference tier", "the control plane is down", "an agent isn't picking up
  jobs", "the gateway is 401ing", "nephos admin panel", "publish a service". This
  skill assumes control-room access (the Studio); an operator machine that only USES
  the cloud does not have it. Read ~/.config/nephos/env for the control-plane address
  and node SSH aliases; never hardcode tailnet addresses.
---

# nephos-admin — operating the cloud

The counterpart to the `nephos` skill. `nephos` teaches how to USE the cloud
(deploy, run jobs, inference, logs). This teaches how to RUN it: build and ship the
binary, manage the control plane, add nodes, configure tiers, and fix the fleet.

**You administer from the control room (the Studio).** The control-plane PROCESS
runs on a different machine (a node), and most admin actions are `ssh <node> …`
from here. Read `~/.config/nephos/env` first — it holds `NEPHOS_CONTROL_ADDR`, the
public endpoints, and `NEPHOS_NODES` (SSH aliases in `~/.ssh/config`). Never
hardcode tailnet addresses.

---

## The fleet's shape (where things actually live)

- **Control plane** — one node runs `nephos-control.service` (a **`systemctl --user`**
  service, NOT system-wide, NOT via sudo/fsudo). Its state + config live in
  `~/.config/nephos/` on that node: `gateway-config.yaml`, `keys.json`, `nodes.json`,
  `allocations.json`, `jobs.json`, `schedules.json`, `publish-config.yaml`,
  `ui-auth.json`, and `releases/` (uploaded binaries). Losing a state file loses that
  slice of fleet/queue state — there is no off-site backup; back these up.
- **Agents** — every node runs a deploy listener (`nephos-deploy.service` on Linux,
  the `com.nephos.serve` launchd agent on macOS) plus a reporter (`nephos-report` /
  `com.nephos.report`). Jobs and deploys execute here.
- **Inference backends** — Ollama / MLX processes on the GPU/unified-memory node,
  fronted by the gateway the control plane serves.
- **Binary paths differ by machine (the #1 gotcha):** Linux nodes run the real
  binary at **`~/bin/nephos`**; macOS runs it at **`~/.local/libexec/nephos`** behind
  a tracked shell wrapper (`~/.local/bin/nephos`). `agent self-update` installs to
  `~/bin` on Linux; the macOS wrapper is NOT the binary. Know which path a machine
  uses before you swap anything.

---

## Building & shipping the binary (do this after any source change)

Source: `~/projects/nephos-cloud-wt` (Go module `nephos`), pushed to
`github.com:ostepan8/nephos`.

```bash
# 1. Cross-compile for every fleet arch and upload to the control plane's releases/
nephos self-update build "$NEPHOS_CONTROL_ADDR" --source-dir ~/projects/nephos-cloud-wt
#    (detects arches from the node registry: darwin/arm64 + linux/amd64 + linux/arm64)
```

Then install on each machine and **restart its service** — a running process keeps
the OLD binary until restarted. **Swap with `mv`, never `cp` over the live file**
(Linux gives "text file busy"; write `.new` then `mv`).

```bash
# Control plane + its agent (Linux, ~/bin/nephos):
ssh <control-node> 'cp ~/.config/nephos/releases/linux-amd64/nephos ~/bin/nephos.new \
  && chmod +x ~/bin/nephos.new && mv ~/bin/nephos.new ~/bin/nephos \
  && systemctl --user restart nephos-control nephos-deploy'

# The macOS agent (~/.local/libexec/nephos):
cp /path/to/darwin-build ~/.local/libexec/nephos.new && chmod +x ~/.local/libexec/nephos.new \
  && mv ~/.local/libexec/nephos.new ~/.local/libexec/nephos
launchctl kickstart -k gui/$(id -u)/com.nephos.serve

# Other Linux agents:
for n in <node-aliases>; do
  ssh "$n" "~/bin/nephos agent self-update $NEPHOS_CONTROL_ADDR; systemctl --user restart nephos-deploy"
done
```

**Which machines need the new binary depends on what changed:**
- Control-plane-only change (dispatcher, HTTP handlers, scheduling) → just restart the
  control-plane node.
- Agent-side change (execution / quadlet / log resolution) → every agent.
- Both → the whole fleet.

Restarting the control plane briefly blips the inference gateway (`llm.` host) —
in-flight requests fail and retry; acceptable.

---

## Inference tiers

Tiers are declared in **`~/.config/nephos/gateway-config.yaml` on the control-plane
node** — one block per alias: `alias`, `backend`, `model`, `engineKind`,
`maxConcurrent`, `maxPromptTokens`, `overflowAlias`, `maxLiveTokens`,
`maxQueueWaitSeconds`, `autostart`, `idleTimeoutSeconds`. Edit the file, then
`systemctl --user restart nephos-control`.

```bash
nephos llm ls                 # what's actually loaded now
nephos llm up|down <tier>     # start/stop a backend (frees GPU memory)
nephos keys new <app> --models fast --models mid   # mint a scoped key (shown once)
nephos models                 # list tiers (needs a key; 401 if unauthenticated — that's the gate working)
```

Gotchas: two heavy models can't be resident on one Ollama at once (they thrash and
serve *empty responses*, not errors) — lean on `idleTimeoutSeconds` to free the GPU.
A tier's key scope must include a model alias or calls 401 with "not scoped for
model". Ollama-backed tiers autostart/idle-unload themselves.

---

## Nodes

```bash
nephos nodes                  # every node, caps, free capacity
nephos nodes remove <id>      # drop a stale/ghost registration (a rebuilt machine re-registers)
```

**Onboarding a node:** install the binary for its arch at `~/bin/nephos`, `nephos
agent join`, then run `agent serve` + `agent report` under a supervisor
(`systemctl --user` unit on Linux, launchd agent on macOS). Add an SSH alias in
`~/.ssh/config` if the hostname doesn't resolve (some tailnet names don't). A node
only needs the base `nephos` skill, not this one.

---

## Exposure

- **Private (tailnet):** the control plane binds loopback; reach it over Tailscale.
  A freshly-deployed service's ports also bind loopback — expose with
  `tailscale serve --bg --tcp <port> tcp://127.0.0.1:<port>` on its node.
- **Public:** `nephos publish <service>` adds a Cloudflare Tunnel route under your
  public apex domain; the zone + credentials live in `publish-config.yaml` on the
  control-plane node, served by the `cloudflared` service. The tunnel terminates TLS
  at the edge. (The apex/endpoints are machine-local — read them from
  `~/.config/nephos/env`, never hardcode them.)

## The dashboard (admin panel)

```bash
nephos ui            # manage the embedded web dashboard (fleet / inference / storage views)
nephos ui passwd     # set the dashboard password (hash in ~/.config/nephos/ui-auth.json)
```
Mounted on the control plane's listener; reach it over the tailnet (or publish it).

---

## Diagnosing the fleet

- **`nephos logs` can't read a macOS launchd service** (it reaches for journalctl) —
  read the file directly: `~/.local/share/nephos/logs/<name>.log` on that node.
  (`nephos job logs` handles this correctly for jobs.)
- **A job/deploy 'succeeded' but nothing changed** — a running service/unit wasn't
  restarted; a redeploy of an active unit can no-op. Confirm the unit actually
  restarted.
- **An agent isn't picking up work** — it's likely on an old binary; self-update +
  restart its `nephos-deploy` / `com.nephos.serve`.
- **Control-plane state** lives in `~/.config/nephos/*.json` on the control node —
  inspect there when the queue/registry/ledger looks wrong.
- **Root on a Linux node:** `~/.vault/bin/fsudo '<cmd>'`. **Never** run `nephos-control`
  or agents as a system service — they are `--user` services by design.

---

## When NOT to use this skill

If the task is just USING the cloud — deploying an app, running a job, calling
inference, reading a service's logs — that's the `nephos` skill, and it works from
any operator machine. This skill is only for operating the fleet itself, and only
makes sense on a control-room machine with SSH access to the nodes.
