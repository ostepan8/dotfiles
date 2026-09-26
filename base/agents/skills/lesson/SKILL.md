---
name: lesson
description: Record a hard-won lesson where future agents will actually read it — repo docs, the right skill, or the dotfiles rules — then push it so every machine and session gets it. Use when Owen says "update the docs so we never make this mistake again", "so agents know", "write that down", "make sure this doesn't happen again", "update the skills", "put it in your agentic docs", or after a painful debugging session reveals a non-obvious fact.
---

# lesson

A lesson is only useful if the next agent reads it before it repeats the mistake. Put it
where that agent looks first, keep it short, and push it.

## 1. Write down the lesson itself

Two or three sentences: **what went wrong**, **the fact that would have prevented it**,
and **what to do instead**, with the date and the cost (e.g. "a deploy from a stale
branch rolled back the roku feature, 2026-09-19"). Include the concrete command or file.
Leave out any retelling of the session.

## 2. Choose where it goes (the narrowest place that the next agent will load)

| The lesson is about… | Put it in |
|---|---|
| one repo's code, build, deploy, or quirks | that repo's `CLAUDE.md`/`AGENTS.md`, or the doc it already points to (e.g. nephos `docs/`) |
| using nephos (deploy, jobs, db, inference) | `~/dotfiles/base/agents/skills/nephos/SKILL.md` |
| operating nephos (nodes, tiers, self-update) | `~/dotfiles/base/claude/keeper-skills/nephos-admin/SKILL.md` |
| a workflow rule for every project | `~/dotfiles/base/claude/rules/common/*.md` |
| a machine, tool, or setup fact | the matching skill (`tailnet`, `vault`, `fleet`…) |
| something that must never happen again and can be detected | propose a hook as well: docs get skipped, hooks don't |

Before adding a line, search for an existing one on the same subject and edit that
instead. Docs that contradict each other are worse than no docs.

## 3. Ship it

- Repo docs: commit (`docs: …`) and push, and merge to main. Agents on other branches only
  see what is on main. Owen has had to say "push the docs changes so agents know" more
  than once.
- Skills and rules: commit and push `~/dotfiles`, then install locally with `~/dotfiles/apply.sh`
  (or the `dotfiles-sync` skill) so this machine picks it up. Tell Owen that other
  machines get it on their next sync.

## 4. Confirm

One line: where the lesson went, and the commit.
