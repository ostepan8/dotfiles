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
nephos deploy ./svc --public api  # …and give it a public HTTPS hostname
nephos down <name>            # stop and remove, on whichever node runs it
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
nephos deploy .                             # source -> built on a node -> running
nephos logs myapp -f
```

A deploy builds automatically when the manifest names no `image:` and the
directory has a Dockerfile; `--build` only forces a rebuild over an explicit
`image:`.

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
# listenPort: 8080        # instead of ports:, for network: host or kind: process
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

**A `network: host` container or a `kind: process` workload declares
`listenPort:` instead of `ports:`** — it publishes no mapping, so without it
nephos knows of no port for the service and it cannot be reported, exposed on
the tailnet, or published with `--public`.

**If the app binds `0.0.0.0` (not `127.0.0.1`) on `network: host`, it also needs
`publishPort:`** — a different number from `listenPort`:

```yaml
network: host
listenPort: 8080      # what the app actually binds
publishPort: 18080    # what the tailnet/public route uses
```

Without it, nephos's own `tailscale serve` proxy claims the tailnet address at
that exact port, and the app's `0.0.0.0` bind collides with it (`EADDRINUSE`)
the moment it tries to start — a real incident, not a theoretical one. An app
that binds `127.0.0.1` specifically never hits this and doesn't need
`publishPort:` at all.

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

**Ports are exposed on the tailnet automatically.** They stay *bound* to
loopback — tailscale proxies to them — so a deploy prints where it can actually
be reached:

```
deployed myapp on node gpu2
  tailnet: 100.110.53.32:8000
```

If exposure fails the deploy still succeeds and says so, rather than reporting a
running service that nothing can connect to.

**`--public <name>` gives it an HTTPS hostname** through the shared Cloudflare
tunnel:

```bash
nephos deploy . --public myapp     # -> https://myapp.<zone>
```

A bare label gains the configured zone; a hostname outside that zone is refused
**before** the build runs, not after a service is already live under a name it
cannot be reached by. The origin is the node's tailnet address, so this works
from any node, not just the one running the tunnel.

`nephos down` removes the route and its DNS record along with the service, so a
torn-down service never leaves a hostname returning a bad gateway.

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

## Taking something down

```bash
nephos down myapp              # finds the node running it and stops it there
nephos down myapp --node gpu1  # when the same name runs in more than one place
nephos down myapp --all        # stop every copy
nephos down myapp --local      # this machine only, no control plane involved
```

Removes the unit, its secrets file, its tailnet exposure, its public route and
DNS record, and its capacity allocation. A name found on more than one node is
**refused** rather than guessed at — that means two nodes are serving different
versions of one thing, and picking silently is how a "stopped" service keeps
answering.

---

## When a service dies

If the control plane was started with `--ntfy-topic <topic>`, a real push
notification fires automatically whenever a service goes from `running` to
any other state — no polling, no separate daemon, hooked into the same
`nephos agent report` cycle every node already runs. A service's first-ever
sighting never fires (nothing to compare against yet), and a normal `nephos
down` never fires either (that's an intentional removal, not a crash). Get
the free ntfy app (iOS/Android), subscribe to the configured topic, done.

---

## Keeping nephos itself updated

```bash
nephos self-update build "$NEPHOS_CONTROL_ADDR"   # cross-compile + upload, once
nephos self-update fleet "$NEPHOS_CONTROL_ADDR"   # every OTHER node, over SSH
nephos agent self-update "$NEPHOS_CONTROL_ADDR"   # this machine, run directly (not through fleet)
```

`self-update build` derives which platforms to build for from whatever's
actually registered — no target list to maintain by hand. `self-update fleet`
loops over every registered node except the one you're running it from and
SSHes `agent self-update` to each — one node failing doesn't stop the rest.
`agent self-update` downloads that node's own build, verifies its checksum,
atomically replaces the binary currently running it, and best-effort restarts
whichever of that node's own nephos services are actually present. **Caveat**:
on the inference host specifically, this kills any nephos-managed LLM tier
(`fast` via mlx-lm) since it's a child process of the restarted agent — Ollama
is unaffected (manages its own lifecycle). Run `nephos llm up <alias>`
afterward if needed. A node with no self-update support yet (predates this
feature) still needs the old manual
`scp`+`install`+`systemctl restart` sequence once — after that, this handles
it.

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

- **No off-site backup** for the bulk disk.

`nephos deploy` also takes a repo URL now — `nephos deploy github.com/user/repo`
(or a full URL) shallow-clones it locally first, then runs the same `--build`
pipeline as a local directory. `nephos nodes remove <id>` forgets a rebuilt or
retired machine's registration (doesn't touch anything running there).

---

## When nephos is the wrong answer

Say so plainly. Use a hosted provider for frontier-model quality, guaranteed uptime,
concurrency beyond the caps above, long-context work at concurrency, or anything
running code Owen did not write. nephos is excellent for personal projects,
experiments and batch work; it is not a replacement for a real cloud under load.
