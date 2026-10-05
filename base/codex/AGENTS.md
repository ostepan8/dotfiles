# Agent instructions

GENERATED FILE — do not edit by hand.
Regenerate with `base/codex/gen-agents-md.sh` after changing anything in
`base/claude/rules/common/`. Source of truth is those rule files, so Claude
(via rules/) and Codex (via this file) never drift apart.

<!-- from base/claude/rules/common/communication.md -->
# Communication

## The target: 80% of the way to ASD-STE100

Write every piece of prose at **80% of the way to ASD-STE100 (Simplified Technical
English)**. Short sentences, common words, explicit logic, no fluff.

ASD-STE100 is a controlled-English specification published by ASD (the AeroSpace,
Security and Defence Industries Association of Europe). The European airline industry
asked for it in the 1980s so that aircraft maintenance manuals read the same way to
every mechanic on earth, whatever their first language. Issue 9 is current. It holds
**53 writing rules in 9 sections** plus a dictionary of about **900 approved words** —
each locked to one meaning and one part of speech — and about **1,200 words to avoid**
with replacements.

It works because it removes the writer's freedom to be interesting. That is also why we
take 80% and not 100%. The 80% is the structure and the logic. The 20% we drop is the
closed vocabulary, which would make real technical work impossible to discuss.

## Scope

This governs prose: chat replies, commit messages, PR bodies, code comments,
documentation, plans, status reports, error messages.

It does **not** govern, and you never rewrite:

- Code, identifiers, file paths, flags, config keys
- Quoted command output, error text, logs, test failures
- Text the user wrote, or text you are quoting back
- Commit trailers and other machine-read lines

## The 80% we adopt

### Sentences

- **One idea per sentence.** One instruction per sentence, unless two actions truly
  happen at the same time.
- **20 words maximum** for an instruction. **25 words maximum** for a description.
- **Condition first, then the command, separated by a comma.** "If the build fails, run
  `make clean`." Not "Run `make clean` if the build fails."
- **No semicolons in prose.** Use two sentences, or `and`, `but`, `then`, `so`.
- Connect sentences with plain words: `and`, `but`, `then`, `so`, `as a result`.

### Paragraphs and lists

- One topic per paragraph. **6 sentences maximum.**
- Go from general to specific, one layer at a time. Do not open on the detail.
- Use a vertical list for 3 or more parallel items or steps.
- Keep list items grammatically parallel. Do not mix steps and descriptions in one list.

### Verbs

- **Active voice.** Imperative for anything the reader must do.
- Allowed forms: infinitive, imperative, simple present, simple past, simple future, and
  the past participle used as an adjective ("the configured value" is fine, and is not
  passive).
- **Banned: present perfect, past perfect, and every progressive tense.** Write "I fixed
  the binding", not "I have fixed the binding" and not "I am fixing the binding".
- **Banned: stacked auxiliaries + past participle** — "is to be run", "can be seen",
  "must be configured", "will be deleted". Rewrite active: "run it", "you can see",
  "configure it", "it deletes".
- **Use a verb, not a noun phrase.** "to configure the cache", not "for the
  configuration of the cache". "decide", not "make a decision".
- Reserve `-ing` for genuine nouns and modifiers (`a running process`). Never for tense.

### Words

- **One term per concept, every time.** Pick `worktree` or `checkout` and never alternate
  for variety. Varying the word is how a reader concludes there are two things.
- **Compound nouns: 3 words maximum.** Longer than that, define a short form once and
  reuse it.
- **No Latin abbreviations.** Not `e.g.`, `i.e.`, `etc.`, `via`. Write `for example`,
  `that is`, `and so on`, `through`.
- **Pronouns only when the reference cannot be misread.** A sentence that opens with
  "It" or "This" almost always needs the noun instead.
- **Avoid phrasal verbs whose meaning is not the sum of the parts** — unless the phrase
  is the established name for the thing. `roll back a migration` and `check out a branch`
  stay. "The build blew up" becomes "the build failed".
- Keep the conjunction `that` after `make sure`, `show`, `recommend`. "Make sure that the
  key is free."
- Gender-neutral throughout. They/them for a person whose pronouns you do not know.

### Risk

When you flag something destructive or hard to reverse, give three things in order: the
command or change, the damage it causes, and the condition under which it happens. Never
bury an instruction inside an aside. A note informs. It never instructs.

### Fluff to delete on sight

`Great question` · `I'll go ahead and` · `Let me just` · `Basically` · `Essentially` ·
`It's worth noting that` · `In order to` (write `to`) · `At this point in time` (write
`now`) · `Please note that` · `As you can see` · `Simply` · `Just` · restating the
question before answering it.

## The 20% we drop, on purpose

- **The 900-word approved dictionary.** Domain words win. Say `idempotent`, `rebase`,
  `symlink`, `coroutine`. Never swap the real name of a command or concept for an
  approved near-synonym — STE's own rule is that a technical noun or verb beats a
  paraphrase.
- **The ban on contractions.** `don't` and `it's` are shorter and read faster. Keep them.
- **The WARNING / CAUTION block format.** That is an aerospace manual convention.
- **Hard sentence-length limits inside code comments** where the code demands more.

## Checklist

Before sending prose, check:

- [ ] First line answers the question
- [ ] No sentence over 25 words, no instruction over 20
- [ ] Active voice, allowed tenses only
- [ ] No semicolons, no Latin abbreviations, no fluff phrases
- [ ] Same term for the same concept throughout
- [ ] Every `it` and `this` has one possible referent
- [ ] Conditions stated before their commands
- [ ] Code, output and quotes left exactly as they are

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

