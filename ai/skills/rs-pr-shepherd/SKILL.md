---
name: rs-pr-shepherd
description: "Shepherd an open PR through the post-open toil: fix failing CI, keep the branch current with its base, turn every new review comment into a fix or a drafted reply, re-run a swarm self-review on substantive pushes, and keep the PR body honest. One invocation is one iteration — run under /loop for hands-off cadence. Use when the user says 'shepherd this PR', 'babysit this PR', or wants CI and review comments handled automatically."
argument-hint: "[pr-url|pr-number]"
disable-model-invocation: true
---

# PR Shepherd

Drive an open PR to merge-readiness by orchestrating the existing skills; this skill owns the decisions, the sub-skills own the mechanics:

- **CI** — inspect failing checks, fix real failures, re-run flaky ones (handled inline; there is no sub-skill for this).
- **`rs-rebase` / `rs-resolve-conflicts` / `rs-restack`** — branch currency when the base has moved and it matters.
- **`rs-address-pr-review`** — every review comment becomes a prompt: apply clear fixes, draft replies, defer judgement calls.
- **`rs-review-swarm`** (self mode) — re-review your own substantive pushes so quality converges across iterations.
- **`rs-update-pr`** — refresh the title/body when the pushed commits changed what the PR claims to do.
- **stamphog** (PostHog/posthog only) — keep the PR Approval Agent's label on the current SHA and report its verdict.

**One invocation = one iteration.** The skill never sleeps or self-loops — it does one pass and hands back. For hands-off cadence run it under `/loop` (e.g. `/loop 10m /rs-pr-shepherd <pr>`); the outer loop provides the rounds, and fixes pushed in one iteration are re-reviewed in the next.

## Hard rules

These override anything a sub-skill's own flow would do:

