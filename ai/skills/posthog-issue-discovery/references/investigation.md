# Investigate one candidate

Read the entire candidate pasted into the conversation as evidence and leads, not an authoritative diagnosis. Investigate only that candidate unless another symptom is necessary to explain it. Do not request a handoff file, load every sibling candidate, or start another discovery sweep.

## Re-establish context

Confirm the current repository and PostHog project match the packet. Compare the current checkout with its inspected commit and note relevant uncommitted changes. Do not switch or reset the checkout to match the packet. Read root and local guidance and inspect current tool schemas; a saved tool name or query may no longer be supported.

If no candidate was pasted, ask for it. If the project cannot be accessed, ask for the missing access. Continue code investigation that does not depend on it, and identify which conclusions remain blocked.

## Independently verify

1. Re-run decisive queries using the original absolute bounds and definitions. Compare results with the recorded snapshot. Retention, ingestion delay, sampling, or changed definitions can explain differences; do not silently replace the original result.
2. Check a newer complete window separately to establish whether the symptom persists or has recovered. A recovered symptom may still be a real historical defect; describe current status separately from the diagnosis.
3. Trace the actual code path, callers, guards, types, instrumentation, and existing tests. Follow the evidence beyond the discovery agent's suggested file when needed.
4. Actively try to disprove the proposed cause. Check deliberate behavior, flags and experiments, configuration, segment mix, instrumentation errors, browser or upstream failures, and sampling. Treat temporal correlation with a deploy as a lead, not proof of causation.
5. Inspect relevant commits and PRs for intent and check current work in flight. A recent fix or open PR can change the next action without disproving the historical symptom.
6. Run existing focused tests or read-only reproductions when useful and permitted by the repository's environment rules. Do not generate traffic or writes against production to reproduce an issue. Report precisely what was and was not exercised.

Do not force a code fix for a product decision or data-quality issue. If two candidates share a cause, name the overlap for consolidation rather than proposing competing fixes.

## Verdict and next action

Return one primary diagnosis: **confirmed defect**, **intended behavior**, **instrumentation issue**, or **insufficient evidence**. State current status separately: ongoing, recovered, fixed, or work in flight. Include an **already addressed** disposition when existing work fully covers the required action, with its evidence.

Support the verdict with decisive data and code references, distinguish observed facts from remaining hypotheses, and explain any difference from the original packet. For a confirmed defect, identify the cause, smallest plausible fix, affected sibling paths, and a validation plan including a measurable PostHog outcome. For other verdicts, explain why a fix is unwarranted or what evidence is still needed.

Return the result in the conversation, with the candidate ID, current commit, query timestamps, and evidence. Do not write notes, handoffs, query results, or investigation reports to disk. Do not modify code, create issues or PRs, or publish research unless separately instructed.
