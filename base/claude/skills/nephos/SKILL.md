---
name: nephos
description: Owen's self-hosted personal cloud — inference, object storage, and service provisioning across his own machines. Use whenever a task involves running an LLM without paying per token, needing S3-compatible storage, deploying a small service, giving an app a public HTTPS API, or asking what hardware is available. Trigger on "nephos", "my cloud", "my own API", "self-host this", "run it on my hardware", "where should this run", "deploy this", "give it a public endpoint", "I need storage for this app". Machine-specific addresses live in ~/.config/nephos/env — read that first, never hardcode them.
---

# nephos — Owen's personal cloud

Turns Owen's own machines into a cloud: an OpenAI-compatible inference API, S3-compatible
object storage, and one-command service deployment — reachable privately over Tailscale and
publicly over Cloudflare Tunnel.

**Read `~/.config/nephos/env` first.** It holds this machine's endpoints, the control-plane
host, the binary path, and the node aliases. Those values are deliberately NOT in this file —
this skill ships in a public dotfiles repo. If that file is missing, nephos isn't set up on
this machine; say so rather than guessing addresses.

## Check what THIS machine may do, before proposing anything

Every machine gets this skill, but they are not equally privileged. Check the tier
first and scope your suggestions to it — proposing a provisioning step on a worker
node wastes a round trip on a command that is meant to fail.

```bash
nephos-role            # this machine's role and everything it permits
nephos-can provision   # test one action; exit 0 = allowed
```

Both read `~/dotfiles/roles/nephos-<tier>.role` — the same file the Tailscale ACL
and the control plane's `authorized_keys` restrictions are generated from. So if
`nephos-can` says no, the network says no too; they cannot disagree.

| Tier | Machine | May |
|---|---|---|
| `keeper` | Mac Studio | everything: mint and revoke credentials, deploy, admin |
| `operator` | MacBook | provision and deploy; holds no long-lived secrets |
| `node` | gpu1, gpu2, fedora, onephus | run workloads; use credentials it already has |

If the tier is `node` and the task needs provisioning, say so and suggest running it
from the Studio, rather than attempting it.

## How to invoke the CLI

**Use `nephos` directly.** A wrapper on `PATH` points `--control` at the fleet control
plane over the tailnet, so it works from scripts, cron and launchd too.

```bash
nephos nodes      # fleet + auto-detected capabilities
nephos ps         # running services
```

Only fall back to `ssh "$NEPHOS_CONTROL_HOST" "$NEPHOS_BIN ..."` when the local CLI is
genuinely missing — it adds a hop and needs sshd reachable even when the control API is.
The wrapper exits 127 with a clear message if the binary is not installed.

## Credentials

Fetch them into the shell; never write them to a file:

```bash
nephos-env <app>      # export this app's credentials into THIS shell
nephos-unenv          # clear them again
```

Only the keeper holds anything long-lived. Do not suggest writing a fetched key into
`.env`, a config file, or the repo.

---

## What it is

| Layer | Implementation |
|---|---|
| Network | Tailscale — every node on one private tailnet |
| Control plane | Single Go binary, `systemd --user` unit, always-on Linux node |
| Services | Rootless Podman + Quadlet units (Linux nodes only) |
| Inference | `mlx_lm.server` / `llama-server` / Ollama behind a gateway |
| Storage | MinIO, S3-compatible |
| Public access | Cloudflare Tunnel — no open ports, home IP hidden |
| Secrets | `~/.vault` (age/Keychain), never in the repo |

---

## Using it — the common cases

### Run inference instead of paying per token

```bash
nephos keys new <appname>
```

Then point any OpenAI SDK at `$NEPHOS_LLM`:

```python
client = OpenAI(base_url=NEPHOS_LLM, api_key=KEY)
client.chat.completions.create(model="fast", messages=[...])
```

**Two aliases, and picking wrong is the most common mistake:**

| Alias | Character | Use when |
|---|---|---|
| `fast` | ~4B model, high concurrency, ~270 tok/s aggregate | Short templated prompts, many at once, classification, extraction |
| `big` | Up to 120B MoE, ~71 tok/s, low concurrency | Quality matters more than throughput |

Aliases are the contract — the model behind one can change without breaking callers.

### Store things

