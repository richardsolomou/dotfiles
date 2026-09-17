---
name: sprint-planning
description: "Write the bi-weekly sprint planning update for the Context & MCP team, ready to post as a GitHub comment on the sprint issue. Use when the user asks to write/prep the sprint planning update or retro, post the sprint comment, archive the board's old Done items (`archive`), or show what the team is working on (`goals`)."
argument-hint: "[archive|goals]"
---

# Sprint Planning

Generate a bi-weekly sprint planning update for the Context & MCP team (configurable for other teams via `scripts/config.sh`), ready to post as a GitHub comment on the sprint planning issue.

## Team Configuration

All team-specific values live in this skill's `scripts/config.sh`. The helper scripts source it automatically; the inline `gh` commands in this skill source it too, so always run them with the leading `source` line shown. Scripts are invoked through `~/.agents/skills/`, which every harness's installer populates, so the commands work from any working directory.

The defaults target the **Context & MCP** team:

| Variable | Default | Meaning |
| --- | --- | --- |
| `SPRINT_TEAM_SLUG` | `team-context-mcp` | GitHub team slug under the org |
| `SPRINT_TEAM_NAME` | `Context & MCP` | Display name used in prose |
| `SPRINT_SLACK_CHANNEL` | `team-context-and-mcp` | Slack channel name used for team activity |
| `SPRINT_PROJECT_NUMBER` | _(unset)_ | Project board number — empty until the team has a board |
| `SPRINT_GOALS_URL` | `https://posthog.com/teams/context-and-mcp#objectives` | Goals page link |
| `SPRINT_COMMENT_HEADER` | `# Team Context & MCP` | Markdown heading identifying the team's comment |
| `SPRINT_ORG` | `PostHog` | GitHub org |
| `SPRINT_REPO` | `PostHog/posthog` | Repo holding sprint issues |
| `SPRINT_FALLBACK_MEMBERS` | `richardsolomou adboio JakeRuth` | Space-separated handles used only if the members API fails |

Override any value with an environment variable, or edit the defaults in `config.sh`.

In the output templates below, `{SPRINT_…}` placeholders refer to these config values; read them from `config.sh` (or `source` it) and substitute the resolved values before presenting output.

> **No project board configured:** `SPRINT_PROJECT_NUMBER` is empty by default. The board steps (Step 5, Step 13, and the board half of the `goals` workflow) detect this and skip cleanly, so the plan is built from in-flight work and the user's input instead. Set `SPRINT_PROJECT_NUMBER` in `config.sh` when the team has a board.
>
> **Prerequisite (once a board exists):** the board scripts call `gh project`, which needs the `read:project` scope. If they fail with a missing-scope error, run `gh auth refresh -s read:project` once.

## Quarter Objectives

Pull the quarter goals and their statuses from the previous sprint's comment (Step 3). Carry them forward, applying any status changes the user confirms in Step 9. If no previous comment exists (the team's first sprint), ask the user for the team's current quarter objectives.

## Arguments