- **Never post a PR comment, reply, or review.** Full stop, not even with approval — code fixes are pushed as commits (that's fine), but anything conversational is drafted and accumulated in `drafted_replies` for the user to copy and post themselves. This is a standing CLAUDE.md rule — the shepherd runs unattended, so there is no "ask first" escape hatch: draft, carry, surface, never post.
- **New commit per round, never amend.** Reviewers must see what changed between rounds.
- **Never mark a draft PR ready.** Shepherd it (CI, currency, swarm) but skip the review-comment and body-refresh steps and note the draft state in the summary — readiness is the user's call.
- **PR body refreshes are automatic** — `rs-update-pr` is not a review comment; run it without asking when warranted.

## Resolving sub-skills

Resolve each sub-skill local-first, then from the skills store — the same pattern `rs-review-swarm` uses for `security-audit`. Every `rs-*` skill is mirrored in the store (the dotfiles copy is the source of truth), so the shepherd works on machines without the dotfiles clone:

1. **Local:** if `~/.claude/skills/<name>/SKILL.md` exists, use it — read the file when the sub-skill is loaded as a brief or followed inline, or `Skill("<name>")` for the model-invocable ones (`rs-review-swarm`, `rs-address-pr-review`, `rs-resolve-conflicts`).
2. **Store fallback:** otherwise fetch the body with `mcp__posthog__exec command='call llma-skill-get {"skill_name":"<name>"}'` and use it the same way. If the store call fails too, apply Graceful degradation for that step.

## Narration

Emit a one-line, present-tense narration before every step so the user can follow without reading tool output. Format: `[shepherd] <step> — <what and why>`. A silent 30-second gap is the failure mode.

```text
[shepherd] step 1 — resolving PR from current branch
[shepherd] step 1 — no change since a1b2c3d, skipping iteration
[shepherd] step 2 — 2 checks failing, reading logs for lint
[shepherd] step 2 — base moved and PR conflicts, running rs-rebase
[shepherd] step 3 — 3 new review comments, dispatching rs-address-pr-review
[shepherd] step 4 — substantive push since last swarm, running rs-review-swarm self
[shepherd] step 5 — net state changed, running rs-update-pr
[shepherd] step 6 — applying stamphog at def4567; verdict: changes requested
[shepherd] iter done — handing back; /loop drives the next pass
```

## State between invocations

GitHub is the source of truth; the loop is restartable from nothing. State is carried only via the printed state line (re-supplied through `$ARGUMENTS` or visible in the conversation when iterations run back-to-back):

- `swarm_marker_sha` — HEAD the last time the swarm ran. `null` initially.
- `deferred_threads` — review-thread IDs already surfaced as needing the user's judgement; skipped on later iterations to avoid nagging.
- `drafted_replies` — count of reply drafts awaiting approval (the drafts themselves live in the conversation; re-print the pending ones each iteration until the user acts).
- `flaky_rerun_sha` — HEAD at which a failed-check re-run was already tried, so a genuinely broken check isn't re-run forever.
- `stamphog_applied_for_sha` — HEAD at which the `stamphog` label was last applied (PostHog/posthog only). `null` initially.
- `last_updated_at` — the PR's `updatedAt` observed at the end of the previous iteration.

## Workflow — one iteration

### Step 1: Resolve the PR and fast-path check

If `$ARGUMENTS` has a PR number or URL, use it; otherwise the current branch's PR. Resolve everything in one call:

```bash
gh pr view <ref> --json number,url,baseRefName,headRefOid,state,isDraft,mergeable,updatedAt \
  --jq '{number, url, base: .baseRefName, head_sha: .headRefOid, state, isDraft, mergeable, updatedAt}'
```

Parse owner/repo from `url`. If state is `MERGED` or `CLOSED`, terminate with a final summary. If no PR exists for the current branch, say so and stop — opening a PR is `rs-ship`'s job, on the user's initiative, not the shepherd's.

**Fast path:** on a re-invocation, if `head_sha` and `updatedAt` both match the carried state and CI is not failing, nothing happened — print the state line and exit without dispatching anything. (`updatedAt` moves on any commit, comment, review, or label event; CI-only transitions may not move it, which is why the CI check is part of the gate.)

Ensure the working tree is on the PR head before anything edits files: `gh pr checkout <n>` unless already there, and abort the iteration if `git status --porcelain` shows unrelated local changes — never push someone's half-finished work.

### Step 2: CI and branch currency

```bash
gh pr checks <n> --json name,state,link,workflow
```

For each failing check, in order of likely payoff:

1. **Read the failure** — `gh run view <run-id> --log-failed` (find the run id via the check's `link`). Classify: real failure (test, lint, types, build) vs infrastructure flake (timeout, runner death, 5xx from a registry).
2. **Real failure** — reproduce locally when cheap (the repo's own test/lint command for the failing target), fix it, and commit (`fix: <what>`, new commit). Batch all CI fixes into one commit per iteration; push once at the end of this step.
3. **Flake** — `gh run rerun <run-id> --failed`, once per HEAD: if `flaky_rerun_sha` already equals the current HEAD, don't re-run again — report the check as persistently failing and defer to the user.
4. **Needs a human** (a secret is missing, a required approval, an infra change) — defer: one line in the summary, no thrash.

**Branch currency** — act only when it matters; don't churn merge commits every iteration:

- `mergeable == CONFLICTING` → resolve `rs-rebase` and follow it (it merges the parent branch in — that's the convention here, not an actual rebase — and uses `rs-resolve-conflicts` for conflicts). If conflict resolution hits a genuine judgement call (both sides changed behaviour and the right merge isn't derivable), abort the merge cleanly, defer with the file list, and skip to Step 3.
- CI failing *because* the branch is stale (a required "branch up to date" check, or failures that don't reproduce on the merged tree) → same.
- Otherwise leave the branch alone.
- If the branch has dependent branches stacked on it (Graphite), follow `rs-restack` after any push so the stack stays coherent.

### Step 3: Review comments — every comment becomes a prompt

Skip if `isDraft`. Fetch the review threads and keep only actionable ones — unresolved, not authored by you after the reviewer's last word, and not in `deferred_threads`:

```bash
gh api graphql -f query='query($owner:String!,$repo:String!,$n:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:20){nodes{author{login} body createdAt}}}}}}}' -f owner=<owner> -f repo=<repo> -F n=<pr>
```

If any remain, dispatch **`rs-address-pr-review`** as a `model: "sonnet"` Agent subagent by load-then-spawn: resolve its body, pass it plus this override brief and the thread list:

> Sub-step, not standalone. Skip the interactive walkthrough and the teaching layer — classify and act. For each thread: if the fix is unambiguous (the reviewer named the change, or there is exactly one reasonable reading), apply it to the working tree; if it needs the author's judgement (design pushback, scope questions, trade-offs), mark it deferred with a one-line reason; if it deserves a reply rather than a code change, draft the reply text but NEVER post it. Never call AskUserQuestion. Return: files changed, per-thread outcome (fixed / deferred+reason / reply-drafted+text), nothing else.

Commit the applied fixes as one commit (`fix: address review comments`), push. Add deferred threads to `deferred_threads`; add drafted replies to `drafted_replies` and print them in the summary, each in a fenced code block ready to paste.

### Step 4: Swarm self-review on substantive pushes

Run when `swarm_marker_sha` is `null`, or the diff `swarm_marker_sha..HEAD` touches at least one non-doc file (something other than `*.md`, `*.txt`, or pure whitespace). Otherwise log `swarm: skip (no substantive changes since <sha>)`.

Invoke `Skill("rs-review-swarm", args: "<pr> as:self")` **in the main loop** — it spawns its own reviewer agents, and nesting agent spawns inside a dispatched subagent is the thing to avoid. Then, instead of its interactive offer-to-apply:

- **Blockers** — apply the fixes yourself, commit (`fix: address self-review findings`), push. HEAD moves; the next iteration's swarm gate sees the fixes.
- **Suggestions** — list them in the summary; don't act unless trivial and unambiguous.

Set `swarm_marker_sha` to the HEAD the swarm reviewed (its Step 1 records it). One swarm pass per iteration — convergence comes from the outer `/loop`, not an inner round-loop.

### Step 5: PR body freshness

If this iteration pushed commits, compare the PR's title/body against `git diff <base>...HEAD` per the standing CLAUDE.md rule; when the net state no longer matches what the PR claims, resolve `rs-update-pr` and follow it against the entire PR diff. Skip if `isDraft` or nothing was pushed.

### Step 6: Stamphog (PostHog/posthog only)

`stamphog` is PostHog/posthog's PR Approval Agent; re-applying its label on each new SHA is what triggers a fresh review, so the shepherd just keeps the label current and reports the verdict. Skip this step entirely when the repo isn't `PostHog/posthog`, and when `isDraft` — stamphog silently skips drafts, and the shepherd never marks a PR ready.

Apply when `stamphog_applied_for_sha` differs from the current HEAD. Guard against an out-of-band push first:

```bash
gh pr view <n> --json headRefOid -q .headRefOid
```

If HEAD moved since your last push, skip and let the next iteration re-baseline. Otherwise:

```bash
gh pr edit <n> --add-label stamphog
```

Set `stamphog_applied_for_sha` to the labeled SHA. Then read the verdict (informational — it never gates the loop, and the actionable review *threads* were already handled in Step 3):

```bash
gh pr view <n> --json reviewDecision,latestReviews \
  --jq '{reviewDecision, reviews: [.latestReviews[] | {author: .author.login, state, body: .body[:400]}]}'
```

Report approved / changes requested / dismissed with a one-line reason from the review body when present.

### Step 7: Summary and hand-back

Print one status line, then the pending human-input items, then the state line:

```text
[shepherd] iter done — sha=<short> ci=<pass=N fail=N pending=N> currency=<clean|merged-base|conflict-deferred> comments=<fixed=N deferred=N replies-drafted=N> swarm=<ran: B blockers fixed, S suggestions|skip> body=<refreshed|current> stamphog=<applied|current|skipped|n/a> verdict=<approved|changes|pending|n/a>
```

- Drafted replies awaiting approval: each as `file:line` + the draft in a fenced block (re-print unactioned ones from previous iterations too).
- Deferred threads and deferred CI/conflict items: `file:line` or check name + one-line reason.

```text
[shepherd] state — swarm_marker_sha=<sha|null> deferred_threads=[...] drafted_replies=<n> flaky_rerun_sha=<sha|null> stamphog_applied_for_sha=<sha|null> last_updated_at=<iso8601>
```

Set `last_updated_at` from a final `gh pr view --json updatedAt` after all pushes, so the next fast-path compares against a post-action baseline. Hand back — `/loop` or the user drives the next iteration.

## Terminal conditions

Stop cleanly (tell the outer loop to stop too) when:

- the PR is `MERGED` or `CLOSED`;
- everything actionable is done and only deferred items remain — CI green or deferred, no new comments, swarm converged (last run found nothing), body current. The fast path short-circuits this on re-invocation, but say it explicitly once so the user knows the shepherd is idle by success, not by being stuck;
- the user interrupts.

CI failures, conflicts needing judgement, and deferred threads are **not** terminal — they're reported and the loop keeps watching for the user's input or new events.

## Model economy

Launch the loop session on a cheaper model (`/model sonnet` before `/loop … /rs-pr-shepherd`): the orchestration and CI mechanics don't need deep reasoning. The parts that do are pinned regardless of session model — `rs-review-swarm` pins its reviewers to `opus`, and the `rs-address-pr-review` runner is dispatched at `sonnet` explicitly.

## Graceful degradation

- A sub-skill resolves neither locally nor from the store → warn, skip that step, continue the iteration (a missing swarm never blocks a CI fix).
- `Agent` can't be spawned → run the `rs-address-pr-review` body inline in the main loop; you lose the model pin, not the function.
- `gh` rate-limited or a call fails → retry once, then defer that step to the next iteration rather than failing the whole pass.
- Working tree dirty with unrelated changes → abort the iteration with a clear message; never stash or push around the user's work.
