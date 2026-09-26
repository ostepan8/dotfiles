---
name: ship
description: Take finished work all the way out — commit, push, merge to main, deploy, roll the nephos binary to the fleet if it changed, clean up worktrees, and confirm what's live matches main. Use when Owen says "ship it", "/ship", "commit push and deploy", "push everything and handle it all", "merge to main", "get it onto main", "push it to prod", "did you distribute the binary". Do NOT run unasked — Owen decides per task whether to push.
---

# ship

Run only when asked. Owen pushes every change on some projects and holds changes on
others. Asking to ship is the signal. Having finished the work is not.

Go top to bottom and skip steps that don't apply. Stop and report at the first failure.
Don't work around it.

1. **Orient.** `git fetch origin && git status --short && git log --oneline origin/main..HEAD`.
   Also run `git worktree list` and check `git branch --no-merged origin/main` for
   feature branches that belong to this work.
2. **Commit** what belongs to this task, in conventional-commit form (`feat:`, `fix:`, …).
   Leave out files another session is editing: if something looks unrelated, ask about
   it rather than sweeping it in.
3. **Integrate.** Rebase or merge onto `origin/main` and fix any conflicts. Run the tests
   after resolving, not before.
4. **Push.** If the repo uses PRs (a GitHub remote plus a non-trivial branch): open the PR.
   The `pr-deslop` gate will run first. Then merge once CI passes. Otherwise push
   straight to main.
5. **Wait for CI.** `gh run watch` on the pushed commit. The `ci-gate` Stop hook blocks
   ending on a red run anyway.
6. **Deploy**, if the project deploys:
   - nephos service: `nephos deploy` **from a clean checkout at origin/main** (the
     deploy-gate refuses anything else). Confirm with `nephos ps` and one real request
     (curl the URL or health endpoint).
   - Vercel or another platform: its deploy command, then curl the URL.
7. **Fleet binary.** If the nephos repo changed, run `nephos self-update` and confirm every
   online node reports the new version.
8. **Dotfiles.** If anything under `~/dotfiles` changed, commit and push that repo too.
   It is separate.
9. **Clean up.** For each worktree whose branch is now merged: check
   `git -C <wt> status --porcelain` is empty, then `git worktree remove <wt>` and
   `git branch -d <branch>`, and finally `git worktree prune`.
10. **Report** in 3–5 lines: the commit SHA on main, what was deployed where, the live URL
    and its check result, and anything skipped with the reason.
