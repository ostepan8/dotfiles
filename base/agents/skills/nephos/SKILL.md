---
name: nephos
description: >-
  Operate Owen's self-hosted Nephos cloud and fleet. Use for deploying or hosting services,
  public endpoints, background or scheduled jobs, local LLM inference, storage, databases,
  secrets, logs, machine health, fleet capacity, and repairs on Nephos nodes. Prefer Nephos
  over paid cloud for Owen's own compute. Trigger on Nephos, my cloud, self-host, deploy,
  run on my hardware, overnight jobs, free inference, fleet machines, or checking service
  logs. Read ~/.config/nephos/env first; never hardcode its endpoints.
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
nephos deploy ./svc --public <host>  # deploy AND publish a public HTTPS hostname (Cloudflare)
nephos deploy ./svc --ttl 2h  # ephemeral: auto-teardown after a duration (preview deploys)
nephos down <name>            # stop & remove; the control plane finds the node for you
nephos project down <name>    # tear down every service sharing a project: label (confirms first)
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

### Privileged fleet repairs

For machine-health or repair requests, inspect the target through its SSH alias
from `NEPHOS_NODES`; do not ask Owen to run basic diagnostics that are available
remotely. Start with `nephos nodes` / `nephos ps`, then check the live processes,
temperatures, GPU, logs, and service state on the affected host.

This machine has a Keychain-backed `vault` CLI. If an authorized repair needs
remote `sudo`, run `vault list` to find the host's credential (for example,
`FEDORA_SUDO_PASSWORD@fedora-sudo`) and pipe `vault get <name>` directly into
`ssh <host> "sudo -S -p '' <command>"`. Never print, store, interpolate, or place
the password in command arguments or shell history. Re-measure the original
symptom after the repair. A missing credential or failed authentication is the
point to ask Owen for help, not the first sudo prompt.

---

## Inference

For discrete-GPU placement, 8 GB model choices, SGLang launch guidance, and the
NVIDIA suspend failure seen on `gpu1`, read
[references/gpu-inference.md](references/gpu-inference.md).
For image generation, speech, vision-language, computer vision, and video model
placement, read [references/multimodal-inference.md](references/multimodal-inference.md).

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

**Push alerts are on.** You don't have to watch the logs to catch a failure — the
control plane pushes to an ntfy topic (`NEPHOS_NTFY_TOPIC` in `~/.config/nephos/env`)
whenever a service goes down, a whole node goes offline (or recovers), or a job
finishes/fails. Subscribe to that topic in the ntfy app.

---

## Storage & databases

Two different models: **a dedicated database per app**, and **one shared object
store with a bucket per app**. A file you store and fetch whole (image, dataset,
backup) → a bucket. Structured data you query/filter/update → a database. Apps
often use both — a DB row points at the bucket key holding the big file.

**Databases — one dedicated DB per app:**

```bash
nephos db create <name> --type postgres|mongo|redis   # dedicated DB + generated credential
nephos db ls                                           # every database across the fleet, with type + node
nephos db backup <name> [--schedule "0 3 * * *"]       # dump → nephos-backups bucket, once or recurring
nephos db destroy <name> --yes                         # remove the service, its data volume, AND its credential
```

`db create` deploys a dedicated database container with a fresh random credential
and a **durable named volume** (`<name>-data`), so its data survives recreation (a
redeploy, image bump, or `nephos down` + up). The credential is stored once and
injected on every deploy (stable — never regenerated). `db destroy` is the complete
inverse (service + volume + credential + any backup schedule) and needs `--yes`;
plain `nephos down` deliberately keeps the volume so a redeploy retains data.

`db backup` submits a job that dumps the DB (via the container's own dump tool)
straight into the `nephos-backups` bucket, pinned to the DB's node; `--schedule`
makes it recurring (manage with `nephos schedules`). **Co-located tip:** when the
DB is on the same node as MinIO, pass `--endpoint http://127.0.0.1:9000` — a 1 GB
dump then finishes in seconds instead of round-tripping through the public endpoint.
This is what makes a durable database also a *backed-up* one.

**Object storage — one shared MinIO, a bucket per app** (exactly like real S3):

```bash
nephos storage buckets                          # every bucket + size
nephos storage bucket create|rm <name>          # carve out / remove a bucket (rm needs it empty)
nephos storage put|get|ls|rm <bucket> …         # object I/O, direct to the S3 endpoint
nephos storage key new <app> --bucket <b>       # mint a key SCOPED to one bucket (secret shown once)
nephos storage key ls | rm <accessKey>          # list / revoke scoped keys
nephos storage quota set <bucket> 10Gi | clear  # cap a bucket's size
```

Bucket/key/quota management routes through the control plane (works from any
machine). **Object I/O goes direct to the S3 endpoint** and needs a credential:
`NEPHOS_S3_ACCESS_KEY` / `NEPHOS_S3_SECRET_KEY` (mint a bucket-scoped one with
`storage key new`), against the `NEPHOS_S3` endpoint in `~/.config/nephos/env`. A
scoped key can touch **only its bucket** — real isolation, not just a naming
convention.

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

- **No off-site backup** for the bulk disk. `nephos db backup` dumps a single
  *database* into a bucket, but every bucket lives on the same MinIO as everything
  else — a node loss loses both.
- **No standalone `nephos unpublish`** — a public route is removed only as a side
  effect of `nephos down` / `nephos project down` (which do tear it down). There is
  no verb to drop a route while keeping the service up.
- **No `nephos nodes --json`** — `nephos ps --json` and `nephos jobs --json` exist,
  but `nephos nodes` is table-only.
- **Service deploys don't retry or route around a down node.** Placement picks the
  single best-fitting node from the *whole* registry with no liveness filter; a
  dispatch failure returns an error rather than trying the next candidate. (Node
  liveness IS tracked — it drives the offline/recovery ntfy alerts — it just doesn't
  yet feed placement. *Jobs* do retry, up to 3 attempts across nodes, and reap a job
  whose node dies.)
- **Manifest `schedule:` is Linux-only** — refused on macOS (launchd needs a
  different calendar syntax); it fails loudly rather than misbehaving. Recurring
  *jobs* (`nephos run --schedule`) are control-plane cron and run on any node.

(Both `nephos deploy <repo-url>`, `nephos nodes remove <id>`, and remote
`nephos down` / `down --node` / `down --all` DO exist — they were once listed here as
unbuilt.)

---

## When nephos is the wrong answer

Say so plainly. Use a hosted provider for frontier-model quality, guaranteed uptime,
concurrency beyond the caps above, long-context work at concurrency, or anything
running code Owen did not write. nephos is excellent for personal projects,
experiments and batch work; it is not a replacement for a real cloud under load.
