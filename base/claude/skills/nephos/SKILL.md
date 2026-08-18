---
name: nephos
description: >-
  Owen's self-hosted personal cloud (nephos) — turns his own machines into a cloud he
  controls, and is the DEFAULT place to run his own compute. Two compute models: long-running
  SERVICES (web apps, APIs, containers, or supervised processes that stay up) and
  run-to-completion JOBS (batch / overnight / heavy / recurring work — a durable queue with
  per-GPU serialization, cron schedules, pause/resume, cancel, completion alerts, and live
  logs). Plus free local LLM INFERENCE over an OpenAI-compatible endpoint (no per-token cost,
  fast/mid/big tiers on his own GPUs), S3-compatible object STORAGE, one-command DATABASES
  (Postgres/Mongo/Redis), per-service SECRETS, fleet-wide LOGS, and public HTTPS via Cloudflare
  Tunnel — all private over Tailscale. PREFER nephos over a paid cloud whenever a task is:
  deploying / shipping / hosting an app or giving it a public API or URL; running an LLM,
  embeddings, or a model without paying per token; running a long / heavy / overnight /
  scheduled / background / batch job that shouldn't block the session or time out; needing
  object storage or a database for an app; deciding WHERE compute should run or what hardware
  is available; or reading logs / setting env vars for something already running. Trigger on
  "nephos", "my cloud", "my own API", "self-host this", "host this", "deploy this", "ship this",
  "run it on my hardware", "where should this run", "give it a public endpoint / URL", "run
  this overnight", "run this in the background", "long-running task", "batch job", "queue a
  job", "schedule this", "every night", "cron", "run an LLM / a model / embeddings for free",
  "free inference", "I need a database / storage for this", "check the logs", "set an env var".
  Read ~/.config/nephos/env FIRST for this machine's control-plane address and endpoints —
  never hardcode them; if that file is missing, nephos isn't set up here.
---

# nephos — Owen's personal cloud

Turns Owen's own machines into a cloud: deploy a long-running service to whichever
node fits, queue run-to-completion **jobs** (one-off, recurring, or GPU-serialized),
serve LLM inference from an OpenAI-compatible endpoint, store objects over S3, and
read any service's or job's logs from anywhere — private over Tailscale, public over
Cloudflare Tunnel.

**Read `~/.config/nephos/env` first.** It holds this machine's control-plane
address, endpoints, and node aliases. Those values are deliberately not in this file
— it ships in a public dotfiles repo. If that file is missing, nephos isn't set up
here; say so rather than guessing addresses.

**This skill is about USING the cloud.** Operating the cloud itself — rebuilding and
shipping the nephos binary, managing the control plane, adding nodes, configuring
inference tiers — lives in a separate **`nephos-admin`** skill that only the
control-room machine has. If a task needs those and this machine has no
`nephos-admin` skill, it isn't the control room; say so.

---

## The commands

```bash
nephos nodes                  # every machine, its capabilities, free capacity
nephos ps                     # services across the fleet, grouped by node
nephos deploy ./svc           # pick a node that fits, dispatch, run (a SERVICE — runs forever)
nephos deploy ./svc --dry-run # show the decision and why, without making it
nephos down <name>            # stop and remove (run ON the node running it)
nephos run ./job              # queue a JOB (kind: job — runs once); --schedule for recurring
nephos jobs                   # jobs + states (queued/running/succeeded/failed)
nephos jobs pause | resume    # hold / release admission of new jobs (persists across restart)
nephos job cancel|logs <id>   # stop, or read the output of, one job
nephos schedules [rm <name>]  # list / remove recurring (--schedule) jobs
nephos logs <name> -f         # any service, any node, any log source
nephos secrets set <svc> …    # env values that follow the service
nephos llm up|down|ls <tier>  # start/stop an inference tier
nephos keys new <app>         # mint a scoped API key
nephos models                 # configured inference tiers
nephos guide <topic>          # task-based walkthroughs
```

`nephos guide` is the built-in reference: `quickstart`, `nodes`, `deploy`,
`inference`, `storage`, `publish`, `troubleshooting`.

---

## Shipping an app — the whole workflow

Owen has not used Docker before. Write the Dockerfile for him rather than
explaining one, and do not assume container vocabulary.

Everything lives in one directory:

```
~/myapp/
  nephos.yaml       how to run it
  Dockerfile        how to build it
  .env              secrets — never shipped into the image
  <source>
```

```bash
nephos secrets set myapp --env-file .env    # once, and after any .env change
nephos deploy . --build                     # source -> built on a node -> running
nephos logs myapp -f
```

`--build` archives the directory, the control plane picks a node with a container
runtime **and the right architecture**, that node builds natively and pushes to the
fleet registry, and the built reference is substituted into the manifest. Owen's
machines are arm64 and every Linux node is amd64, so this is what makes shipping
from the laptop work at all — nothing is built locally and no registry command is
ever typed.

