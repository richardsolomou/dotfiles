# Candidate handoff

Use this structure inside each candidate's single copy-paste code block. Keep it compact but independently reproducible. If a field is unavailable, state what is missing rather than filling it with an assumption. Do not write a packet to disk.

Start the block with `Use $posthog-issue-discovery investigate in <absolute repository root>. Independently verify the candidate below. Do not modify code or create issues or PRs.` Substitute the repository path, then include the following evidence in the same block.

## Identity

- Stable ID and symptom-focused title
- Discovery timestamp
- PostHog host, project ID, and project-to-application mapping evidence
- Absolute repository root, remote, branch, and inspected commit SHA
- Relevant uncommitted changes; if they affect the diagnosis, summarize the difference from the named commit
- Candidate status: awaiting independent investigation

## Symptom and impact

Describe the user-visible failure or measurable regression and why it warrants investigation. Include baseline and current values, units, affected population, denominator, onset, absolute time windows, aggregation timezone, and important segments. Separate facts from estimates. State identity and sampling limitations.

## Reproducible data evidence

For each decisive observation include:

- Evidence identifier such as `E1`, retrieval timestamp, and PostHog URL when available
- Exact successful query or tool call arguments, with project context and absolute date filters
- A compact table or result excerpt preserving the values supporting the claim
- What the result establishes and what it does not establish

Preserve the measured metric's definition, funnel order and conversion window, breakdowns, exclusions, cohort maturity, and any sampling settings relevant to reproducing it. Record bound parameters alongside parameterized queries. Evidence that cannot be reproduced should be labeled as such.

## Code leads

Name relevant file paths, symbols, and inspected line numbers at the recorded commit. Describe the code actually read and its connection to the symptom. Include relevant capture calls, flag checks, tests, and history. Distinguish a search hit from a traced execution path.

## Hypotheses and counterevidence

For each plausible explanation, state supporting evidence, counterevidence, and the observation that would distinguish it from alternatives. Explicitly record checks for intended behavior, experiments, configuration, upstream failures, and instrumentation defects. Do not present a guessed cause as confirmed.

## Existing work and gaps

Link relevant open or recently merged PRs, issues, and known fixes. Record what was searched and when, or that access prevented the check. List missing data, tool/access restrictions, and unanswered questions.

## Investigation assignment

Give the next agent a few concrete next steps and a measurable outcome that could validate a future fix. Avoid prescribing an implementation before the cause is established.

The assignment and all evidence belong in the same block. Do not ask the next agent to retrieve a handoff file or read the discovery conversation. Indent query examples or use plain labels rather than nested code fences.
