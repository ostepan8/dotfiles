# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Note: Attribution disabled globally via ~/.claude/settings.json.

## Before Branching

```bash
git fetch origin && git log --oneline HEAD..origin/main
```

Branch from `origin/main` (`git switch -c <name> origin/main`) unless the task explicitly
continues existing branch work. A branch cut from a stale checkout silently omits whatever
`main` gained since, and anything built on it duplicates or reverts that work.

See [development-workflow.md](./development-workflow.md) Step 0 for the full check,
including the migration-number collision it prevents.

## Worktree Hygiene

Worktrees are cheap to make and easy to forget. A stale one goes on looking like live work.

- Remove one as soon as its branch is merged: `git worktree remove <path>`, then
  `git worktree prune`.
- Before removing, confirm nothing would be lost: `git -C <path> status --porcelain` is
  empty **and** its HEAD is reachable from a pushed ref.
- Do a periodic `git worktree list` and check each path against those two tests.
- Build throwaway checkouts (verifying, deploying from `origin/main`) under the scratch
  directory, not in `~/projects`, and remove them in the same session.

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).
