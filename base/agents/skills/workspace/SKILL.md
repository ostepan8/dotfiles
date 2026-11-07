---
name: workspace
description: >-
  Owen's project layout. A project is not only a repo: it is a workspace folder holding the
  repo plus agent docs, scripts, skills and worktrees. Use when creating or organizing a
  project's folder, starting a task in a workspace, adding a workspace script, skill or doc,
  when the repo root has no AGENTS.md around it, and for "set up a workspace", "make a dev
  environment for X", "where does this go", `ws`, `stack`, `scripts/wt`.
---

# workspace

A workspace is a plain folder around a repo. It keeps what agents need beside the code without
adding it to the repo.

```
<name>/
  AGENTS.md            what this is, its layout, its rules, how to run it
  CLAUDE.md            contains only @AGENTS.md
  docs/                notes for agents that don't belong in the repo
  scripts/
    wt                 scripts/wt <branch> creates a task worktree with env files
    stack              start | stop | status, if the project has servers
  .claude/skills/      skills for this workspace only
  repos/<repo>/        the main clone. Keep it clean on the base branch. Never edit here.
  worktrees/<repo>/
    dev/               the checkout that stack runs
    <branch>/          one per task. All edits happen here.
```

`~/workspaces/<name>` links to every workspace, and `s <name>` opens its tmux session there.

## Commands

```bash
ws ls                                         # list workspaces
ws new <name> <dir> <git-url> <base> --env-from <dir>   # create, or fill in what is missing
scripts/wt <branch>                           # start a task
stack start                                   # from any folder in the workspace
stack <name> status                           # from anywhere
```

`ws new` never overwrites a file, so running it again is safe.

## Where work goes

- Start every task with `scripts/wt <branch>`. Never edit `repos/` or `worktrees/<repo>/dev`.
- A note the next agent needs goes in `docs/`. A fact about the code goes in the repo's docs.
- A repeatable command goes in `scripts/`. A repeatable procedure goes in `.claude/skills/`.
- A Subconscious ticket that spans repos uses `sub` instead. See `subconscious-tickets`.

## Add a project with servers

1. Pick ports with the rules in the `studio-dev` skill.
2. Write `scripts/stack`. It must run servers in their own tmux session and keep them off
   production data.
3. Add the session and browser ports to `~/dotfiles/hosts/studio-ports.conf`.
4. Fill in `AGENTS.md`: how to run it, what it's safe to do, what is untested.

Workspaces are local files, not in git. Don't put secrets in `AGENTS.md`, `docs/` or `scripts/`.
