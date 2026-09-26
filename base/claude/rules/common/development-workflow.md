# Development Workflow

> This file extends [common/git-workflow.md](./git-workflow.md) with the full feature development process that happens before git operations.

The Feature Implementation Workflow describes the development pipeline: research, planning, TDD, code review, and then committing to git.

## Feature Implementation Workflow

### Step 0 — Orient in the repository _(before anything else, including research)_

**The first question is never "how do I build this", it is "does this already exist".**
A repo with several live branches merges to `main` many times a day, and the branch that
happens to be checked out may be hours behind. Run this before writing a line:

```bash
git fetch origin
git log --oneline origin/main -15                              # what has landed
git branch -r --sort=-committerdate | head -15                 # what is in flight
git log --oneline HEAD..origin/main                            # what you are missing
git log --all --oneline --since=7.days -- <area you will touch> # who else touched it
```

Rules that follow from it:

- **If the work already exists on `origin/main` or another `origin/*` branch, stop and say
  so.** Do not rebuild it. Reconciling two implementations costs more than either.
- **Branch from `origin/main`, not from whatever is checked out** — unless the task
  explicitly builds on that branch. `git switch -c <name> origin/main`.
- **Never deploy from a branch that is behind `origin/main`.** Deploying rolls back
  everything `main` has that your branch lacks. Check `git log HEAD..origin/main` is empty,
  or deploy from a clean checkout of `origin/main`.
- **Numbered, shared-namespace files are locks** — SQL migrations above all, but also
  ordered fixtures and numbered configs. Two branches that both add `0005_*` collide
  silently: the second is skipped because the version is already recorded, and the code
  then runs against a schema it did not create. Before adding one, `git log --all --
  <migrations dir>` and take the next free number across **all** refs, not just yours.
- **An installed tool's `--help` is not evidence about the source.** A locally installed
  binary can be hundreds of commits behind `origin/main`, so a missing subcommand means
  *this build* lacks it — not that it was never written. Check the tree, not the CLI:

  ```bash
  git ls-tree -r origin/main --name-only | grep -i <feature>
  git log --all --oneline --grep=<feature> -i
  ```

  Only after both come back empty is the feature genuinely absent. When they disagree
  with the installed tool, rebuild/redistribute it (for nephos: `nephos self-update`)
  before trusting any further capability check from that binary.

  > Cost of skipping this: `nephos db --help` showed no `restore` subcommand, which was
  > reported as a missing capability and nearly became a subagent task. `origin/main`
  > already carried `cmd/db_restore.go`, `db_restore_apply.go`, `db_restore_credential.go`
  > and five test files. The checkout was 284 commits behind and the installed binary
  > older still.

1. **Research & Reuse** _(mandatory before any new implementation)_
   - **GitHub code search first:** Run `gh search repos` and `gh search code` to find existing implementations, templates, and patterns before writing anything new.
   - **Library docs second:** Use Context7 or primary vendor docs to confirm API behavior, package usage, and version-specific details before implementing.
   - **Exa only when the first two are insufficient:** Use Exa for broader web research or discovery after GitHub search and primary docs.
   - **Check package registries:** Search npm, PyPI, crates.io, and other registries before writing utility code. Prefer battle-tested libraries over hand-rolled solutions.
   - **Search for adaptable implementations:** Look for open-source projects that solve 80%+ of the problem and can be forked, ported, or wrapped.
   - Prefer adopting or porting a proven approach over writing net-new code when it meets the requirement.

2. **Plan First**
   - Use **planner** agent to create implementation plan
   - Generate planning docs before coding: PRD, architecture, system_design, tech_doc, task_list
   - Identify dependencies and risks
   - Break down into phases

3. **TDD Approach**
   - Use **tdd-guide** agent
   - Write tests first (RED)
   - Implement to pass tests (GREEN)
   - Refactor (IMPROVE)
   - Verify 80%+ coverage

4. **Code Review**
   - Use **code-reviewer** agent immediately after writing code
   - Address CRITICAL and HIGH issues
   - Fix MEDIUM issues when possible

5. **Commit & Push**
   - Detailed commit messages
   - Follow conventional commits format
   - See [git-workflow.md](./git-workflow.md) for commit message format and PR process
