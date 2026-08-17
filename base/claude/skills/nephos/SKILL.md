---
name: nephos
description: Owen's self-hosted personal cloud — deploy services, run LLM inference, store objects, and read logs across his own machines. Use whenever a task involves running an LLM without paying per token, needing S3-compatible storage, deploying a service or app, giving something a public HTTPS API, reading a service's logs, managing its environment variables, or asking what hardware is available. Trigger on "nephos", "my cloud", "my own API", "self-host this", "run it on my hardware", "where should this run", "deploy this", "ship this", "give it a public endpoint", "I need storage for this app", "check the logs", "set an env var for". Machine-specific addresses live in ~/.config/nephos/env — read that first, never hardcode them.
---

# nephos — Owen's personal cloud

Turns Owen's own machines into a cloud: deploy a service to whichever node fits,
serve LLM inference from an OpenAI-compatible endpoint, store objects over S3, and
read any service's logs from anywhere — private over Tailscale, public over
Cloudflare Tunnel.

**Read `~/.config/nephos/env` first.** It holds this machine's control-plane
address, endpoints, and node aliases. Those values are deliberately not in this file
— it ships in a public dotfiles repo. If that file is missing, nephos isn't set up
here; say so rather than guessing addresses.

---

## The commands

```bash
nephos nodes                  # every machine, its capabilities, free capacity
nephos ps                     # services across the fleet, grouped by node
nephos deploy ./svc           # pick a node that fits, dispatch, run
nephos deploy ./svc --dry-run # show the decision and why, without making it
nephos down <name>            # stop and remove (run ON the node running it)
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

## Deploying something

A manifest declares intent and never names a machine:

```yaml
schemaVersion: 1
name: myapp
project: myapp            # groups services for `nephos logs --project`
image: <registry>/myapp:v1
caps: [podman]            # hard requirements
resources:
  memory: 512Mi
  cpu: 1
  vram: 8Gi               # requesting VRAM IS requesting a GPU
ports: ["8080:8080"]
```

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
| `fast` | small model, high concurrency | short templated prompts, classification, extraction, volume |
| `big` | large model, low concurrency | when quality matters more than throughput |

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

- **`nephos deploy --build`** — building an image from source on a node. Today the
  image must already exist somewhere the node can pull from, so build on a Linux
  node and push to the fleet registry.
- **`nephos down` has no `--node`** — deploy is remote, teardown is local; ssh to
  the node running it.
- **No node-removal command** — a rebuilt machine leaves a ghost registration.
- **No off-site backup** for the bulk disk.

---

## When nephos is the wrong answer

Say so plainly. Use a hosted provider for frontier-model quality, guaranteed uptime,
concurrency beyond the caps above, long-context work at concurrency, or anything
running code Owen did not write. nephos is excellent for personal projects,
experiments and batch work; it is not a replacement for a real cloud under load.
