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
  `allocations.json`, `jobs.json`, `schedules.json`, `secrets.json`,
  `publish-config.yaml`, `ui-auth.json`, and `releases/` (uploaded binaries). Losing a
  state file loses that slice of fleet/queue state — there is no off-site backup; back
  these up. `secrets.json` is the secret store: it holds every service's injected
  env values, including the credentials `nephos db create` generates — lose it and
  those databases become unreachable (the password lives only there and in the
  already-initialized data volume).
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
# 1. Cross-compile for every fleet arch, SIGN each, and upload to releases/
nephos self-update build "$NEPHOS_CONTROL_ADDR" --source-dir ~/projects/nephos-cloud-wt
#    (detects arches from the node registry: darwin/arm64 + linux/amd64 + linux/arm64)
```

`self-update build` signs each binary with the operator's ed25519 key at
`~/Library/Application Support/nephos/signing.key` (created on first use — it prints
a WARNING and the public key). **BACK THAT FILE UP.** Lose it and the fleet can't be
updated until you hand-re-pin a new public key on every node. It also stamps a
monotonic version into the signature (anti-rollback: agents refuse a version older
than the one they recorded).

Then install on each machine and **restart its service** — a running process keeps
the OLD binary until restarted. **Never `cp` over the live file** (Linux "text file
busy"); use `mv` a `.new`, or `agent self-update`.

```bash
# Linux agents (self-update verifies the signature against the node's pinned key):
for n in <node-aliases>; do
  ssh "$n" "~/bin/nephos agent self-update $NEPHOS_CONTROL_ADDR; systemctl --user restart nephos-deploy nephos-report"
done

# Control plane + its agent (Linux). Restart all three core units:
ssh <control-node> '~/bin/nephos agent self-update '"$NEPHOS_CONTROL_ADDR"'; \
  systemctl --user restart nephos-control nephos-deploy nephos-report'

