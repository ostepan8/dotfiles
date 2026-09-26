export const meta = {
  name: 'bug-swarm',
  description: 'Parallel bug hunt over a codebase or area, adversarially verified, optionally fixed',
  whenToUse: 'Owen says "spawn a swarm to find bugs", "swarm the code", "check the code for errors before we push". args: {target: "path or area", focus?: "extra instructions", fix?: true}',
  phases: [
    { title: 'Find', detail: 'one finder per lens' },
    { title: 'Verify', detail: 'a skeptic tries to refute each finding' },
    { title: 'Fix', detail: 'one agent fixes confirmed findings and runs tests' },
  ],
}

const target = (args && args.target) || 'the current repository (focus on recently changed code: git log -20, git diff origin/main)'
const focus = (args && args.focus) ? `\nExtra focus from Owen: ${args.focus}` : ''

const LENSES = [
  { key: 'correctness', ask: 'logic errors, wrong conditions, off-by-one, unhandled cases, broken invariants, state that can go stale' },
  { key: 'failure', ask: 'error handling: swallowed errors, missing timeouts, retries that never stop, partial writes, crashes on bad input or a down dependency' },
  { key: 'security', ask: 'authn/authz gaps, injection, secrets in code or logs, unsafe exposure on the public tunnel, path traversal' },
  { key: 'concurrency', ask: 'races, double-processing, leaks (goroutines, connections, file handles), unbounded queues or memory' },
]

const FINDINGS = {
  type: 'object',
  properties: { findings: { type: 'array', items: { type: 'object', properties: {
    file: { type: 'string' }, line: { type: 'integer' }, title: { type: 'string' },
    scenario: { type: 'string', description: 'concrete input/state -> wrong result' },
    severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
  }, required: ['file', 'title', 'scenario', 'severity'] } } },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: { real: { type: 'boolean' }, reason: { type: 'string' } },
  required: ['real', 'reason'],
}

const confirmed = (await pipeline(
  LENSES,
  l => agent(
    `Hunt for real bugs in ${target}. Lens: ${l.key} — ${l.ask}.${focus}\n` +
    `Read the code; do not guess. Report only defects with a concrete failure scenario. ` +
    `No style nits, no speculative "could be cleaner". Zero findings is a fine answer.`,
    { label: `find:${l.key}`, phase: 'Find', schema: FINDINGS }),
  r => parallel((r ? r.findings : []).map(f => () =>
    agent(
      `Try to REFUTE this reported bug. Read the code at ${f.file}${f.line ? ':' + f.line : ''} and its callers.\n` +
      `Claim: ${f.title}\nScenario: ${f.scenario}\n` +
      `real=false if the scenario cannot happen, is already handled, or you are unsure.`,
      { label: `verify:${f.file.split('/').pop()}`, phase: 'Verify', schema: VERDICT, effort: 'high' })
      .then(v => (v && v.real ? { ...f, why: v.reason } : null)))),
)).flat().filter(Boolean)

const order = { critical: 0, high: 1, medium: 2, low: 3 }
confirmed.sort((a, b) => order[a.severity] - order[b.severity])
log(`${confirmed.length} confirmed finding(s)`)

if (args && args.fix && confirmed.length) {
  phase('Fix')
  const summary = await agent(
    `Fix these verified bugs in ${target}. For each: make the smallest correct fix, add or extend a test that ` +
    `fails without it, and run the test suite. Do not commit or push. Report per finding: fixed / not fixed + why.\n\n` +
    JSON.stringify(confirmed, null, 2),
    { label: 'fix', phase: 'Fix' })
  return { confirmed, fixReport: summary }
}
return { confirmed }