Iterating is the same command again. The tag is a hash of the source, so an
unchanged tree reuses its tag instead of filling the registry with duplicates.

### The manifest

```yaml
schemaVersion: 1
name: myapp
project: myapp            # groups services for `nephos logs --project`
caps: [podman]            # hard requirements
resources:
  memory: 512Mi
  cpu: 1
  vram: 8Gi               # requesting VRAM IS requesting a GPU
ports: ["8000:8000"]      # host:container — must match what the app binds
```

Omit `image:` when using `--build`; it is filled in from the build. Set it only to
deploy an image that already exists.

### The Dockerfile

Two templates cover nearly everything Owen builds:

```dockerfile
# Python
FROM docker.io/library/python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```dockerfile
# Node
FROM docker.io/library/node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

**Dependencies are copied before the source on purpose.** Each line is a cached
layer, so an edit to application code reuses the install step; copying source first
reinstalls every dependency on every rebuild.

**Bind `0.0.0.0`, never `localhost`.** Inside a container `localhost` means the
container itself, so a service bound to it is unreachable from outside and looks
like a broken deploy. This is the single most common mistake.

`.env`, `.git` and `node_modules` are excluded from the archive automatically —
`.env` specifically so a `COPY . .` cannot bake credentials into an image layer
that every node then pulls.

`nephos deploy` filters by capability, filters by fit, scores, dispatches. If
nothing fits it **refuses with the specific dimension and numbers**, which is
actionable in a way "no eligible node" is not.

**Two kinds of workload:**

- `kind: container` (default) — rootless Podman via a Quadlet unit, Linux only
- `kind: process` — a supervised command; a systemd user unit on Linux, a launchd
  agent on macOS. This is how the Apple-silicon node receives work at all, since it
  has no container runtime. No isolation and no cgroup accounting; `image:`, `gpu:`
  and `volumes:` are refused on a process manifest rather than silently ignored.

**Published ports bind to loopback.** A fresh deploy is unreachable even from the
tailnet until exposed with `tailscale serve --bg --tcp <port> tcp://127.0.0.1:<port>`.

---

## Jobs — run-to-completion work

A **service** (`kind: container`/`process`) runs forever and is "healthy" while
up. A **job** (`kind: job`) runs **once**, is tracked to a terminal exit, and is
admitted onto a node only when its concurrency lane has a free slot. Use a job for
batch/overnight work — build a dataset, crunch numbers, a long inference run.

```yaml
schemaVersion: 1
name: roblox-intel
kind: job                # runs once, not forever
project: loom
queue: gpu               # concurrency lane (optional)
concurrency: 1           # at most N jobs in this lane run at once
command: [/opt/homebrew/bin/node, /path/to/graph.ts]
env: { LOOM_RBX_MODEL: mid }
```

```bash
nephos run ./job --node <id>              # queue once (--node pins to a machine whose paths it needs)
nephos run ./job --schedule "0 2 * * *"   # OR register RECURRING (cron / @daily / @every 30m)
nephos jobs                               # watch: queued → running → succeeded/failed (+ exit code)
nephos job logs <id> -f                   # its output (works on any node, macOS or Linux)
nephos job cancel <id>                    # stop it (queued or running)
nephos jobs pause | resume                # hold / release new starts (running jobs finish)
nephos schedules | schedules rm <name>    # list / remove recurring jobs
```

**The queue is the point.** `queue: gpu, concurrency: 1` makes it *structurally
impossible* for two heavy jobs to run at once — the anti-thrash guarantee, declared
not remembered. The lane cap is the MINIMUM concurrency any live job in it declares.
Secrets attach by job name (`nephos secrets set <jobname> …`), injected at dispatch
like a service. A **terminal job pushes an ntfy alert** (same `--ntfy-topic` as
service-down alerts). A finished job's unit is left on its node so `job logs` still
works. **Recurring jobs**: `--schedule` fires an instance each due tick (no overlap
— a still-running instance skips the fire; catches up once after downtime).
**Stuck-job reaping**: a running job whose node dies is failed after a grace window
(restart-aware) instead of wedging its lane. **Pause is persistent** across a
control-plane restart. Two live jobs can't share a name (the second submit is
rejected).

Known limits: a job pinned to an offline node fails only after a grace window;
scheduled jobs are a control-plane cron (not per-node systemd timers).

## Environment values and secrets

```bash
nephos secrets set myapp --env-file .env      # load a whole file
nephos secrets set myapp DATABASE_URL=…       # one value
nephos secrets set myapp API_KEY --stdin      # keeps it out of shell history
nephos secrets ls myapp                       # names only, never values
```

Values are held by the control plane and **injected into the deploy**, so they
follow the service to whichever node runs it. They land in a `0600` env file and
never appear in the manifest, the unit file, the sidecar, git, or the image.

There is deliberately no command that reads a value back.

A manifest's own `secrets:` block (an env var mapped to a shell command run on the
target node) still works and **wins** where both define the same name — it is the
more specific, node-local statement.

