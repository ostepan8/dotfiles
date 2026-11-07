---
name: studio-dev
description: >-
  How Owen runs every project: code, agents and dev servers live on the Mac Studio, and the
  MacBook is only a screen. Use whenever a task starts, runs, previews or tests an app, a dev
  server, a simulator or an iPhone build, in ANY project (ListHalo, Subconscious platform,
  api-gateway, subconscious CLI, bench-runner, SGLang, or personal projects like nephos and
  jarvis). Also use when you run on the MacBook and need the Studio, when localhost or a
  Tailscale URL does not open on the MacBook, when an ssh or tmux connection drops, and for
  "run it on the studio", "open it on my laptop", "I'm on my macbook", `s`, `sf`.
---

# studio-dev

Everything runs on the Studio. The MacBook only views it, so a closed lid or a bad hotspot
drops the view and never stops the work.

## Which machine am I on

Run `cat ~/.dotfiles-host`. It prints `studio` or `macbook`.

- On `studio`: run things directly. To reach the MacBook, run `ssh macbook`.
- On `macbook`: don't start new work here. Run it through `ssh mac-studio`.
  A plain ssh command has no Homebrew on PATH, so use `ssh mac-studio 'zsh -lc "<cmd>"'`.

## What Owen types on the MacBook

| Command | What it does |
|---|---|
| `s` | Pick a Studio tmux session. Reconnects after a drop. |
| `s <name>` | Attach to that session, or create it, and open its ports. `C-a d` quits. |
| `sf 3000` | Open one more Studio port at `localhost:3000`. Rarely needed. |
| `sf 13000:3000` | The same, on a different MacBook port. |
| `sf` / `sf stop 3000` | List tunnels / stop one tunnel. |

`s` opens ports by itself, so Owen needs no second terminal. They come from
`~/dotfiles/hosts/studio-ports.conf`, or from `.sub/ports` for a ticket. If a project has a
server and no line there, add one with `dfw`. Only then tell Owen `sf <port>` for this time.

## Pick a port for a project

One port serves one app at a time, so a shared default like 3000 shows the wrong app.

1. Read `hosts/studio-ports.conf` and take the next free port from 4100 upward.
2. Check that nothing on the Studio holds it: `lsof -nP -iTCP:<port> -sTCP:LISTEN`.
3. Set the app to use that port in its own config.
4. Add the line to `hosts/studio-ports.conf`.

Never reuse 5173, 3001 or 8081, which ListHalo holds. Never use 40000 and up, which `sub`
tickets hold. If an app must keep a fixed port, for example for an OAuth callback, keep it
and note why in the config.

## Run each project

Start every command on the Studio.

| Project | Where | Start | Ports |
|---|---|---|---|
| ListHalo | `~/Desktop/ListHalo` | `~/Desktop/ListHalo/scripts/lh-stack start` | API 3001, web 5173, Metro 8081 |
| platform | `sub start <id> platform` | `PORT=$PLATFORM_WEB_PORT pnpm dev` in `platform/web` | from the ticket |
| api-gateway | `sub start <id> gateway` | `bash local-dev/dev.sh up` | from the ticket |
| subconscious CLI | `sub start <id> cli` | `npm test`, `bin/cli.js --version` | none |
| bench-runner | `~/Desktop/subconscious/benchmarks`, tmux session `benchmarks` | `bench-stack start` | website 4200, backend 4201, Redis 4202 |
| SGLang | `sub start <id> sglang` | no NVIDIA GPU here: sync to gpu1 or gpu2, see `fleet` and `nephos` | on the GPU box |
| Personal | `~/projects/<name>` or `~/Desktop/Projects` | the project's README, in `s <name>` | the project's |

For Subconscious, read the `subconscious-tickets` skill first. Ticket ports are in
`<ticket>/.sub/ports`. Never use default ports, because other tickets run at the same time.

For ListHalo, read `~/Desktop/ListHalo/AGENTS.md` first. Never push to `list-halo`. Other
`lh-stack` commands: `stop`, `status`, and `start --full`, which adds the job worker and the
Stripe listener. Those two can change the dev database.

## bench-runner safety

Use `bench-stack` for dev. The repo's `.env` points at the real remote Redis and R2, and the
backend reads that file unless `HARBOR_ENV_FILE` says otherwise. Never start the backend
from a checkout by hand. `bench-stack` has a local Redis, no R2, and no provider keys.
`bench-stack start --keys` adds runner keys, so real jobs can run and cost money. Ask Owen
first. `bench-stack update` moves the checkout to `origin/main`. For a ticket that changes
bench-runner, use `sub start <id> bench`, and set `BENCH_DIR` to its checkout.

