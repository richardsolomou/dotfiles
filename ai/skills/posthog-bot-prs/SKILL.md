---
name: posthog-bot-prs
description: "Review posthog[bot] PRs awaiting the user's or their team's review. Delegate reviews, give the gist, and carry authorized fixes, approvals and Trunk submissions through to merge. Use for the bot review backlog, not all open PostHog PRs."
---

# PostHog bot PR backlog

Coordinate the backlog; use existing skills for individual reviews, fixes and merge-queue work. Keep code verdicts separate from merge gates.

## Establish the set

Use supplied PRs first. Otherwise discover review requests rather than using the current checkout's PR. Search direct requests and requests to the user's current teams, found with `gh api user/teams --paginate`:

```bash
gh search prs --author 'posthog[bot]' --review-requested @me --state open --limit 100 --json number,title,url,repository,isDraft
```

Repeat for relevant `ORG/TEAM` reviewers within the requested organizations or repositories. Deduplicate by repository and number, handle result limits, and confirm candidates through the PR API because search can lag. An unrestricted author search includes unrelated repositories. Report drafts separately; work on drafts or assigned-only PRs only when requested.

Freeze this set for the pass. Inspect native-stack dependencies, distinguishing review targets from additional layers that need review or changes. Link every target and relevant layer to the thread when host linking is available.

Record authorization alongside the set:

| Request | Authorized work |
| --- | --- |
| Review / give me the gist | Read-only review and recommendations. |
| Fix the findings | Review, then correct; follow repository commit and push rules. |
| Approve | Approve the identified PRs at their reviewed heads. |
| Merge / send `/trunk merge` | Submit the identified PRs or stacks through Trunk and monitor to merge or a concrete blocker. Approve only if also authorized. |

"Ready", "babysit" and "clear the backlog" do not supply merge permission. Preserve explicit authorization across corrections, restacks and later turns. Obtain missing authorization for dependency mutations or merges after making the review or correction concrete. Approval and merge permission do not authorize unsolicited review comments or replies. Later arrivals need their own mutation and merge authorization; do not continually discover new work or schedule recurring runs unless requested.

Keep a compact ledger: URL, full head SHA, true base/merge-base, stack position, findings and verdict, validation limits, merge gates, authorization, corrective pushes, retries, submission and watch state. Recheck GitHub before mutations and final claims.

## Review and give the gist

Delegate independent PRs or small related batches; give a whole stack to one worker when its contracts span layers. Preserve the selected model and runtime options through the available orchestrator. If delegation is unavailable, review sequentially and say so.

Give each worker the URLs, immutable heads/bases, known findings and responses, and this brief:

- Use `review-pr` for one combined, read-only pass per PR, including relevant security scrutiny. Read discussion and affected callers, tests and backend/generated contracts; separate new findings from unresolved existing ones. Return only verified findings; no findings is a valid result.
- Review each layer against its true parent and inspect the dependency chain. A clean child does not clear a broken or unreviewed parent.
- Return the purpose, reviewed head/base, findings with anchors and concrete failure cases, approval recommendation, separate merge gates, tests run and verification gaps.
- Do not edit, post, approve, enqueue, watch, poll or delegate further. Recheck the head before returning; a moved head needs review of its delta before clearance.

Validate returned findings and reconcile coverage. Report one concise row per PR with its purpose, code verdict, changes needed and merge gates; group into **ready on code**, **needs changes** and **needs verification** when useful. Trace CI failures before calling them code defects. A bot's policy refusal is separate from correctness, and an agent review is not independent human assurance.

Stop here for review-only requests. Otherwise proceed with authorized corrections. External findings, replies, reactions and resolutions follow the user's authorization and repository rules.

## Fix and approve

Assign each branch or stack to one implementation owner in an isolated worktree. The parent owns approvals, queue actions and watchers. Use `ship`, `update-pr`, `restack` and repository preflight instructions for those operations; make new commits for review rounds and batch related fixes into one corrective push. Run PostHog development commands through `.codex/with-flox` from that worktree's root, using its dependencies. Leave unrelated stacks and shared services alone.

Before changing a queue-held branch, cancel its submission and confirm every affected layer is inactive. Failed batches may still be held while Trunk bisects or waits for other tests.

For generated-contract failures, reproduce the synthetic merge's failure and use the real generation pipeline. Refresh the affected base if master introduced interacting tools or schemas; check the full relevant catalogue, not just the named tool. Compare each layer's own diff before and after restacking to preserve earlier fixes, then verify native-stack structure, actual bases and remote heads.

Run relevant repository checks and regression coverage. Exercise rendered changes in an owned environment; distinguish mocked Storybook evidence from live backend behavior. Report validation limits accurately.

Review the correction delta and affected contracts against every earlier finding, rather than restarting the whole review swarm. Before an authorized approval, confirm the remote head still matches and bind the approval to that full SHA. An older visible approval does not establish review of a newer head.

## Submit and resume on events

Use `merging-prs` for authorized PostHog merges: Trunk CLI first, `/trunk merge` as the unavailable/unauthenticated CLI fallback, submitting native stacks from the top. Confirm acknowledgement. Distinguish submitted, testing and merged.

Use one host watcher per needed PR, end the turn, and resume on events. Compare each event and current head with the ledger. Test-count badges and rising passing-check counts usually need no action; report meaningful findings, fixes, blockers, retries and merges.

- **Feedback:** verify against current code and deduplicate summaries/inline findings. Repeating an approval-bot label does not resolve a policy refusal. An incomplete optional scanner is not a code finding or grounds for a dummy commit; check whether it gates merging.
- **CI:** use `debugging-ci-failures`. Inspect the actual failing jobs across all matrix pages or Depot jobs, not just aggregate gates or analytics badges. Earlier failed attempts can coexist with passing final gates; zero uploaded failures can hide setup or artifact failures. For apparently stuck jobs, check provider state, logs and timeouts, then use scoped recovery and rerun dependent gates as required.
- **Queue:** use `triaging-merge-queue-failures` against the shadow SHA, batch and prefix. Cancelled gates may be fallout; inspect the original failure. Do not resubmit while Trunk holds the batch. Allow one infrastructure retry per head/workflow, counting automatic retries in the ledger; repeated failure needs diagnosis. Generated-contract drift needs a correction, not an infrastructure retry.

Confirm every original PR and stack layer through GitHub before reporting completion. A closed shadow PR or "will merge soon" message does not establish a merge; a parent can land before its child. Stop watches for merged/closed PRs. While CI or Trunk is pending, retain only needed watches and end the turn. When handing work back, stop remaining watches, reconcile linked PRs, and report merged counts, ready-but-unsubmitted PRs, blockers and validation limits, separating later arrivals from the original set.
