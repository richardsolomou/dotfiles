---
name: rs-sprint-planning
description: "Write a bi-weekly sprint planning update for the AI Gateway team, ready to post as a GitHub comment on the sprint issue. Automates sprint detection, merged-PR fetching, and plan-first retro construction from the previous sprint's comment. Use when the user asks to write/prep the sprint planning update or retro, post the sprint comment, archive the board's old Done items (`archive`), or show what the team is working on (`goals`)."
argument-hint: "[archive|goals]"
---

# Sprint Planning

Generate a bi-weekly sprint planning update for the AI Gateway team (configurable for other teams via `scripts/config.sh`), ready to post as a GitHub comment on the sprint planning issue.

## Team Configuration

All team-specific values live in `scripts/config.sh`. The helper scripts source it automatically; the inline `gh` commands in this skill source it too, so always run them with the leading `source` line shown.

The defaults target the **AI Gateway** team:

| Variable | Default | Meaning |
| --- | --- | --- |
| `SPRINT_TEAM_SLUG` | `team-ai-gateway` | GitHub team slug under the org |
| `SPRINT_TEAM_NAME` | `AI Gateway` | Display name used in prose |
| `SPRINT_PROJECT_NUMBER` | _(unset)_ | Project board number — empty until the team has a board |
| `SPRINT_GOALS_URL` | `https://posthog.com/teams/ai-gateway#goals` | Goals page link |
| `SPRINT_COMMENT_HEADER` | `# Team AI Gateway` | Markdown heading identifying the team's comment |
| `SPRINT_ORG` | `PostHog` | GitHub org |
| `SPRINT_REPO` | `PostHog/posthog` | Repo holding sprint issues |
| `SPRINT_FALLBACK_MEMBERS` | `richardsolomou brandonleung` | Space-separated handles used only if the members API fails |

Override any value with an environment variable, or edit the defaults in `config.sh`.

In the output templates below, `{SPRINT_…}` placeholders refer to these config values; read them from `config.sh` (or `source` it) and substitute the resolved values before presenting output.

> **No project board yet:** the AI Gateway team does not have a project board, so `SPRINT_PROJECT_NUMBER` is empty by default. The board steps (Step 5, Step 13, and the board half of the `goals` workflow) detect this and skip cleanly — the plan is built from in-flight work and the user's input instead. When the team creates a board, set `SPRINT_PROJECT_NUMBER` in `config.sh` and these steps light up automatically.
>
> **Prerequisite (once a board exists):** the board scripts call `gh project`, which needs the `read:project` scope. If they fail with a missing-scope error, run `gh auth refresh -s read:project` once.

## Quarter Objectives

Pull the quarter goals and their statuses from the previous sprint's comment (Step 3). Carry them forward, applying any status changes the user confirms in Step 9. If no previous comment exists (the team's first sprint), ask the user for the team's current quarter objectives.

## Arguments