## ListHalo on an iPhone

- Owen uses the app on the MacBook in its own simulator, "ListHalo Studio". It's the normal
  way, because Screen Sharing shows the whole Studio screen and feels janky.
  `s listhalo` opens the ports. Owen then opens Simulator and the ListHalo icon. Code changes
  arrive through Metro on the Studio. The simulator has no real camera.
- The MacBook can't build the app (Xcode 15.4). After a native change, build for the simulator
  on the Studio, copy `ListHalo.app` from DerivedData to the MacBook, and run
  `xcrun simctl install <udid> <app>` there. Run `simctl` on the MacBook with the simulator
  already booted, because booting from ssh fails with `could not bind to session`.
- Agents test in the simulator: `mobile/scripts/sim.sh shot home` in the repo, then read the image.
- The real phone needs a build first: `~/Desktop/ListHalo/scripts/lh-phone debug` for live
  reload, or `lh-phone release` to run without Metro.
- It is not Expo Go. The app has native modules.
- After install, the phone reaches the Studio over Tailscale from anywhere.

## When something breaks

| You see | Cause | Do this |
|---|---|---|
| "Reconnecting" in `s` | The connection dropped. The agents still run. | Wait up to about 20 seconds. Don't restart anything. |
| `s` window is gone | The terminal closed. | Run `s` again. The session is still there. |
| Agents are gone, shells remain | The Studio rebooted. tmux restores shells only. | Restart the agents. FileVault needs a login at the Studio first. |
| A Tailscale URL fails in the MacBook browser | The MacBook browser uses the work tailnet. | Use `sf`. Don't debug the app. |
| `localhost:<port>` is empty on the MacBook | No tunnel, or no app on the Studio. | Run `sf`, then check the app on the Studio. |
| `port N is in use` from `sf` | A MacBook app holds the port. | Use the `LOCAL:STUDIO` form that the error suggests. |
| Vite 403 on the Tailscale name | Vite blocks unknown hosts. | Start with `lh-stack`, which allows `.ts.net`. |
| `errSecInternalComponent` | A background shell can't use the signing key. | Run `lh-phone` from a tmux pane. |
| `0xe8008012` on install | The phone isn't on Apple team `TDDKV836MN`. | The first default `lh-phone` run registers it. Ask Owen first. |
| Install can't find the phone | Xcode doesn't install over Tailscale. | The phone must be unlocked and near the Studio. |
| `Cannot find native module` in the simulator | The installed app is older than the JS. | Rebuild: `pnpm --filter mobile ios`. |
| `gh` returns 401 | The login expired. | Owen runs `gh auth login -h github.com`. The vault token can't reach `subconscious-systems`. |
| A `sub` ticket's Claude asks for login | The work profile logged out. | Owen runs `ccdw`, then `/login`. |
| `dev.sh build` or `up` fails on ECR | The Studio has no AWS login. | Ask Owen, or run the gateway natively with cargo. |
| `dev.sh down` leaves containers | It ignores the `.env` project name. | `DEV_COMPOSE_PROJECT=gw-<ticket> bash local-dev/dev.sh down` |
| Containers run out of memory | Colima has 2 CPUs and 2 GB. | Ask Owen. A resize restarts the ListHalo containers. |
| bench-runner `/api/health` is 503 | `app/backend-go/bin/harbor` is missing. | Run `bench-stack setup`. Don't run the production sidecar installer. |
| A branch or repo isn't on the Studio | It may exist only on the MacBook. | Check `ssh macbook` before you rebuild it. |

## Rules

- Never switch the Studio's tailnet. If it leaves the personal tailnet, the MacBook loses it.
- Bare `sf stop` closes every tunnel, including ones you didn't open. Stop your own port.
- Don't suggest `pmset disablesleep` on the MacBook. It can overheat in a backpack, and the
  work belongs on the Studio anyway.
- These exist only on the MacBook: AWS, Azure, Kubernetes and gcloud logins, `subcon_gpu`, and
  `INVOICE_BANK_*`. Don't copy them. Ask Owen.
- Don't wipe MacBook repos. Many hold commits that aren't on GitHub or the Studio.