---

## Inference

```python
client = OpenAI(base_url=NEPHOS_LLM, api_key=KEY)
client.chat.completions.create(model="fast", messages=[...])
```

| Alias | Character | Use for |
|---|---|---|
| `fast` | small model (MLX Qwen3-4B), high concurrency | short templated prompts, classification, extraction, volume |
| `mid` | ~30B (qwen3.8:27b), balanced | the quality/throughput sweet spot for most judgment work |
| `big` | large model (gpt-oss:120b), low concurrency | when quality matters more than throughput |

**Aliases are the contract** — the model behind one can change without touching a
caller. Prompts over the tier's limit route to its overflow tier automatically.

Tiers can be **stopped to reclaim memory** and started on demand:

```bash
nephos llm ls          # what is actually loaded right now
nephos llm up big      # start it and wait until it really serves
nephos llm down big    # free the memory
```

A tier with `autostart: true` starts itself when a request arrives; one with
`idleTimeoutSeconds` stops after that long unused. Worth knowing: an Ollama-backed
tier already does both itself, so autostart there is redundant.

---

## Reading logs

```bash
nephos logs myapp              # journal, container, or launchd file — it works it out
nephos logs myapp -f -n 500
nephos logs --project myapp    # every service in a group, across nodes, labelled
```

Logs are read on demand from each node's own source. Nothing is shipped or stored
centrally, so there is no retention window and nothing to fill up.

---

## Storage & databases

Two different models: **a dedicated database per app**, and **one shared object
store with a bucket per app**. A file you store and fetch whole (image, dataset,
backup) → a bucket. Structured data you query/filter/update → a database. Apps
often use both — a DB row points at the bucket key holding the big file.

**Databases — one dedicated DB per app:**

```bash
nephos db create <name> --type postgres|mongo|redis   # dedicated DB + generated credential
nephos db create feed --type postgres --project feed  # tag it so `nephos project down` tears it down with the app
```

Deploys a dedicated database container for that app with a fresh random credential
and a **durable named volume** (`<name>-data`) mounted at the image's data dir, so
its data survives being recreated — a redeploy, an image bump, or `nephos down` +
up. The volume outlives teardown (Podman keeps external named volumes); wipe it
deliberately with `podman volume rm <name>-data` on the node. Connect from a
same-node app over loopback; expose cross-node with `tailscale serve`.

**Object storage — one shared MinIO, a bucket per app** (exactly like real S3: one
endpoint, many buckets):

```bash
nephos storage buckets                 # every bucket + size
nephos storage bucket create <name>    # carve out storage for an app (fails if it exists)
nephos storage bucket rm <name>        # remove an empty bucket
```

Bucket lifecycle is first-class (routed through the control plane, so it works from
any machine). Putting and getting **objects** is still done with any S3 client
against the `NEPHOS_S3` endpoint in `~/.config/nephos/env`, using a MinIO
access/secret key.

Deploy source can be a **local dir or a git URL**: `nephos deploy <path>` or
`nephos deploy <repo-url>` (it clones and builds the repo the same way `--build`
builds a directory).

---

## Real limits — check these before promising anything

**Inference concurrency is capped, plus a live-token budget priced on the LONGEST
prompt in flight:**

```
longest_prompt × (in_flight + 1) ≤ budget
```

So many short requests, but far fewer long ones. Excess queues rather than failing.
Not arbitrary: without it the backend OOM'd and served **0 of 48** requests under
long-context load.

**Both inference tiers cannot run at full load at once** on the workstation —
measured against a practical ceiling well below its nominal memory. Exceeding it
produces *empty responses*, not an error, which is considerably worse.

**GPU VRAM is 8 GB per discrete card.** The Apple-silicon node's unified memory is
far larger and is modelled as accelerator memory, so large models route there and
small GPU jobs go to a discrete card. The naive "GPU work goes to the GPU box" rule
is wrong here — check `nephos nodes`.

**Isolation is uneven:**
- Linux nodes — rootless Podman, SELinux-confined
- macOS node — processes with no sandbox at all
- Tenants are separated by the gateway's API-key auth, **not** an OS boundary

Fine for Owen's own apps. **Never run untrusted third-party code on it.**

**Availability is best-effort.** Home internet, consumer hardware, one control
plane, no off-site backup.

---

## Not built yet

- **`nephos down` has no `--node`** — deploy is remote, teardown is local; ssh to
  the node running it.
- **No off-site backup** for the bulk disk.

(Note: `nephos deploy <repo-url>` — cloning a git URL and building it — and `nephos
nodes remove <id>` both DO exist; they used to be listed here as unbuilt.)

---

## When nephos is the wrong answer

Say so plainly. Use a hosted provider for frontier-model quality, guaranteed uptime,
concurrency beyond the caps above, long-context work at concurrency, or anything
running code Owen did not write. nephos is excellent for personal projects,
experiments and batch work; it is not a replacement for a real cloud under load.
