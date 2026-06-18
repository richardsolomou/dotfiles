---
name: rs-autopilot
description: "Build a feature end to end: implement it autonomously, converge it through repeated fresh-context adversarial self-reviews, then gate a ship. Use when the user hands over a feature to build start to finish with minimal supervision."
argument-hint: "<feature description>"
disable-model-invocation: true
---

# Autopilot

Take a feature description, build it, harden it through rounds of fresh-context adversarial review until the reviewers stop finding anything real, then hand back a ship-ready working tree and gate the ship on the user.

The build and the review-and-resolve loop run as a background **Workflow** (`scripts/autopilot.js`). The point of the workflow is that each reviewer is a separate subagent with its own context — it never sees how or why the code was written, so its read can't be biased by the author's reasoning. `/loop` can't do this; it reuses one context. The ship and the watch-for-comments phase stay in the main conversation, under your eye.

Phases:

1. **Build** — one agent implements the feature + tests in the working tree (uncommitted).
2. **Review → Resolve, loop until dry** — `rs-reviewer` agents (fresh context, parallel, read-only) find issues; one agent resolves or rejects them. Repeats until a round finds nothing new, or the round cap.
3. **Ship** (gated) — you review the diff, then `rs-ship` makes one commit + PR.
4. **Watch & address** (separate, recurring) — poll the PR, address comments with `rs-address-pr-review`.

## Step 1: Get the feature description

Use the argument as the feature spec. If it's empty or a one-liner with no real detail, ask the user for: what to build, any constraints, and how to tell it's done. A vague spec produces a vague build — the cheapest place to fix that is before Step 3.

## Step 2: Pre-flight

```sh
git status --porcelain        # must be clean; if not, ask whether to stash or abort
git remote show origin | sed -n 's/.*HEAD branch: //p'   # the base branch
```

If the working tree isn't clean, stop and ask — the workflow modifies the working tree in place, so it must start clean.

Create the feature branch off the base, named per the user's Git convention (`<type>/<slug>`, or `<type>/<issue#>-<slug>` when an issue number is known):

```sh
git checkout -b <type>/<slug>
```

The branch stays checked out for the whole run; the background agents operate on it.

## Step 3: Run the build + review-converge workflow

Invoke the `Workflow` tool with the bundled script. Pass the absolute path to this skill's `scripts/autopilot.js` (resolve `~` to the home directory yourself):

```js
Workflow({
  scriptPath: "<HOME>/.claude/skills/rs-autopilot/scripts/autopilot.js",
  args: { feature: "<the full feature spec>", base: "<base branch>" }
})
```

Optional `args`: `maxRounds` (default 3), `reviewers` (default 3, capped at the number of lenses).

It runs in the background. When it returns you get: the build summary, per-round findings (applied vs rejected with reasons), and convergence status. Tell the user to leave the repo alone while it runs — the agents are editing this working tree.

**Convergence note to surface:** a finding the resolver *rejected* is suppressed in later rounds (so the loop terminates instead of re-litigating it). That's correct for nitpicks but means a wrongly-rejected real issue won't resurface — so when you report back, call out the `rejected` list with its reasons, not just what was applied. The user's call is whether any rejection was wrong.

## Step 4: Report and gate the ship

Show the user, tightly:

- What was built (the build summary) and `git diff <base> --stat`.
- Rounds run, total applied, total rejected (with the rejection reasons).
- Whether it converged or hit the round cap. Hitting the cap means it was *still* finding issues — flag that the change may need another pass or a closer human read.

Then **stop and ask** before shipping. Do not open a PR unprompted — it's outward-facing. Offer: ship now, do another review round, or hand back for manual edits.

On confirmation, invoke `rs-ship`. The changes are uncommitted in the working tree, which is exactly what `rs-ship` expects: it makes one conventional-commit, pushes, and opens the PR from the repo template.

## Step 5: Watch & address (separate, on request)

This is the recurring half — it does not belong in the workflow. After the PR is open, when the user asks (or on a schedule/poll they set up):

1. Check for new review comments on the PR.
2. Run `rs-address-pr-review` for the PR.
3. Apply code fixes; **draft** any reply comments for the user to approve — never post PR replies without explicit approval (per the user's CLAUDE.md).
4. Push fixes. Repeat as new comments arrive.

## What this is not

- Not a `/loop`. The review independence comes from separate subagent contexts, which `/loop` doesn't give.
- Not a replacement for reading the diff. It converges the change; you still gate the ship.
- Not fully hands-off through to merge: PR creation and reviewer replies are outward-facing and stay gated.

## Dependencies

- The `rs-reviewer` agent (`ai/agents/rs-reviewer.md`) must be installed (`ai/install.sh`) — the workflow spawns reviewers with `agentType: 'rs-reviewer'`. On the first run, confirm the agent resolves; if it doesn't, run the installer and retry.
- Reviewers read `rs-adversarial-review` and `rs-self-review` from `~/.claude/skills/` for their discipline. Keep those installed.