- `/rs-sprint-planning archive` — Skip the full sprint planning workflow and jump directly to archiving old Done items from the project board. When this argument is present:
  1. Run Step 1 (Detect Sprint Context) to get `sprint_start`
  2. Jump directly to Step 13 (Archive Previous Sprint's Done Items)
  3. Exit after archiving

- `/rs-sprint-planning goals` — Show what the team is currently working on by merging the current sprint plan with project board data, grouped by assignee. When this argument is present:
  1. Run Step G1 (Fetch Team Members)
  2. Run Step G2 (Determine Current User)
  3. Run Step G3 (Fetch Current Sprint Plan)
  4. Run Step G4 (Fetch Board Goals)
  5. Run Step G5 (Merge and Display)
  6. Exit after displaying

## Your Task

Follow these steps in order. Gather as much data automatically as possible before asking the user anything.

### Step 1: Detect Sprint Context

Run the helper script to find the current and previous sprint issues:

```bash
scripts/detect-sprint.sh
```

This returns tab-separated fields:
`current_number\tcurrent_title\tsprint_start\tsprint_end\tprev_number\tprev_title\tprev_start\tprev_end`

Store all these values. You need:

- `current_number` and `current_title` for the issue to post on
- `sprint_start` and `sprint_end` for the PR date range
- `prev_number` for fetching the previous comment
- `prev_start` and `prev_end` for the previous sprint's PR date range

### Step 2: Fetch Team Members

```bash
source scripts/config.sh
gh api "orgs/${SPRINT_ORG}/teams/${SPRINT_TEAM_SLUG}/members" --jq '.[].login'
```

If this fails (permissions, etc.), fall back to `SPRINT_FALLBACK_MEMBERS`, or ask the user for the team's members if it is empty.

### Step 3: Fetch Previous Sprint Comment

```bash
scripts/fetch-previous-comment.sh <prev_number>
```

If the result is "NOT_FOUND" (e.g., the team's first sprint), skip the plan-first retro approach entirely. You'll build the retro purely from merged PRs and project board items instead, confirmed with the user.

If the result is not "NOT_FOUND", parse the comment to extract:

- The **Plan** section from the previous sprint (this becomes the retro skeleton)
- Each team member's planned items
- The quarter goal statuses

### Step 4: Fetch Merged PRs

For each team member, fetch their merged PRs during the **previous** sprint period. Issue all fetch calls in parallel (multiple Bash tool calls in a single response) to minimize wall-clock time:

```bash
scripts/fetch-team-prs.sh <username> <prev_start> <prev_end>
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
scripts/fetch-team-open-prs.sh <username>
```

Bucket the open PRs by `createdAt`:

- Opened on or before `prev_end` → in-progress **retro** items (🟡) — work
  carried through last sprint but not yet merged.
- Opened after `prev_end` → in-flight **plan** seeds — what they're working on now.

`isDraft` marks early/WIP work; a non-draft open PR is review-ready. Read the
bodies here too.

### Step 5: Fetch Project Board Items

If `SPRINT_PROJECT_NUMBER` is empty (no board yet), skip this step — there are no board items to categorize. The plan in Step 9 is then drafted from the previous sprint's in-flight work and the user's input.

```bash
source scripts/config.sh
[ -n "$SPRINT_PROJECT_NUMBER" ] && gh project item-list "$SPRINT_PROJECT_NUMBER" --owner "$SPRINT_ORG" --format json --limit 200
```

Categorize items by status column:

- **Done** items inform the retro
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

Auto-resolve statuses: For each planned item, search the merged PRs (Step 4) for a match by:

- Issue number or PR number overlap
- Keyword similarity in titles
- Explicit references

If a matching merged PR is found, mark the item as done. Keep the PR's URL on hand for the rare case a reader would want to open it, but the bullet text is the outcome, not the PR title.

Identify side quests: Any merged PRs that don't map to a planned item are candidate "side quests" or unplanned work.

Path B - No previous plan (first sprint or NOT_FOUND):

Build the retro from merged PRs and project board "Done" items, grouping each person's work and presenting it for confirmation. Then add in-progress items from the open/draft PRs fetched in Step 4 (those opened on or before `prev_end`) so the retro reflects started-but-unfinished work, the way house retros do — not only what shipped. Prefix every item with a status emoji: `🟢` for shipped outcomes, `🟡` for each distinct in-progress workstream (collapse only PRs that are part of the same workstream).

**Synthesize, don't transcribe.** The retro audience is the wider company, not the team. Read each PR's description (Step 4 fetches it) and translate the raw PRs into plain-language outcomes:

- Describe **what was accomplished**, in terms a reader outside the team understands — grounded in the PR body, not the title alone, which is often verbose, too low-level, or undersells the actual change.
- **Collapse several related PRs into one bullet.** A bullet like "Built the spend path end to end — ledger, real-spend settlement, pre-call admission" beats nine PRs named `feat(quota): …`.
- **Links are the exception, not the rule.** Most bullets carry no link. Attach a single representative PR link only to a flagship item a reader might plausibly open. Never trail a bullet with a list of links.
- **Describe what was built or shipped, not ownership.** Avoid "owns" / "now owns" framing — the team doesn't claim ownership of components. "Built the model catalog", not "Built and now owns the model catalog".
- **Keep each bullet to one punchy line.** Headline outcome plus at most one short clause of the most telling specifics — not an exhaustive comma-list of every sub-detail. "Built the prepaid wallet & ledger — O(1) balances, bounded overspend, admin top-up", not a clause naming all six PRs' worth of detail. The reader skims; trim hard.
- Optionally group a person's bullets under a short theme when it aids reading; a small team's handful of bullets often needs no grouping at all.

### Step 8: Second Prompt - Retro Review

If previous plan exists (Path A), present the reconciled retro per person, each item as a plain-language outcome (not a PR title):

> Here's what I've reconstructed from last sprint's plan vs. what shipped:
>
> **@member1**
>
> - ✅ Planned outcome 1
> - ✅ Planned outcome 2
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

If no previous plan (Path B), present the synthesized accomplishments per person:

> Here's what I found shipped during the sprint:
>
> **@member1**
>
> - Plain-language outcome (synthesized from one or more PRs)
> - Another outcome
>
> **@member2**
>
> - Plain-language outcome
>
> Questions:
>
> 1. Do these accomplishments read accurately?
> 2. Anything missing that didn't result in PRs?
> 3. Anything to exclude?

Wait for the user's response.

### Step 9: Third Prompt - Plan and Objectives

If there is no board (Step 5 skipped), draft the plan **only from in-progress work**, then leave the rest for the user to fill out live. Specifically, seed each person's plan with:

1. Every `🟡` in-progress item from their retro (Step 7), reworded to imperative/future tense ("Scoped X" → "Finish X").
2. Their in-flight open/draft PRs from Step 4 (those opened after `prev_end`) — real continuing work.

**Do not invent plan items from the quarter goals.** Carrying a goal forward as a plan bullet with no in-progress work behind it is a guess; the user knows their own plan. After the in-progress items, add an italic placeholder bullet per person (e.g. `- _…(add the rest)_`) so they fill in the rest. Otherwise, present project board items as a draft plan:

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

**Fact-check the draft against the PR bodies first.** Synthesis from titles drifts — bullets overstate, miscategorize a 🟢 that's actually still open, or miss a whole workstream. Before finalizing, verify every retro and plan bullet against the merged + open PR data (titles *and* descriptions) from Step 4. For a non-trivial sprint, spawn one verification agent per team member (in parallel) that reads the PR bodies and returns, per bullet, a verdict: SUPPORTED (cite PR numbers), OVERSTATED (how to reword), WRONG, or MISCATEGORIZED (claimed 🟢 but PR still open/draft, or 🟡 but actually merged) — plus any substantial merged work MISSING from every bullet, and a status check that each 🟢 has a merged PR and each 🟡 is genuinely still open. Apply the corrections before presenting. This pass routinely catches real omissions and overstatements; don't skip it.

Then compose the final sprint update using all gathered and confirmed data.

**Write it in Richard's voice.** This comment gets posted under his name, so apply the [`rs-tone`](../rs-tone/SKILL.md) skill in the **`slack-status`** register (the closest fit for a status post — never `slack-casual` here). Generate in that register from the start, don't write neutral-assistant prose and rewrite. In practice: past tense for shipped retro items, future tense for plan items, no formulaic openers or sign-offs, no AI tells, terse bullets that each say one thing, concrete specifics over abstractions.

**IMPORTANT**: Output the update as raw markdown inside a code block so the user can copy/paste it directly into GitHub.

The format below mirrors the canonical issue template at [`.github/ISSUE_TEMPLATE/sprint_planning_retro.md`](https://github.com/PostHog/posthog/blob/master/.github/ISSUE_TEMPLATE/sprint_planning_retro.md) (the sprint issue body is generated from it) plus the house conventions visible in how teams actually post (see any open `Sprint - …` issue in `SPRINT_REPO` for live examples). Match it closely — the wider company reads these, so consistency matters. Notable conventions, easy to get wrong:

- **Status emoji prefix the line** — `- 🟡 Goal 1: …`, not a trailing emoji. Nest sub-items, each with its own emoji.
- **The legend is a single inline line at the bottom of the Retro `<details>`** — `🟢 =finished 🟡=in progress 🔴=won't finish ⚪=not started`. No separate legend block under Quarter goals.
- **No narrative paragraph** — the retro is bullets only, inside `<details>`.
- **Plan subsections are `### High priority`, `### Low priority / side quests`, and `### Are any other teams impacted by this plan? If so, tag them here`** — include all three, even if a section is just `-`.

Substitute the configured values: `SPRINT_COMMENT_HEADER` for the top heading, `SPRINT_GOALS_URL` for the goals link. Include a `[Project Board](https://github.com/orgs/{SPRINT_ORG}/projects/{SPRINT_PROJECT_NUMBER})` link under `## Plan` **only when `SPRINT_PROJECT_NUMBER` is set**; omit the line entirely when there's no board. The quarter goals come from Step 3 (or the user, for a first sprint), not the example below.

Retro shape depends on the path from Step 7:

- **Path A** (previous plan existed): grab last sprint's High priority and Low priority / side-quest items, tag each `@person`, and prefix each with a status emoji marking whether it completed — this matches the template's "grab the items from last time and add whether that item was completed" note.
- **Path B** (first sprint / NOT_FOUND): synthesized per-person outcome bullets with **no** status emoji.

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

- Plain-language outcome describing what shipped, synthesized from one or more PRs
- Another outcome — link a flagship item only when a reader might open it ([PR](url))

@member2

- Plain-language outcome

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

Write the final markdown to `~/dev/notes/PostHog/sprint-planning/<sprint_start>.md` (e.g. `2026-06-29.md` — sortable, one file per sprint), then commit and push so it's backed up to the private `notes` repo:

```bash
git -C ~/dev/notes add -A
git -C ~/dev/notes diff --cached --quiet || git -C ~/dev/notes commit -q -m "sprint-planning: <current_title>"
git -C ~/dev/notes push -q
```

The `diff --cached --quiet` guard skips the commit when nothing changed (e.g. a regenerated draft that matched). If the file already exists (re-run for the same sprint), overwrite it — the latest draft wins. If the push fails (offline, auth), report it but don't block. This is the pre-meeting draft; the user edits live after pasting, so the archive is a record of what was prepared, not the final posted comment.

### Step 12: Offer to Post

After showing the output, ask:

> Would you like me to post this as a comment on #{current_number}?

If the user confirms, post with:

```bash
source scripts/config.sh
gh issue comment <current_number> --repo "$SPRINT_REPO" --body "$(cat <<'EOF'
<the markdown>
EOF
)"
```

### Step 13: Archive Previous Sprint's Done Items

After posting the comment (or if the user declines to post), offer to clean up the project board by archiving Done items from previous sprints.

1. Run the helper script to find archivable items:

   ```bash
   scripts/archive-done-items.sh <sprint_start>
   ```

2. If the result is an empty array, skip silently — no prompt needed.

3. Otherwise, present the list and ask for confirmation:

   > I found {N} items in the Done column that were completed before this sprint ({sprint_start}). Would you like me to archive them to keep the board clean?
   >
   > {list of items with titles and closed dates}

4. If the user confirms, archive each item:

   ```bash
   source scripts/config.sh
   gh project item-archive "$SPRINT_PROJECT_NUMBER" --owner "$SPRINT_ORG" --id <item-id>
   ```

## Goals Workflow

These steps apply when the `goals` argument is provided. They run independently of the main sprint planning workflow.

### Step G1: Fetch Team Members

Follow Step 2 (Fetch Team Members) from the main workflow.

### Step G2: Determine Current User

```bash
gh api user --jq .login
```

This user's section is highlighted in the output. If the API call fails, fall back to the output of `git config user.email` and match against team member handles.

### Step G3: Fetch Current Sprint Plan

1. Detect the current sprint using Step 1 (Detect Sprint Context) from the main workflow.

2. Fetch the team's comment from the current sprint issue:

   ```bash
   scripts/fetch-previous-comment.sh <current_number>
   ```

3. If the result is "NOT_FOUND", skip this step (no sprint plan exists yet). The output will rely solely on board data from Step G4.

4. If a comment is found, parse the **Plan** section to extract each team member's planned items. Each item may be plain text or a `[title](url)` link.

### Step G4: Fetch Board Goals

Run the helper script to fetch In Progress and Todo items with assignee data:

```bash
scripts/fetch-board-goals.sh
```

This returns a JSON array of items, each with `id`, `title`, `status`, `url`, `type`, `number`, and `assignees` fields.

### Step G5: Merge and Display

Merge the sprint plan (Step G3) with the project board (Step G4) into a single view per team member.

**Merge strategy:**

1. Start from the sprint plan items as the baseline for each person.
2. For each board item, check if it matches a plan item by URL, issue/PR number, or keyword similarity in the title.
3. Matched items: use the board item's status (In Progress / Todo) and URL, preserving the plan's item description.
4. Unmatched plan items (not on the board): include as-is from the plan, without a status subheading.
5. Unmatched board items (not in the plan): append under a **"New (not in sprint plan):"** subheading.
6. If no sprint plan exists (Step G3 returned NOT_FOUND), display board items only, grouped by status as before.

**Output format:**

```markdown
## Team Goals - {SPRINT_TEAM_NAME}

[Project Board](https://github.com/orgs/{SPRINT_ORG}/projects/{SPRINT_PROJECT_NUMBER})

**--> @currentuser** (you)

**In Progress:**
- [Item from plan that's in progress on board](url)

**Todo:**
- [Item from plan that's todo on board](url)

**Other planned:**
- Item from plan not on board

**New (not in sprint plan):**
- [Board item not in plan](url) - In Progress

---

@teammate

**In Progress:**
- [Their item](url)

---

### Unassigned
- [Orphaned item](url) - In Progress
- Draft board item title - Todo
```

**Display rules:**

- Current user appears first with `**-->**` prefix and `(you)` suffix
- Other team members in alphabetical order
- Items with URLs use `[title](url)` links
- DraftIssues (no URL) show plain text title
- Unassigned items appear at bottom in a separate section
- Items with multiple assignees appear under each assignee
- Status subsections only shown if items exist for that status
- Only show team members who have at least one item assigned
- Side quests from the sprint plan appear under their own heading per person

## Formatting Rules

The output template in Step 10 is the authoritative format reference. These rules cover non-obvious behavior not visible in the template:

- **Retro bullets are outcomes, not PR titles** — synthesize what shipped into plain language a reader outside the team understands, collapsing related PRs into one bullet. Most bullets carry no link; attach at most one representative PR link to a flagship item, and never trail a bullet with a list of links.
- **Every retro item carries a status emoji** — both paths. Path A reconciles last sprint's plan items, each prefixed with whether it completed. Path B prefixes shipped outcomes with `🟢` and each distinct in-flight workstream with `🟡`. Don't mix bare bullets with emoji'd ones — it reads half-finished.
- **One distinct item per bullet** — split what would otherwise be a comma-joined list (separate in-progress workstreams, each impacted team, distinct plan items, each side quest) into its own bullet. This is the opposite of the synthesis rule, which only collapses PRs that are genuinely the same piece of work; two different efforts are two bullets. Side quests get a `Side quests:` parent line with one emoji-prefixed sub-bullet per quest, not a single comma-joined line.
- **Quarter-goal statuses prefix the line, not trail it** — `- 🟢 Goal 1: …`, with nested sub-items each carrying their own emoji.
- **The emoji legend is one inline line at the bottom of the Retro `<details>`** — `🟢 =finished 🟡=in progress 🔴=won't finish ⚪=not started`. Don't add a separate legend block under Quarter goals.
- **Plan always has all three subsections** — `### High priority`, `### Low priority / side quests`, and `### Are any other teams impacted by this plan? If so, tag them here` — even if a section is just `-`.
- **Include the Support hero line** — `**Support hero:**` sits above `**Off during the sprint:**`; use "N/A" when a small team has no rotation.
- **Project Board link only when a board exists** — omit the line entirely when `SPRINT_PROJECT_NUMBER` is unset.
- **Never post without explicit user confirmation** — always ask before running the `gh issue comment` command
