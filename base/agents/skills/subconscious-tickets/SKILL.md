---
name: subconscious-tickets
description: "Start, list and clean up Subconscious work tickets on the Mac Studio. Each ticket is a folder under ~/Desktop/subconscious holding one git worktree per repo it touches (platform, api-gateway, subconscious CLI, subconscious-code/marathon, bench-runner, SGLang), with env files, its own ports, its own gateway database and a tmux session with a fresh Claude. Use when Owen says 'do SUBCON-670', 'start a ticket', 'pick up subcon-NNN', 'what tickets are open', 'show tickets', 'done subcon-NNN', 'clean up that ticket', or works on any Subconscious repo on the Studio."
---

# subconscious-tickets

One folder per ticket. Inside it, one worktree per repo the ticket touches, all
on the same branch. The whole thing is one script: `sub` (on PATH, from
`scripts/sub.sh`).

```
~/Desktop/subconscious/
  CLAUDE.md        repo map (references/home-CLAUDE.md) - read it first
  .repos/<repo>/   parent clones. Never work in these.
  .env-store/      one env set per repo, copied into each new worktree
  .slots/<n>/      port slot claims (one per live ticket)
  subcon-670/      a ticket
    CLAUDE.md      generated: branch, base branches, ports
    api-gateway/   worktree
    platform/      worktree
```

## Start a ticket ("do SUBCON-670")

You are the kickoff session. Set the ticket up, hand it off and stop. Do not do
the ticket's work yourself.

1. Run `sub ls`. If the ticket is already there, run `sub start <id>` with no
   repos. It reattaches, or restarts the session if it died. Then stop.
2. Read the ticket. If a Linear tool is connected, take its title,
   description and `gitBranchName`. If not, ask Owen for the repos and use the
   ticket id as the branch.
3. Pick the repos from the ticket. Use the combos in the root `CLAUDE.md`. If
   it is unclear, ask Owen. Don't guess wide: extra worktrees cost disk.
4. Run:
   ```bash
   sub start SUBCON-670 platform gateway \
     --branch "<gitBranchName from Linear>" \
     --prompt "<ticket title + description, then Owen's instructions for how far to go>"
   ```
   It opens a tmux session named `subcon-670` with Claude started in the
   ticket folder. If Owen said how far to go (plan only, through draft PR, and
   so on), put that in `--prompt`. Otherwise end the prompt with "Ask Owen how
   far to take this before you push."
5. Tell Owen the folder, the branch and whether a PR already exists. `sub start`
   prints all three.

`sub start` never cuts a second branch for a ticket that exists:

- Folder exists: it reuses the folder and branch.
- Branch exists on origin: it continues that branch. With no `--branch`, any
  origin branch named `<id>` or `<id>-*` counts. Linear names branches that way.
- PR exists: it prints the PR state. Pass that on to the new agent.

## Add a repo mid-ticket

`sub add subcon-670 sglang`. It is the same branch and env setup, and it
rewrites the ticket `CLAUDE.md`.

## Show tickets

`sub ls` shows each ticket's branch, port slot, whether its tmux session is
live and, per repo, the PR state, uncommitted files and unpushed commits.
`READY TO CLEAN` means every PR merged and nothing is uncommitted. Point those
out to Owen. Cleanup only happens on command.

## Clean up ("done subcon-670")

`sub done subcon-670`

It refuses, and changes nothing, if any worktree has one of these problems.
The session keeps running.

- Uncommitted changes
- An env file edited since it was copied
- A switch off the ticket branch
- Commits not on GitHub
- A PR that is not merged

If the only problem is an unmerged PR, ask Owen. Run `sub done <id> --force`
only after a yes. `--force` never overrides the other checks.

Teardown order:

1. Only that ticket's tmux session is killed, so no agent writes during
   teardown. Never kill the tmux server.
2. Gateway compose stack down, and its volume dropped.
3. Worktrees removed. Each is re-checked first, and git refuses a dirty one.
4. Merged local branches deleted.
5. Ticket folder removed and port slot freed.

## Ports and databases

Each ticket gets a slot N. Its ports are 40000 + 100·N + offset. They are in
`<ticket>/.sub/ports`, in the ticket `CLAUDE.md`, and exported into its tmux
session.

- **Platform web:** `PLATFORM_WEB_PORT`. It uses the shared Neon database from
  `web/.env`, so there is nothing per ticket.
- **Gateway:** `local-dev/.env` gets `DEV_COMPOSE_PROJECT=gw-<ticket>` and the
  `DEV_*` ports. `bash local-dev/dev.sh up` then runs a private Postgres and
  Valkey. `sub done` drops them.

## Env files

`~/Desktop/subconscious/.env-store/<repo>/<path>` is copied into every new
worktree of that repo. It is never overwritten if the file is already there.
To change an env for future tickets, edit the store. `SOURCES.tsv` records
where each file came from. The full MacBook backup is in
`~/.local/share/subconscious-env-backup/`.

## SGLang

The Studio has no NVIDIA GPU. To test an SGLang worktree, sync it to gpu1 or
gpu2 (see the `fleet` and `nephos` skills).

## Settings

| Variable | Default |
|---|---|
| `SUB_HOME` | `~/Desktop/subconscious` |
| `SUB_CMD` | `ccdw`: the Claude profile launched in the session. `--cmd ccd` per run. |
| `SUB_REMOTE` | `git@github.com:subconscious-systems` |

## Tests

`bash scripts/sub_test.sh` runs start, add, ls, done and tmux against
throwaway local repos. Run it after any edit to `sub.sh`.