- `/sprint-planning archive` — Skip the full sprint planning workflow and jump directly to archiving old Done items from the project board. When this argument is present:
  1. Run Step 1 (Detect Sprint Context) to get `sprint_start`
  2. Jump directly to Step 13 (Archive Previous Sprint's Done Items)
  3. Exit after archiving

- `/sprint-planning goals` — Show what the team is currently working on by merging the current sprint plan with project board data, grouped by assignee. Follow `~/.agents/skills/sprint-planning/references/goals.md` and exit after displaying.

## Your Task

Follow these steps in order. Gather as much data automatically as possible before asking the user anything.

### Step 1: Detect Sprint Context

Run the helper script to find the current and previous sprint issues:

```bash
~/.agents/skills/sprint-planning/scripts/detect-sprint.sh
```

This returns tab-separated fields:
`current_number\tcurrent_title\tsprint_start\tsprint_end\tprev_number\tprev_title\tprev_start\tprev_end`

Store all these values. You need:

- `current_number` and `current_title` for the issue to post on
- `sprint_start` and `sprint_end` for the PR date range
- `prev_number` for fetching the previous comment
- `prev_start` and `prev_end` for the previous sprint's PR date range

Verify that today's date falls within `sprint_start` through `sprint_end`. The detector can fall back to the nearest past or future issue when no issue contains today; if that happens, show the detected issue and dates and ask the user to confirm before continuing. If detection returns `NOT_FOUND`, stop and ask which sprint issue to use.

### Step 2: Fetch Team Members

```bash
source ~/.agents/skills/sprint-planning/scripts/config.sh
gh api "orgs/${SPRINT_ORG}/teams/${SPRINT_TEAM_SLUG}/members" --jq '.[].login'
```

If this fails (permissions, etc.), fall back to `SPRINT_FALLBACK_MEMBERS`, or ask the user for the team's members if it is empty.

### Step 3: Fetch Previous Sprint Comment

```bash
~/.agents/skills/sprint-planning/scripts/fetch-previous-comment.sh <prev_number>
```

If the result is "NOT_FOUND" (e.g., the team's first sprint), skip the plan-first retro approach entirely. You'll build the retro purely from merged PRs and project board items instead, confirmed with the user.

If the result is not "NOT_FOUND", parse the comment to extract:

- The **Plan** section from the previous sprint (this becomes the retro skeleton)
- Each team member's planned items
- The quarter goal statuses

### Step 4: Fetch Merged PRs

For each team member, fetch their merged PRs during the **previous** sprint period. Issue all fetch calls in parallel (multiple Bash tool calls in a single response) to minimize wall-clock time:

```bash
source ~/.agents/skills/sprint-planning/scripts/config.sh
~/.agents/skills/activity-harvest/scripts/team-merged-prs.sh <username> "$SPRINT_ORG" <prev_start> <prev_end> 200 body
```

Store all PR data per team member. The script returns each PR's `body` (the
description) alongside its title — **read the descriptions, not just the
titles.** Titles are conventional-commit one-liners that routinely undersell or
miscolor the work; the body is where the actual outcome, scope, and caveats
live. Synthesize the retro from the bodies.

Then fetch each member's currently-open PRs (including drafts) to capture
in-flight work the merged query misses — house retros list started-but-unfinished
items (🟡/🔴), not just shipped work:

```bash
~/.agents/skills/sprint-planning/scripts/fetch-team-open-prs.sh <username>
```

Bucket the open PRs by activity, not creation date alone:

- An open PR is an in-progress **retro** item (🟡) only when its commits, comments, reviews, or `updatedAt` show activity during `[prev_start, prev_end)`. An older open PR with no in-window activity is stale evidence: omit it from the retro unless another source shows the work continued.
- An open PR with activity on or after `prev_end` is an in-flight **plan** seed.

`isDraft` marks early/WIP work; a non-draft open PR is review-ready. Read the
bodies here too.

### Step 4b: Harvest Slack

PRs miss a lot of real sprint work — incidents handled, decisions driven, cross-team RFC input, demos, and each member's own stated focus for next sprint. Search Slack for the previous sprint window with `mcp__slack__conversations_search_messages`, three passes:

1. **Your own messages** — `filter_users_from` with your user ID, per the `activity-harvest` Slack rules (day-granular dates; post-filter to the window).
2. **Each teammate's messages in the team channel** — resolve `SPRINT_SLACK_CHANNEL` to its channel ID once, then use `filter_users_from: <their user ID>` + `filter_in_channel: <team channel ID>`. This is where their launch updates, incident triage, and "my focus next week is…" posts live; those focus posts are plan gold.
3. **Your DMs with each teammate** — `filter_in_im_or_mpim` takes the `@username` form; passing the `D…` channel ID fails with "user not found".

Results cap at 100 per page — follow the `Cursor` column until the window is covered (the earliest sprint days are on the later pages). Treat incident threads as retro candidates and use 🟢 only when a message explicitly records the completed outcome; decision threads can support 🟡 items, demo/talk appearances can support side quests, and stated next focus can seed the plan. **Private-DM process conversations and interpersonal feedback never go in the company-wide comment**, however relevant they feel.

Record any unresolved user or channel IDs, failed searches, truncated pagination, or uncovered dates. A Slack statement of intent is evidence that work was planned or investigated, not that it completed, unless the message explicitly records the completed outcome.

### Step 5: Fetch Project Board Items

If `SPRINT_PROJECT_NUMBER` is empty (no board yet), skip this step — there are no board items to categorize. The plan in Step 9 is then drafted from the previous sprint's in-flight work and the user's input.

```bash
source ~/.agents/skills/sprint-planning/scripts/config.sh
[ -n "$SPRINT_PROJECT_NUMBER" ] && gh project item-list "$SPRINT_PROJECT_NUMBER" --owner "$SPRINT_ORG" --format json --limit 200
```

Categorize items by status column:

- **Done** items inform the retro only when timestamped evidence places completion within `[prev_start, prev_end)`. For linked issues or PRs, fetch the target and inspect `closed_at` or `merged_at`. If the board item has no authoritative completion timestamp, treat it as corroboration only rather than assigning it to this sprint.
- **In Progress** and **Todo** items inform the plan
- **In Review** and **Approved** items are treated as **In Progress** for planning purposes. These are PR-based items that may lack board assignees. For each, fetch the PR author with `gh pr view <number> --repo <owner/repo> --json author --jq .author.login` and use that as the assignee. Only include items whose author is a current team member.

Each item's `content.url` field contains the issue or PR URL. Preserve these for linking in the output.

### Step 6: First Prompt - Context

Now that you have all the automated data, ask the user:

> I'm writing the sprint planning update for **{current_title}** (#{current_number}).
>
> Team members: {list from Step 2}
>
> Two questions before I build the draft:
>
> 1. Who's the support hero this sprint? (or N/A for a small team with no rotation)
> 2. Is anyone off during the sprint?

Wait for the user's response before continuing.

### Step 7: Build Retro

There are two paths depending on whether a previous sprint comment was found.

Path A - Previous plan exists (plan-first retro):

Start from what was **planned**, not what was shipped.

Extract previous plan items: From the previous sprint comment (Step 3), parse each person's planned items. These become the retro checklist.

Build candidate matches: For each planned item, search the merged PRs (Step 4) for a match by:

- Issue number or PR number overlap
- Keyword similarity in titles
- Explicit references

Keyword similarity only nominates a candidate. Mark an item done only when an exact issue/PR reference, the PR body, board history, or an explicit completion statement ties the shipped work to the planned outcome. Otherwise leave it unresolved for Step 8. Keep the PR's URL on hand for the rare case a reader would want to open it, but the bullet text is the outcome, not the PR title.

Identify side quests: Any merged PRs that don't map to a planned item are candidate "side quests" or unplanned work.

Path B - No previous plan (first sprint or NOT_FOUND):

Build the retro from merged PRs and project board "Done" items, grouping each person's work and presenting it for confirmation. Then add in-progress items from the open/draft PRs fetched in Step 4 only when they have activity in `[prev_start, prev_end)`, so the retro reflects started-but-unfinished work without reviving stale PRs. Prefix every item with a status emoji: `🟢` for shipped outcomes, `🟡` for each distinct in-progress workstream (collapse only PRs that are part of the same workstream).

**Synthesize, don't transcribe.** The retro audience is the wider company, not the team. Read each PR's description (Step 4 fetches it) and translate the raw PRs into plain-language outcomes:

- Describe **what was accomplished**, in terms a reader outside the team understands — grounded in the PR body, not the title alone, which is often verbose, too low-level, or undersells the actual change.
- **Collapse several related PRs into one bullet — but one distinct item per bullet.** "Built the spend path end to end — ledger, real-spend settlement, pre-call admission" beats nine PRs named `feat(quota): …`; two different efforts are two bullets, never a comma-joined list. Side quests get a `Side quests:` parent line with one emoji-prefixed sub-bullet per quest.
- **Every retro item carries a status emoji, both paths** — don't mix bare bullets with emoji'd ones; it reads half-finished.
- **Links are the exception, not the rule.** Most bullets carry no link. Attach a single representative PR link only to a flagship item a reader might plausibly open. Never trail a bullet with a list of links.
- **Describe what was built or shipped, not ownership.** Avoid "owns" / "now owns" framing — the team doesn't claim ownership of components. "Built the model catalog", not "Built and now owns the model catalog".
- **Keep each bullet to one punchy line.** Headline outcome plus at most one short clause of the most telling specifics — not an exhaustive comma-list of every sub-detail. "Built the prepaid wallet & ledger — O(1) balances, bounded overspend, admin top-up", not a clause naming all six PRs' worth of detail. The reader skims; trim hard.
- Optionally group a person's bullets under a short theme when it aids reading; a small team's handful of bullets often needs no grouping at all.

### Step 8: Second Prompt - Retro Review

Present the retro per person, each item as a plain-language outcome (not a PR title):

> Here's what I've reconstructed from last sprint's plan vs. what shipped:
>
> **@member1**
>
> - ✅ Planned outcome 1
> - ❓ Planned item 3 → no matching PR found
>
> **Unplanned work I found (side quests?):**
>
> - Plain-language outcome from an unmatched PR
>
> Questions:
>
> 1. For items marked ❓, what's the status? (done, in progress, blocked, cancelled)
> 2. Which unplanned items should I include as side quests?
> 3. Anything else to add or correct?

For Path B (no previous plan), the same prompt minus the reconciliation: lead with "Here's what I found shipped during the sprint", list the synthesized outcomes per person, and ask instead whether the accomplishments read accurately, what's missing that didn't result in PRs, and what to exclude.

Wait for the user's response.

### Step 9: Third Prompt - Plan and Objectives

If there is no board (Step 5 skipped), draft the plan **only from in-progress work**, then leave the rest for the user to fill out live. Specifically, seed each person's plan with:

1. Every `🟡` in-progress item from their retro (Step 7), reworded to imperative/future tense ("Scoped X" → "Finish X").
2. Their in-flight open/draft PRs from Step 4 (those opened after `prev_end`) — real continuing work.

**Do not invent plan items from the quarter goals.** Carrying a goal forward as a plan bullet with no in-progress work behind it is a guess; the user knows their own plan. After the in-progress items, add an italic placeholder bullet per person (e.g. `- _…(add the rest)_`) so they fill in the rest. Otherwise, present project board items as a draft plan.

**The issue tracker is the board.** With no project board, the team repo's open issues carry the real state — sweep them (bodies AND comments) before finalizing the plan, fanning out parallel subagents batched by theme for a large tracker. Gotcha: `gh issue view` can print nothing in this environment; use `gh api repos/<org>/<repo>/issues/<n>` plus `…/comments`. The sweep finds what PR-reading can't:

- **Decisions already recorded in comments** — don't re-plan a question that's been answered (e.g. a feature decided _against_, a mirror decided as drop); the plan item becomes the follow-through, not the decision.
- **Launch gates with no covering PR** — tracking issues for a cutover often list blockers nobody has picked up; these are the highest-value plan items.
- **Items already covered by open PRs** — an issue isn't a plan item if a teammate's open stack resolves it.
- **Close-candidates** — issues whose work merged; mention as housekeeping, not plan items.

**Propose quarter-goal status bumps from evidence** (a ⚪ sub-goal with real in-flight work behind it → 🟡) instead of only asking for changes.

**Suggestions, if the user asks for extra picks:** draw only from open issues the person owns or that sit next to work they already did — prioritize the remaining children of their epics so the epics can close. Phrase each as the work itself ("Reconcile the breaker with the health bands"), never as "close out the epic". Present them as a prunable list; fold the survivors into the end of that person's plan as ordinary bullets.

Then present the draft:

> Here's the plan I've drafted from the project board:
>
> **High priority:**
> @member1 - item1, item2
> @member2 - item3
>
> **Side quests:**
>
> - item4
>
> Questions:
>
> 1. Any adjustments to the plan?
> 2. Any changes to quarter goal statuses?

Wait for the user's response.

### Step 10: Generate the Update

**Build an evidence ledger before writing.** For every retro and plan bullet, record the supporting PR, issue, board transition, or explicit Slack completion statement, its timestamp, and which part of the claim it supports. A source can nominate a claim without proving it. If the evidence does not establish completion, scope, or timing, weaken the wording or mark the item unresolved.

**Fact-check the draft against the evidence ledger.** Synthesis from titles drifts. For a non-trivial sprint, spawn one verification agent per team member (in parallel) that reads the merged + open PR data from Step 4 and the other cited evidence, then returns:

- Per bullet: SUPPORTED (cite PR numbers), OVERSTATED (how to reword), WRONG, or MISCATEGORIZED (claimed 🟢 but still open/draft, or 🟡 but actually merged).
- Any substantial merged work MISSING from every bullet.

Apply the corrections before presenting. This pass routinely catches real omissions and overstatements; don't skip it.

**Fact-check the plan bullets too.** Every plan bullet that references a PR or issue gets re-checked against live state just before presenting — a PR merges, gets renamed, or a decision lands mid-session, and a stale bullet ("land X" when X merged, "strip Y down" when Y is already stripped, a claimed count like "a 13-PR stack" that's actually 12) undermines the whole draft. Verify counts by listing, never by assuming ranges are contiguous (#303–315 was 12 PRs; #313 didn't exist).

Then compose the final sprint update using all gathered and confirmed data.

**Write it in Richard's voice.** This comment gets posted under his name, so load `tone` with register **`slack-status`** (never `slack-casual` here) and generate in that register from the start — don't write neutral-assistant prose and rewrite. For this artifact the register means plain language, NOT chat diction: bullets stay sentence case with normal punctuation (it's a company-wide GitHub comment, not Slack), but every term gets the plain-words test — if a reader outside the team would stumble ("provenance-verified", "health-routed election", "drift detection"), say it plainly ("capture verifies the events are really ours", "routes to the healthiest provider", "alert when the ledger and billing disagree"). Domain nouns the team actually uses (attribution, breaker, failover, ledger) stay.

**IMPORTANT**: Output the update as raw markdown inside a code block so the user can copy/paste it directly into GitHub.

The format below mirrors the canonical issue template at [`.github/ISSUE_TEMPLATE/sprint_planning_retro.md`](https://github.com/PostHog/posthog/blob/master/.github/ISSUE_TEMPLATE/sprint_planning_retro.md) (the sprint issue body is generated from it) plus the house conventions visible in how teams actually post (see any open `Sprint - …` issue in `SPRINT_REPO` for live examples). Match it closely — the wider company reads these, so consistency matters. Notable conventions, easy to get wrong:

- **Status emoji prefix the line** — `- 🟡 Goal 1: …`, not a trailing emoji. Nest sub-items, each with its own emoji.
- **The legend is a single inline line at the bottom of the Retro `<details>`** — `🟢 =finished 🟡=in progress 🔴=won't finish ⚪=not started`. No separate legend block under Quarter goals.
- **No narrative paragraph** — the retro is bullets only, inside `<details>`.
- **Plan subsections are `### High priority`, `### Low priority / side quests`, and `### Are any other teams impacted by this plan? If so, tag them here`** — include all three, even if a section is just `-`.
- **Plan items are deliverables, not process.** Never write items like "review X's PRs", "coordinate with Y", or "keep an eye on Z" — reviewing and coordination are ambient work, not plan lines. Every bullet names something that ships or a decision that gets recorded.
- **Plan bullets are short.** Deliverable + issue/PR link, one line, at most one brief clause of context. No rationale chains, PR counts, launch-gate explanations, or em-dash essays — that detail lives in the linked issues.
- **One deliverable per plan bullet.** Don't pair items just because they're adjacent ("Antithesis trial; add Bedrock to the simulator" is two bullets). Combine only when it's genuinely one workstream — a batch plus its cutover, one alerting effort with two halves.
- **The Plan is team-scoped.** Out-of-team side quests (other products' PRs, personal itches) never appear in the Plan — the plan is what the team commits to for its own product. They may still appear in the Retro's side quests, which documents where time actually went.

Substitute the configured values: `SPRINT_COMMENT_HEADER` for the top heading, `SPRINT_GOALS_URL` for the goals link. Include a `[Project Board](https://github.com/orgs/{SPRINT_ORG}/projects/{SPRINT_PROJECT_NUMBER})` link under `## Plan` **only when `SPRINT_PROJECT_NUMBER` is set**; omit the line entirely when there's no board. The quarter goals come from Step 3 (or the user, for a first sprint), not the example below.

Retro shape depends on the path from Step 7:

- **Path A** (previous plan existed): grab last sprint's High priority and Low priority / side-quest items, tag each `@person`, and prefix each with a status emoji marking whether it completed — this matches the template's "grab the items from last time and add whether that item was completed" note.
- **Path B** (first sprint / NOT_FOUND): synthesized per-person outcome bullets, each prefixed `🟢`/`🟡` per Step 7.

Use this format (Path B retro shown; for Path A, replace the per-person outcomes with status-emoji'd plan items grouped by priority):

````markdown
```markdown
{SPRINT_COMMENT_HEADER}

**Support hero:** [@handle or "N/A"]
**Off during the sprint:** [names or "Nobody!"]

## Quarter goals

[Goals]({SPRINT_GOALS_URL})

- 🟡 Goal 1: First objective — short description
  - 🟡 Sub-item with its own status
  - ⚪ Another sub-item
- ⚪ Goal 2: Second objective — short description
  - … (carry goals, sub-items, and statuses forward from Step 3)

## Retro

<details>

@member1

- 🟢 Plain-language outcome describing what shipped, synthesized from one or more PRs
- 🟡 An in-progress workstream — link a flagship item only when a reader might open it ([PR](url))

@member2

- 🟢 Plain-language outcome

🟢 =finished 🟡=in progress 🔴=won't finish ⚪=not started

</details>

## Plan

[Project Board](https://github.com/orgs/{SPRINT_ORG}/projects/{SPRINT_PROJECT_NUMBER})

### High priority

@member1
- [Work item description](https://github.com/PostHog/posthog/issues/123)
- [Another work item](https://github.com/PostHog/posthog/pull/456)

@member2
- [Work item description](https://github.com/PostHog/posthog/issues/789)

### Low priority / side quests

- [Side quest item](https://github.com/PostHog/posthog/issues/101)
- Plain text item if no link available

### Are any other teams impacted by this plan? If so, tag them here

- @PostHog/team-x — why they're impacted, or "-" if none
```
````

### Step 11: Archive the Update Locally

Write the final markdown to `~/dev/notes/PostHog/sprint-planning/<sprint_start>.md` (e.g. `2026-06-29.md` — sortable, one file per sprint), then commit and push per `activity-harvest` § _Archive to notes_, commit prefix `sprint-planning:`. If the file already exists (re-run for the same sprint), overwrite it — the latest draft wins; this is the pre-meeting draft, a record of what was prepared, not the final posted comment.

### Step 12: Hand Off for Manual Posting

**Never offer to post the sprint comment, and never run `gh issue comment` for it — even if it seems helpful.** The user pastes it into #{current_number} themselves. End by presenting the final markdown (Step 10's code block) and noting the archive path from Step 11. Only post if the user spontaneously and explicitly asks in their own words.

### Step 13: Archive Previous Sprint's Done Items

After handing off the update, offer to clean up the project board by archiving Done items from previous sprints.

1. Run the helper script to find archivable items:

   ```bash
   ~/.agents/skills/sprint-planning/scripts/archive-done-items.sh <sprint_start>
   ```

2. If the result is an empty array, skip silently — no prompt needed.

3. Otherwise, present the list and ask for confirmation:

   > I found {N} items in the Done column that were completed before this sprint ({sprint_start}). Would you like me to archive them to keep the board clean?
   >
   > {list of items with titles and closed dates}

4. If the user confirms, archive each item:

   ```bash
   source ~/.agents/skills/sprint-planning/scripts/config.sh
   gh project item-archive "$SPRINT_PROJECT_NUMBER" --owner "$SPRINT_ORG" --id <item-id>
   ```

The output template in Step 10 is the authoritative format reference (synthesis and bullet rules live in Step 7). Never offer to post and never run `gh issue comment` unprompted — the user posts the comment themselves (Step 12).
