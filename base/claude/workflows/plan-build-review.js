export const meta = {
  name: 'plan-build-review',
  description: 'Plan -> critique loop -> build -> review loop -> experiment -> results review, until accepted',
  whenToUse: 'Owen asks for "a graph of plan -> build -> review", "a counsel that loops until accepted", "keep iterating until there are no edits". args: {goal: "what to build and what done means", repo?: "path", maxPlanRounds?: 3, maxBuildRounds?: 5}',
  phases: [
    { title: 'Plan', detail: 'planner drafts, critics push back until approved' },
    { title: 'Build', detail: 'builder implements, reviewers loop until no blocking issues' },
    { title: 'Experiment', detail: 'run the measurement that proves it works' },
    { title: 'Results', detail: 'skeptical review of the evidence' },
  ],
}

if (!args || !args.goal) throw new Error('pass args: {goal: "..."}')
const repo = args.repo ? ` in ${args.repo}` : ''
const maxPlan = args.maxPlanRounds || 3
const maxBuild = args.maxBuildRounds || 5

const REVIEW = {
  type: 'object',
  properties: {
    approved: { type: 'boolean' },
    blocking: { type: 'array', items: { type: 'string' }, description: 'issues that must change; empty if approved' },
  },
  required: ['approved', 'blocking'],
}
const CRITICS = ['correctness and completeness against the goal', 'simplicity: is there a smaller design that works', 'testability: how will we PROVE it works, what is the baseline']

async function panel(subject, text, phaseName, round) {
  const votes = (await parallel(CRITICS.map((lens, i) => () =>
    agent(`Review this ${subject} for the goal: ${args.goal}\nYour lens: ${lens}.\n` +
      `Approve only if nothing blocking remains under your lens. Be concrete.\n\n${text}`,
      { label: `${phaseName.toLowerCase()}-critic${i + 1}-r${round}`, phase: phaseName, schema: REVIEW })))).filter(Boolean)
  const blocking = votes.flatMap(v => v.blocking)
  return { approved: votes.length > 0 && votes.every(v => v.approved), blocking }
}

phase('Plan')
let plan = await agent(`Write an implementation plan${repo} for: ${args.goal}\nRead the code first. Include: steps, files, ` +
  `the test/experiment that proves it works, and the baseline it must beat.`, { label: 'plan-r1', phase: 'Plan' })
for (let r = 1; r <= maxPlan; r++) {
  const rev = await panel('plan', plan, 'Plan', r)
  log(`plan round ${r}: ${rev.approved ? 'approved' : rev.blocking.length + ' blocking'}`)
  if (rev.approved) break
  plan = await agent(`Revise this plan to resolve every blocking issue.\n\nPLAN:\n${plan}\n\nBLOCKING:\n- ${rev.blocking.join('\n- ')}`,
    { label: `plan-r${r + 1}`, phase: 'Plan' })
}

phase('Build')
let build = await agent(`Implement this plan${repo}. Write tests alongside. Run them. Commit on a feature branch, do not push.\n\n${plan}`,
  { label: 'build-r1', phase: 'Build' })
let buildOk = false
for (let r = 1; r <= maxBuild; r++) {
  const rev = await panel('implementation (read the actual diff: git diff main...HEAD)', `Plan:\n${plan}\n\nBuilder report:\n${build}`, 'Build', r)
  log(`build round ${r}: ${rev.approved ? 'approved' : rev.blocking.length + ' blocking'}`)
  if (rev.approved) { buildOk = true; break }
  build = await agent(`Fix every blocking review issue${repo}, rerun tests, commit.\n\n- ${rev.blocking.join('\n- ')}`,
    { label: `build-r${r + 1}`, phase: 'Build' })
}
if (!buildOk) log(`build not approved after ${maxBuild} rounds; continuing to experiment with open issues`)

phase('Experiment')
const experiment = await agent(`Run the experiment the plan defines to prove the goal is met${repo}. Measure against the ` +
  `baseline. Report raw numbers, exact commands, and log paths. Do not round up a partial result.\n\nPlan:\n${plan}`,
  { label: 'experiment', phase: 'Experiment' })

phase('Results')
const verdict = await agent(`Skeptically judge whether this evidence shows the goal is met: ${args.goal}\n` +
  `Check the numbers against the baseline and look for gaps (missing baseline, too few runs, wrong metric).\n\n${experiment}`,
  { label: 'results-review', phase: 'Results', schema: REVIEW, effort: 'high' })

return { goalMet: verdict.approved, gaps: verdict.blocking, buildApproved: buildOk, plan, experiment }