# The macOS agent (real binary ~/.local/libexec/nephos; ~/.local/bin/nephos is a wrapper):
~/.local/libexec/nephos agent self-update "$NEPHOS_CONTROL_ADDR"   # verifies + installs
launchctl kickstart -k gui/$(id -u)/com.nephos.serve
launchctl kickstart -k gui/$(id -u)/com.nephos.report
```

**Signature verification is FAIL-CLOSED.** Each node needs the operator's PUBLIC key
pinned at `<config>/nephos/trusted-signing.pub` (Linux `~/.config/nephos/`, macOS
`~/Library/Application Support/nephos/`) or `agent self-update` REFUSES. Pin it once:
`printf '%s\n' '<pubkey>' > <that path>`. Use `--allow-unsigned` only to update a
node that hasn't been pinned yet (checksum-only, insecure). Derive the pubkey from
the signing key if you don't have it handy:
`python3 -c "import base64;d=base64.b64decode(open('...signing.key').read().strip());print(base64.b64encode(d[32:]).decode())"`.

**Bootstrapping signing (first time): order matters.** The release store only KEEPS
a signature if the control plane binary understands it. So update the control-plane
node to a signing-aware binary FIRST (via `--allow-unsigned`), THEN re-run
`self-update build` so the signatures actually land — otherwise the old control plane
silently drops them and every pinned node refuses the download ("carried no signature").

**GOTCHA — `--gateway-listen`.** The dedicated gateway listener is OPT-IN (empty
default). Do NOT set it to `:7931` — that collides with the `agent serve` port on the
control node and crash-loops both. Enable it only on a free loopback port, and only
when you also repoint the published `llm.*` tunnel origin at it.

**Which machines need the new binary depends on what changed:**
- Control-plane-only change (dispatcher, HTTP handlers, scheduling) → just the control node.
- Agent-side change (execution / quadlet / fingerprint / log resolution) → every agent.
- Both → the whole fleet.

Restarting the control plane briefly blips the inference gateway (`llm.` host) —
in-flight requests fail and retry; acceptable. A node re-registers its fingerprint on
agent restart **only if the control plane is up** — if control is down/crash-looping
when an agent restarts, that node keeps its stale registration until it re-reports.

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
- **Public:** `nephos publish <service> --config <publish-config.yaml>` adds a
  Cloudflare Tunnel route under your public apex domain (`--config` is REQUIRED; the
  zone + credentials live in that file on the control-plane node). It only ADDS the
  route — it does not run cloudflared; deploy the `cloudflared` connector separately
  with the token `publish` prints once. The tunnel terminates TLS at the edge. (The
  apex/endpoints are machine-local — read them from `~/.config/nephos/env`, never
  hardcode them.)

## The dashboard (admin panel)

```bash
nephos ui            # manage the embedded web dashboard (fleet / inference / storage views)
nephos ui passwd     # set the dashboard password (hash in ~/.config/nephos/ui-auth.json)
```
Mounted on the control plane's listener; reach it over the tailnet (or publish it).

---

## Storage & databases (the control-plane side)

Operators USE these (the `nephos` skill: `nephos storage bucket …`, `nephos db
create …`); what the control room owns is the config that makes them work.

- **`--storage-config` gates BOTH the dashboard storage view AND bucket management.**
  `nephos control start --storage-config <file>` builds the MinIO client the whole
  storage surface needs. Without it, an operator's `nephos storage bucket create`
  gets a clear **503 "object storage is not configured"** — the first thing to check
  when buckets "don't work." The file gives the MinIO admin/S3 endpoint plus
  `accessKey`/`secretKey` as *shell commands* (resolved once at load, never literals
  in the file — same vault-agnostic pattern as manifest secrets). One shared MinIO,
  many buckets: bucket lifecycle is first-class, but putting/getting objects is still
  done with any S3 client against the endpoint.
- **`nephos db create` is a per-app dedicated database**, deployed through the normal
  dispatch. Its generated credential is stored ONCE in the secret store (`secrets.json`)
  and injected into every deploy, and its data sits in a durable named volume
  (`<name>-data`) on the node. Two consequences for you: `secrets.json` is critical
  backup state (above), and a database's real password can never be regenerated — a
  redeploy reuses the stored one, matching the volume's first-init password. `nephos
  db destroy <name> --yes` now does the full wipe (service + volume + credential +
  any backup schedule) in one step; ordinary teardown still keeps the volume.
- **Scoped keys are real MinIO service accounts.** `nephos storage key new` mints one
  with an inline policy limited to a single bucket (root-owned; visible via `mc admin
  user svcacct ls`). nephos only lists/revokes accounts whose description begins
  `nephos scoped key for bucket ` — an account you add out-of-band with `mc` is
  invisible to `storage key ls/rm` by design. `storage quota` is a MinIO hard quota.
- **Backups.** `nephos db backup` dumps into the `nephos-backups` bucket via a job on
  the DB's node, using a bucket-scoped key stored as the job's secret. The dump streams
  through whatever `NEPHOS_S3` endpoint the job carries: the **public** endpoint works
  from any node but round-trips through Cloudflare (slow for GB-scale dumps), so for a
  DB co-located with MinIO pass `--endpoint http://127.0.0.1:9000`. Still no off-site
  copy — a backup in `nephos-backups` lives on the same MinIO as everything else.

---

## Alerts (ntfy)

Push alerting is **enabled**: the control plane runs with `--ntfy-topic` (and
`--ntfy-url`), and the topic lives in `~/.config/nephos/env` as
`NEPHOS_NTFY_TOPIC` — machine-local, never hardcode it. One topic carries three
event sources:

- a **service** going running→down (report comparison on each node report),
- a whole **node** going offline, and its recovery (a control-plane heartbeat sweep
  — the piece that catches a box that has died and stopped reporting, which the
  service-down check structurally cannot),
- **job** completion / failure (the queue dispatcher).

An ntfy topic is semi-private (anyone who knows it can read it), so keep it out of
the public dotfiles repo. To change it, edit `--ntfy-topic` in the control-plane
systemd unit and restart `nephos-control`; an empty topic disables all alerting.

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
