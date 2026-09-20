# Agent instructions

GENERATED FILE — do not edit by hand.
Regenerate with `base/codex/gen-agents-md.sh` after changing anything in
`base/claude/rules/common/`. Source of truth is those rule files, so Claude
(via rules/) and Codex (via this file) never drift apart.

<!-- from base/claude/rules/common/coding-style.md -->
# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing ones:

```
// Pseudocode
WRONG:  modify(original, field, value) → changes original in-place
CORRECT: update(original, field, value) → returns new copy with change
```

Rationale: Immutable data prevents hidden side effects, makes debugging easier, and enables safe concurrency.

## File Organization

MANY SMALL FILES > FEW LARGE FILES:
- High cohesion, low coupling
- 200-400 lines typical, 800 max
- Extract utilities from large modules
- Organize by feature/domain, not by type

## Error Handling

ALWAYS handle errors comprehensively:
- Handle errors explicitly at every level
- Provide user-friendly error messages in UI-facing code
- Log detailed error context on the server side
- Never silently swallow errors

## Input Validation

ALWAYS validate at system boundaries:
- Validate all user input before processing
- Use schema-based validation where available
- Fail fast with clear error messages
- Never trust external data (API responses, user input, file content)

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Functions are small (<50 lines)
- [ ] Files are focused (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Proper error handling
- [ ] No hardcoded values (use constants or config)
- [ ] No mutation (immutable patterns used)

<!-- from base/claude/rules/common/testing.md -->
# Testing Requirements

## Minimum Test Coverage: 80%

Test Types (ALL required):
1. **Unit Tests** - Individual functions, utilities, components
2. **Integration Tests** - API endpoints, database operations
3. **E2E Tests** - Critical user flows (framework chosen per language)

## Test-Driven Development

MANDATORY workflow:
1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Verify coverage (80%+)

## Troubleshooting Test Failures

1. Use **tdd-guide** agent
2. Check test isolation
3. Verify mocks are correct
4. Fix implementation, not tests (unless tests are wrong)

## Agent Support

- **tdd-guide** - Use PROACTIVELY for new features, enforces write-tests-first

<!-- from base/claude/rules/common/security.md -->
# Security Guidelines

## Mandatory Security Checks

Before ANY commit:
- [ ] No hardcoded secrets (API keys, passwords, tokens)
- [ ] All user inputs validated
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (sanitized HTML)
- [ ] CSRF protection enabled
- [ ] Authentication/authorization verified
- [ ] Rate limiting on all endpoints
- [ ] Error messages don't leak sensitive data

## Secret Management

- NEVER hardcode secrets in source code
- ALWAYS use environment variables or a secret manager
- Validate that required secrets are present at startup
- Rotate any secrets that may have been exposed

## Security Response Protocol

If security issue found:
1. STOP immediately
2. Use **security-reviewer** agent
3. Fix CRITICAL issues before continuing
4. Rotate any exposed secrets
5. Review entire codebase for similar issues

<!-- from base/claude/rules/common/git-workflow.md -->
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

<!-- from base/claude/rules/common/development-workflow.md -->
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

<!-- from base/claude/rules/common/patterns.md -->
# Common Patterns

## Skeleton Projects

When implementing new functionality:
1. Search for battle-tested skeleton projects
2. Use parallel agents to evaluate options:
   - Security assessment
   - Extensibility analysis
   - Relevance scoring
   - Implementation planning
3. Clone best match as foundation
4. Iterate within proven structure

## Design Patterns

### Repository Pattern

Encapsulate data access behind a consistent interface:
- Define standard operations: findAll, findById, create, update, delete
- Concrete implementations handle storage details (database, API, file, etc.)
- Business logic depends on the abstract interface, not the storage mechanism
- Enables easy swapping of data sources and simplifies testing with mocks

### API Response Format

Use a consistent envelope for all API responses:
- Include a success/status indicator
- Include the data payload (nullable on error)
- Include an error message field (nullable on success)
- Include metadata for paginated responses (total, page, limit)

