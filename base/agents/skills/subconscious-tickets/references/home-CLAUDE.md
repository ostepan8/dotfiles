# Subconscious home

Owen's Subconscious work on the Mac Studio. Every ticket lives in its own folder
here. The `subconscious-tickets` skill and the `sub` command manage them.

- To start a ticket, run `sub start <id> <repos>`.
- To list tickets, run `sub ls`.
- To clean one up, run `sub done <id>`.
- Never work in `.repos/`. Those are the parent clones the worktrees grow from.
- Never edit `.env-store/` for one ticket. Edit the env file inside the worktree.

## Repos

| Repo | Alias | Base | What it is |
|---|---|---|---|
| `platform` | monorepo, web | dev | Web app, API, billing (Metronome, Stripe). Was `subconscious-monorepo`. Shared Neon database. |
| `api-gateway` | gateway | dev | OpenAI-compatible inference gateway: auth, keys, metering, dashboard, Helm. Local Postgres per ticket. |
| `subconscious` | cli | main | The `subconscious` CLI, examples and the marketing site. |
| `subconscious-code` | marathon | main | Our own coding-agent CLI (Rust). |
| `bench-runner` | bench | main | Benchmark runner (Harbor, SWE-marathon). |
| `SubconsciousCache-SGLang` | sglang | main | Our SGLang fork: the inference server. Needs a GPU box (gpu1/gpu2) to test. |
| `docs`, `ol-runbook`, `houston` | | main | Public docs, customer runbook, houston. |

## Common combos

| Kind of ticket | Repos |
|---|---|
| Platform / gateway (most tickets) | `platform gateway` |
| Harness | `cli gateway`, plus `marathon` when our CLI changes |
| Inference server | `gateway sglang` |
| Benchmarks | `bench cli marathon` |

## Rules for agents in a ticket folder

- Your ticket's `CLAUDE.md` lists the branch, base branches and ports. Use
  those ports, never the defaults. Up to 5+ tickets run at the same time.
- Open each PR against that repo's base branch (`dev` for platform and
  gateway, `main` for the rest).
- To add a repo, run `sub add <ticket> <repo>`. Never `git clone` or
  `git worktree add` by hand.
- Never remove worktrees, kill tmux sessions or run `sub done`. Owen does that.
