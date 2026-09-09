---
name: rs-pr-shepherd
description: "Maintain an open PR after creation by reacting to failing CI, merge conflicts, new review feedback, and approval-bot results. Each invocation makes at most one corrective push batch and then stops. Use when the user says 'shepherd this PR', 'babysit this PR', or wants CI and review feedback handled automatically. Pass deep only when the user also wants one independent self-review pass."
argument-hint: "[pr-url|pr-number] [deep]"
---

# PR Shepherd

Keep an open PR moving without creating an open-ended review loop. GitHub events supply the work. The shepherd does not search repeatedly for more work after it changes the branch.

One invocation handles the current actionable events, makes at most one corrective push batch, and stops. An outer `/loop` can invoke it again to observe later CI or reviewer activity. The skill never sleeps, polls after a mutation, or invokes itself.

## Boundaries

- Make at most one corrective push batch per invocation. Batch CI fixes, review fixes, and conflict resolution before that push.
- Do not self-review by default. When the user passes `deep`, run `rs-review-pr` once in self mode with one second opinion.
- In `deep` mode, review only the HEAD that existed at invocation start. Never review the commit that fixes that review's findings.
- Never post a PR comment, reply, or review. Draft necessary replies for the user. Do not resolve review threads.
- For a draft PR, handle only failed CI and merge conflicts. Do not process review feedback, run `deep`, refresh the body, submit Stamphog, or mark the PR ready.
- Re-run an infrastructure failure at most once for a given workflow run and HEAD.
- Stop when progress requires product judgement, credentials, approval, or missing external context. Do not revisit the item until its GitHub event changes.
- Do not update the PR body for a fix that the current body already describes. Use `rs-update-pr` only when the PR's scope or claims changed.

## Event cursor

GitHub is the source of truth. Carry only a compact event cursor between invocations:

- `head_sha` — the final known remote HEAD.
- `checks` — sorted required-check names and states.
- `thread_heads` — each unresolved thread ID mapped to its latest comment ID.
- `handled_events` — event IDs already handled, mapped to their outcomes.
- `rerun_runs` — workflow run IDs already re-run at a given HEAD.
- `deep_reviewed_sha` — the SHA reviewed in `deep` mode, or `null`.
- `shepherd_pushed_sha` — the last SHA pushed by the shepherd, or `null`.
- `stamphog_sha` — the SHA submitted to Stamphog, or `null`.

Use `head_sha`, `checks`, `thread_heads`, mergeability, and draft state as the actionable fingerprint. Do not use the PR's `updatedAt`: label changes, body edits, and unrelated comments change it without creating shepherd work.

Give each external event a stable ID: `thread:<thread-id>:<latest-comment-id>`, `check:<run-id>:<attempt>`, or `conflict:<head-sha>`. An event is new when its ID is absent from `handled_events`. Replace obsolete event IDs when a thread advances, a check starts another attempt, a conflict changes SHA, or a thread resolves. This keeps the cursor bounded.

Ignore review threads whose latest comment is by the current GitHub user. Add their event IDs to `handled_events` without classification. A later reviewer reply has a new comment ID and becomes actionable.

## Workflow

### 1. Take one snapshot

Resolve the supplied PR, or use the current branch's PR. Fetch the following in at most three GitHub reads, combining fields where practical:

- PR number, URL, state, draft state, base, HEAD, mergeability, title, body, review decision, and latest reviews.
- Required check names, states, links, and workflow run IDs.
- Current GitHub login and unresolved review threads with thread ID, latest comment ID, author, body, path, line, and outdated state.

Stop if the PR is merged or closed. Stop if no PR exists. Do not check out the branch yet.

Compare the snapshot with the carried cursor. Actionable work is one or more of:

- A merge conflict with a new event ID.
- A failed required check with a new event ID.
- A review thread with a new event ID.
- A requested `deep` review that has not run for the invocation-start HEAD and whose HEAD differs from `shepherd_pushed_sha`.
- A Stamphog submission that is due under step 4.

If none applies, print one status line and the updated cursor, then stop. Pending checks are a wait condition, not work to poll within the invocation.

### 2. Classify all current work

Read only the evidence needed for actionable items.

For each new failed-check event, read its failed log once. Classify it as a reproducible code failure, an infrastructure failure, or a human dependency. Reproduce code failures locally when cheap. Re-run an infrastructure failure only if `rerun_runs` does not contain its run ID at the current HEAD. A rerun creates another check attempt and therefore another event ID. Defer human dependencies.

