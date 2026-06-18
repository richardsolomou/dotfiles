export const meta = {
  name: 'rs-autopilot',
  description: 'Build a feature autonomously, then converge it through fresh-context adversarial reviews; hand back a ship-ready working tree.',
  phases: [
    { title: 'Build', detail: 'one agent implements the feature + tests in the working tree' },
    { title: 'Review', detail: 'fresh-context rs-reviewers find issues (parallel, read-only)' },
    { title: 'Resolve', detail: 'one agent applies/rejects findings in place' },
  ],
}

const {
  feature,
  base = 'main',
  maxRounds = 3,
  reviewers = 3,
} = args || {}

if (!feature) throw new Error('rs-autopilot: args.feature is required')

// Each reviewer gets a distinct lens so the panel covers different failure modes
// rather than three agents finding the same surface issues. They still report
// anything real outside their lens.
const LENSES = [
  {
    key: 'correctness',
    focus:
      'Correctness and edge cases: nil/empty/boundary inputs, inverted conditions, error handling, concurrency and failure, partial writes, off-by-ones.',
  },
  {
    key: 'tests',
    focus:
      'Test quality and coverage: untested behaviour, tautological or over-mocked tests, missing edge-case tests, assertions on implementation rather than observable behaviour.',
  },
  {
    key: 'design',
    focus:
      'Design and convention: scope creep, coupling and hidden dependencies, naming and clarity, drift from existing patterns in this repo.',
  },
]

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['file', 'title', 'whatsWrong', 'proposedFix'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          title: { type: 'string', description: 'one-line gist of the finding' },
          whatsWrong: { type: 'string' },
          proposedFix: { type: 'string' },
        },
      },
    },
  },
}

const BUILD_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'filesChanged'],
  properties: {
    summary: { type: 'string', description: 'what was built, 2-4 sentences' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    testsRun: { type: 'boolean', description: 'whether the project tests were run and pass' },
  },
}

const RESOLVE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['applied', 'rejected'],
  properties: {
    applied: { type: 'array', items: { type: 'string', description: 'title of an applied finding' } },
    rejected: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'reason'],
        properties: { title: { type: 'string' }, reason: { type: 'string' } },
      },
    },
  },
}

// ── Phase 1: Build ───────────────────────────────────────────────────────────
phase('Build')
const build = await agent(
  `You are implementing a feature autonomously on the currently checked-out git branch. The working tree is yours to modify.

Feature request:
${feature}

Follow the engineering guidelines in ~/.claude/CLAUDE.md and any repo-level CLAUDE.md: study existing patterns first, write tests, keep the change minimal and idiomatic. Steps:
1. Read the relevant parts of the codebase and the project README / CLAUDE.md before writing anything.
2. Implement the feature with tests covering the main behaviour and the edge cases.
3. Run the project's tests and formatter (\`bin/fmt\` if present, otherwise the language formatter). Fix anything they flag.
4. Leave all changes UNCOMMITTED in the working tree. Do not commit, push, or open a PR — a later step ships the whole change as one commit.

Your returned summary is data for an orchestrator, not a message to a human. Be factual.`,
  { phase: 'Build', schema: BUILD_SCHEMA },
)

if (!build) return { ok: false, stage: 'build', reason: 'build agent failed' }
log(`Build: ${build.summary}`)

// ── Phase 2: Review → Resolve, loop until dry ────────────────────────────────
const seen = new Set()
const history = []
let converged = false

const key = (f) => `${f.file}::${(f.title || '').trim().toLowerCase()}`

for (let round = 1; round <= maxRounds; round++) {
  phase('Review')
  const reviews = await parallel(
    LENSES.slice(0, reviewers).map((lens) => () =>
      agent(
        `Review the uncommitted changes in this working tree. They are NOT yet committed.

See them with:
\`\`\`
git diff ${base}
\`\`\`
Then read the full changed files in the working tree — not just the hunks.

Lens for this pass — weight your attention here, but report anything real you find outside it: ${lens.focus}

Verify each candidate (construct the concrete failing scenario) before it becomes a finding. Return only findings that survive verification and meet the defensibility bar; skip anything a formatter would fix. If you cannot break it, return an empty findings array.`,
        { label: `review:${lens.key}`, phase: 'Review', agentType: 'rs-reviewer', schema: FINDINGS_SCHEMA },
      ),
    ),
  )

  const roundSeen = new Set()
  const fresh = []
  for (const f of reviews.filter(Boolean).flatMap((r) => r.findings || [])) {
    const k = key(f)
    if (seen.has(k) || roundSeen.has(k)) continue
    roundSeen.add(k)
    fresh.push(f)
  }

  if (fresh.length === 0) {
    converged = true
    log(`Round ${round}: no new findings — converged.`)
    break
  }
  fresh.forEach((f) => seen.add(key(f)))
  log(`Round ${round}: ${fresh.length} new finding(s).`)

  phase('Resolve')
  const resolved = await agent(
    `You are resolving review findings in the current working tree (changes are uncommitted; leave them uncommitted).

For each finding, decide if it is real and defensible. Apply a fix for the real ones by editing the code. Reject ones that don't survive scrutiny and state why — you are allowed to disagree with a reviewer; apply the "consuming feedback" posture from ~/.claude/skills/rs-adversarial-review/SKILL.md. Rejecting a weak finding is correct; do not apply churn to satisfy a nitpick.

After editing, re-run the project's tests and formatter and fix any breakage. Do not commit or push.

Findings (JSON):
${JSON.stringify(fresh, null, 2)}

Return the titles you applied and the ones you rejected with reasons.`,
    { phase: 'Resolve', schema: RESOLVE_SCHEMA },
  )

  history.push({
    round,
    found: fresh.length,
    applied: resolved?.applied || [],
    rejected: resolved?.rejected || [],
  })
  log(`Round ${round}: applied ${resolved?.applied?.length || 0}, rejected ${resolved?.rejected?.length || 0}.`)
}

return {
  ok: true,
  base,
  converged,
  rounds: history,
  totalApplied: history.reduce((n, r) => n + r.applied.length, 0),
  totalRejected: history.reduce((n, r) => n + r.rejected.length, 0),
  build,
}