S3-compatible at `$NEPHOS_S3`. Bucket per purpose, scoped key per app. `boto3`, `aws-sdk`,
and `aws s3` all work unmodified. Backed by a multi-terabyte disk on the Linux node.

**Do not store secrets there** — that disk is unencrypted. Secrets go in `~/.vault`.

### Deploy a service

Write a `nephos.yaml`, then **on the machine that should run it**:

```bash
ssh "$NEPHOS_CONTROL_HOST"
"$NEPHOS_BIN" up ./myservice
```

This one keeps the ssh hop on purpose, unlike the read-only commands above:
`up` takes a local directory path, so it has to run where those files actually
are. Do not "simplify" it to a bare `nephos up` from another machine.

Deploys a rootless Quadlet unit that survives reboot. It checks the machine's advertised
capabilities against the manifest's requirements first and fails clearly if they don't match.

Manifest supports `network: host` — needed when a container must reach a loopback-bound
origin on the same host, because rootless Podman otherwise can't.

### See what's there

```bash
nephos nodes    # fleet + auto-detected capabilities
nephos ps       # running services
nephos models   # configured tiers
nephos keys ls  # metadata only, never plaintext
```

---

## Nodes are a capability registry

Nodes advertise what they *have*; nothing is scheduled by hostname:

```
caps=[amd64, cuda, linux, podman, systemd]   resources=[vram:8GB, ram:94GB, disk:1860GB]
caps=[arm64, darwin]                          resources=[ram:96GB, cpu_cores:28]
caps=[amd64, cuda, windows]                   resources=[vram:8GB, ram:15GB]
```

Adding a node is one command on that machine. A node without `podman` simply never receives
container workloads — that's why the Windows node can serve GPU work but not host services.

---

## Real limits — check these before promising anything

**Inference concurrency is capped at 16 in flight, plus a 40,000 live-token budget** priced on
the *longest* prompt in flight:

```
longest_prompt × (in_flight + 1) ≤ 40,000
```

So ~16 short requests, but only ~9 at 4k tokens. Excess queues rather than failing. This is
not arbitrary — the MLX backend prices memory on the longest sequence in the batch, and
without this budget it OOM'd and served **0 of 48** requests under long-context load.

**Prompts over ~4,096 tokens route to the llama.cpp backend automatically.**

**Both inference tiers cannot run at full load simultaneously** — measured ~28 GB + ~58 GB
against a ~72 GB practical ceiling on a 96 GB machine.

**GPU VRAM is 8 GB on every CUDA node**, so GPU-side batching tops out around 4–8B models.
The Apple-silicon node is the inference workhorse *because of unified memory*, not despite
lacking CUDA.

**Isolation is uneven, and this matters for what you run:**
- Linux node: rootless Podman containers — namespaces, cgroups, unprivileged
- Apple-silicon node: inference servers are **plain processes, no sandbox at all**
- Tenants are separated by the gateway's API-key auth, **not** by an OS boundary

Fine for Owen's own apps. Never run untrusted third-party code on it.

**Availability is best-effort.** Home internet, consumer hardware, one control plane, no
off-site backup. Services restart automatically; a power cut still means downtime.

---

## Routing decisions

| Task | Where |
|---|---|
| LLM inference of any size | Apple-silicon node — far faster, unified memory holds big models |
| CUDA / containers / big scratch disk | Linux node |
| Concurrent small-model serving | `fast` tier |
| Anything needing real quality | `big` tier |
| Long-context work at concurrency | Neither — measured OOM. Serialize it. |

The naive "GPU work goes to the GPU box" rule is **wrong here**: the CUDA machines have 8 GB
of VRAM, the Apple-silicon machine has 96 GB of unified memory. Check `nodes` output rather
than assuming.

---

## Known gaps

- **`nephos up` is local-only** — it deploys to the machine you run it on. The registry knows
  every node's capabilities but the scheduler does not yet dispatch remotely. SSH to the
  target node and deploy there.
- No off-site backup for the bulk disk.
- The public tier depends on home internet and a single control plane.

---

## When nephos is the wrong answer

Say so plainly. Use a hosted provider when the work needs frontier-model quality, guaranteed
uptime, more than ~16 concurrent requests, long-context at concurrency, or when running code
you did not write. nephos is excellent for personal projects, experiments, and batch work —
it is not a replacement for a real cloud under load.