For each new review thread, read the surrounding function, callers, and relevant type definitions. Then choose one outcome:

- `fix` — the requested change is unambiguous and correct.
- `different-fix` — the concern is correct, but another implementation better preserves the code's invariants.
- `draft-reply` — no code change is appropriate.
- `defer` — two materially different choices remain after reading the available context.

Apply the adversarial verification rules from `rs-adversarial-review` before accepting a reviewer's claim. Do not load the interactive teaching workflow from `rs-address-pr-review`. The shepherd needs classification, not a walkthrough. Draft reply text for `different-fix`, `draft-reply`, and any deferred item that needs a reviewer response, but never post it.

Record `draft-reply` and `defer` events in `handled_events` immediately. After a rerun starts, record its event and add its run ID and HEAD to `rerun_runs`. Record events that require code or history changes only after the corrective push succeeds. A failed push must leave those events actionable for the next invocation.

If `deep` was requested, run `rs-review-pr <pr> as:self second-opinion` against the invocation-start HEAD. Apply only verified blockers. Report suggestions without changing code for them. Set `deep_reviewed_sha` to the reviewed SHA even when blockers produce a new commit.

### 3. Make one correction batch

If the batch changes files or history, check out the PR head and stop if the working tree contains unrelated changes. Never stash or discard the user's work.

For a plain PR, fetch and merge its base branch without pushing. For a GitHub Stack, use `rs-restack` once. Resolve conflicts with `rs-resolve-conflicts`. If conflict resolution needs judgement, abort it cleanly, record the conflict event as deferred, and stop changing history.

Apply all unambiguous CI, review, and deep-review fixes. Run the narrow tests, formatter, and linter that cover the changed areas. Create one new fix commit when file edits exist. Never amend. Push the target branch once after the full batch passes local verification. Set `shepherd_pushed_sha` to the pushed SHA.

If the PR belongs to a GitHub Stack and `rs-restack` has not run in this invocation, run it once after the target push. A required restack belongs to the same corrective push batch and can update dependent branches. Do not perform another target-branch correction in this invocation.

If the push fails, stop and report the error. Do not retry the push, update the PR body, or claim that a review fix is live.

Do not wait for new CI after a push. The next invocation observes it. If the pushed changes alter the PR's scope or claims, use `rs-update-pr` once against the complete PR diff. Otherwise leave the body alone.

### 4. Handle Stamphog only when idle

This step applies only to `PostHog/posthog`, and never to drafts.

Submit the current HEAD to Stamphog only when this invocation made no push, required CI is green, no new review thread remains unprocessed, no human decision is pending, and `stamphog_sha` differs from HEAD. Confirm that the remote HEAD still matches the snapshot, apply the label, set `stamphog_sha`, and stop. Do not poll for the verdict. A later invocation reads the resulting review or threads.

Treat the approval verdict as status. Actionable feedback comes through review threads and returns to step 2.

### 5. Report and stop

Emit commentary only for meaningful transitions: the actionable snapshot, the correction batch, and the final result. Do not narrate every command.

Print one compact status line:

```text
[shepherd] done — sha=<short> ci=<green|pending|failed|deferred> conflict=<none|resolved|deferred> threads=<fixed=N drafted=N deferred=N> deep=<not-requested|reviewed|current> push=<sha|none> stamphog=<submitted|current|waiting|n/a>
```

Print only reply drafts and deferred items created or changed in this invocation. Put each reply draft in a fenced code block. Do not repeat unchanged drafts on every loop pass.

Then print the cursor in one machine-readable line:

```text
[shepherd] cursor — {"head_sha":"...","checks":{...},"thread_heads":{...},"handled_events":{...},"rerun_runs":{...},"deep_reviewed_sha":null,"shepherd_pushed_sha":null,"stamphog_sha":null}
```

## Stop conditions

- `ready` — required CI is green, the branch is mergeable, and no new review feedback remains.
- `waiting` — CI, Stamphog, or a reviewer must produce a new event.
- `needs-user` — a deferred decision or external dependency requires the user. Repeated invocations with the same event cursor must exit immediately.
- `finished` — the PR is merged or closed. Tell the outer loop to stop.

Suggestions from the optional deep review do not prevent `ready`. A pushed correction always ends the invocation, even when more CI or review work may arrive later.

## Graceful degradation

- If a required helper skill is unavailable, perform safe, obvious work inline. Skip optional deep review if its skill is unavailable.
- If a GitHub read fails, retry it once. If it fails again, stop this invocation.
- If the working tree is dirty with unrelated changes, stop before checkout or mutation.
