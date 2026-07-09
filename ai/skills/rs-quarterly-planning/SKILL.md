---
name: rs-quarterly-planning
description: "Prep quarterly planning for the AI Gateway team the PostHog way — quarter review, HOGS, themes, and next quarter's objectives PR on posthog.com. Use when the user asks to prep/run quarterly planning, write the quarter retro/review, draft the HOGS, or open/update the objectives PR. Configurable for other teams via `scripts/config.sh`."
argument-hint: "[review|hogs|pr]"
---

# Quarterly Planning

Prep and run quarterly planning for the **AI Gateway** team (configurable for other teams via `scripts/config.sh`), following PostHog's [goal-setting process](https://posthog.com/handbook/company/goal-setting). The end product is a PR on the team's `objectives.mdx` page setting next quarter's goals, tagged for the relevant Blitzscale member to review.

The process, per the handbook:

- **Cadence:** every quarter. Blitzscale sets company direction ~3 weeks before quarter end; team leads run a planning meeting ~2 weeks before; the lead opens a goals PR on the team page; PRs merge before the next quarter starts.
- **Meeting split:** ~20% reviewing the quarter that's ending, ~80% setting next quarter's goals. The review is filled in async beforehand. A well-prepared meeting takes an hour max.
- **HOGS** are written **privately and independently** by each person *before* reading anyone else's, then pasted in together so nobody is skewed by the others' thinking.

This skill produces the async prep — the review and a HOGS scaffold — and, once goals are agreed, drafts and opens the objectives PR.

## Team Configuration

All team-specific values live in `scripts/config.sh`. The helper scripts source it automatically; the inline `gh`/`git` commands in this skill source it too, so always run them with the leading `source` line shown.

The defaults target the **AI Gateway** team:

| Variable | Default | Meaning |
| --- | --- | --- |
| `QP_ORG` | `PostHog` | GitHub org (members API + PR search) |
| `QP_TEAM_SLUG` | `team-ai-gateway` | GitHub team slug under the org |
| `QP_TEAM_NAME` | `AI Gateway` | Display name used in prose |
| `QP_TEAM_PAGE_SLUG` | `ai-gateway` | Folder under `contents/teams/` on posthog.com |
| `QP_POSTHOG_COM_DIR` | `~/dev/posthog/posthog.com` | Local checkout of the posthog.com repo |
| `QP_OBJECTIVES_PATH` | *(derived)* | Path to the team's `objectives.mdx` |
| `QP_GOALS_URL` | `https://posthog.com/teams/ai-gateway#objectives` | Goals page link |
| `QP_BLITZSCALE_REVIEWER` | *(unset)* | Handle to tag on the objectives PR — ask if empty |
| `QP_FALLBACK_MEMBERS` | `richardsolomou brandonleung` | Handles used only if the members API fails |

Override any value with an environment variable, or edit the defaults in `config.sh`. In the templates below, `{QP_…}` placeholders refer to these values; `source config.sh` and substitute the resolved values before presenting output.

## What makes a good goal (handbook bar)

Hold every drafted objective to this bar:

- **As few objectives as possible.** Each one is simple, ambitious, and clearly pass/fail.
- **Lead with motivation** — *why* this matters, in one or two lines.
- **"What we'll ship" are leading indicators** — concrete things achievable quickly that point at the objective. Hitting the objective matters more than shipping any specific item.
- **Output-based first.** Use metrics only where they genuinely sharpen the goal; targets must be specific and not arbitrary. Anti-goals / counter-metrics can clarify scope.
- **Ambitious but achievable.** Consistent misses mean the goals were wrong for the team, not that the team failed.

## Arguments

- `/rs-quarterly-planning review` — Only produce the past-quarter review (the async 20%). Run Steps 1–4, then Step 5, and stop.
- `/rs-quarterly-planning hogs` — Only generate the private HOGS scaffold for the user to fill in. Run Step 1, then Step 6, and stop.
- `/rs-quarterly-planning pr` — Skip prep and jump to opening/updating the objectives PR from goals the user provides (post-meeting). Run Step 1, then the **Objectives PR Workflow**.

With no argument, run the full prep flow (Steps 1–8), then offer the Objectives PR Workflow.

## Your Task

Follow these steps in order. Gather as much data automatically as possible before asking the user anything.

### Step 1: Detect Quarter Context

```bash
scripts/detect-quarter.sh
```

Returns tab-separated fields:
`cur_label\tcur_start\tcur_end\tnext_label\tnext_start\tnext_end\tdays_until_cur_end`

Store these. `cur_*` is the quarter being **reviewed**; `next_*` is the quarter being **planned**. Use `days_until_cur_end` to note where in the cycle we are: ~21 days out is when Blitzscale sets direction, ~14 days out is when the team meeting runs, and goals should merge before `cur_end`. If we're well outside that window, say so but proceed — the user may be planning early or catching up.

### Step 2: Fetch Team Members

```bash
source scripts/config.sh
gh api "orgs/${QP_ORG}/teams/${QP_TEAM_SLUG}/members" --jq '.[].login'
```

If this fails (permissions, etc.), fall back to `QP_FALLBACK_MEMBERS`, or ask the user for the team's members if it is empty.

### Step 3: Read the Current Objectives

Read the team's existing objectives page — the goals being reviewed — from the local posthog.com checkout:

```bash
source scripts/config.sh
cat "$QP_OBJECTIVES_PATH"
```

If the file is missing or `QP_POSTHOG_COM_DIR` isn't a checkout, note it and ask the user for this quarter's objectives (or treat as a first-time team with no prior goals). **Capture the file's exact format** — heading style (`### Q2 2026 objectives`), goal heading style (`#### Goal N: Title`), owner-tagging convention (`(Driver: <TeamMember name="…" />)`, `(owner)` in a summary, or none), and the description / "What we'll ship" labels. The new quarter must match this format exactly.

### Step 4: Fetch Merged PRs

For each team member, fetch their merged PRs across the **current** quarter (`cur_start` to `cur_end`). Issue all fetch calls in parallel (multiple Bash tool calls in one response):

```bash
source scripts/config.sh
~/.claude/skills/rs-activity-harvest/scripts/team-merged-prs.sh <username> "$QP_ORG" <cur_start> <cur_end> 500
```

Store all PR data per member. A quarter is a lot of PRs — you'll synthesize, not list, them. The fetch is deliberately title-only (hundreds of bodies would swamp the context at quarter scale); when a flagship or ambiguous item needs more than its title to score an objective, fetch that PR's body selectively with `gh pr view <url> --json body`.

### Step 5: Build the Past-Quarter Review

This is the async 20%. For **each current objective** (Step 3), assess how it landed and back the assessment with the shipped work (Step 4):

- 🟢 **Hit** — shipped and the outcome held.
- 🟡 **Partial** — meaningful progress, not all the way there.
- 🔴 **Missed** — little or no movement. Note why if it's clear from the work (descoped, blocked, displaced by other priorities).

**Synthesize, don't transcribe.** Map PRs onto objectives by keyword/area and collapse related PRs into plain-language outcomes a reader outside the team understands — not PR titles. Flag notable work that didn't map to any objective (off-goal work — fine in moderation, a signal if it dominated). Keep links rare: at most one representative PR link per flagship outcome.

Present the review for confirmation:

> **{cur_label} review — {QP_TEAM_NAME}**
>
> 1. *First objective* — 🟢 Hit. One-line plain-language outcome.
> 2. *Second objective* — 🟡 Partial. What landed, what didn't.
> 3. …
>
> **Off-goal work worth noting:** …
>
> Does this match how the quarter actually went? Anything I've mis-scored or missed?

Wait for the user's response. If invoked with `review`, stop here.

### Step 6: HOGS

HOGS are written **privately and independently** before anyone reads the others' — that's the whole point, so people aren't anchored. So your job here is to hand the user a scaffold to fill in *their own* HOGS, seeded lightly from the review and shipped work as prompts — not to write them.

Present the scaffold (substitute `{next_label}`):

> Write your HOGS for **{next_label}** privately before the meeting — fill these in yourself; don't let mine anchor you. Paste them into the shared doc only at the session start.
>
> - **Hope** — what are you most excited about? What exploration do you want to do?
> - **Obstruction** — what's embarrassing about the product today? What stops us shipping 2× faster?
> - **Growth** — what would move the needle most? What are users actually asking for?
> - **Sneak attack** — how might a competitor beat us here? What's under-discussed?
>
> Want a few neutral prompts under each (drawn from this quarter's review) to react to — or would you rather start from a blank page?

If the user wants prompts, offer terse bullets framed as questions, not answers. If the user pastes their own HOGS (and optionally teammates'), carry them into Step 7. If invoked with `hogs`, stop after presenting the scaffold.

### Step 7: Distill Themes

From the HOGS (Step 6) and the review (Step 5), distill a short list of **themes** — the handful of directions the next quarter's goals should cover. Cross company direction from Blitzscale here too: ask the user what the company-level objectives are this quarter (the skill can't read the private Blitzscale doc) and note which themes ladder up to them.

Present 3–6 themes, each one line, and ask which to turn into objectives.

### Step 8: Draft Next Quarter's Objectives

Turn the agreed themes into objectives that clear the **good-goal bar** above. Aim for as few as the work honestly needs. For each: a short title, a one/two-line motivation, and a tight "What we'll ship" list of leading indicators, each tagged with an owner from the team.

Render them **in the exact format of the existing `objectives.mdx`** (Step 3) — same heading levels, same owner-tagging convention, same labels — under a new `{next_label}` quarter heading. Output as raw markdown in a code block so it can be reviewed and dropped straight into the file.

Present the draft and ask:

> Here's a draft of the **{next_label}** objectives in the team-page format. Two questions:
>
> 1. Are these the right objectives, and is each one genuinely pass/fail and ambitious-but-achievable?
> 2. Owners look right?
>
> Once you're happy, I can open the objectives PR on posthog.com.

Wait for the user's response. Then offer the Objectives PR Workflow.

## Objectives PR Workflow

Reached after Step 8, or directly via the `pr` argument (in which case ask the user for the finalized goals first). Creates a PR on posthog.com replacing the previous quarter's objectives with the new quarter's.

### Step P1: Verify the Repo

```bash
source scripts/config.sh
git -C "$QP_POSTHOG_COM_DIR" rev-parse --is-inside-work-tree && \
  git -C "$QP_POSTHOG_COM_DIR" status --short
```

If it isn't a checkout, stop and tell the user where `QP_POSTHOG_COM_DIR` should point. If the working tree is dirty, surface that and ask before proceeding — don't stash or discard their changes.

### Step P2: Branch off the latest default branch

```bash
source scripts/config.sh
git -C "$QP_POSTHOG_COM_DIR" fetch origin
default_branch=$(gh repo view PostHog/posthog.com --json defaultBranchRef --jq .defaultBranchRef.name)
git -C "$QP_POSTHOG_COM_DIR" switch -c "${QP_TEAM_PAGE_SLUG}-objectives-$(echo "$next_label" | tr 'A-Z ' 'a-z-')" "origin/${default_branch}"
```

(Name the branch descriptively, e.g. `ai-gateway-objectives-q3-2026`.)

### Step P3: Update objectives.mdx

Replace the previous quarter's objectives section in `$QP_OBJECTIVES_PATH` with the new `{next_label}` section from Step 8. The page shows the current/upcoming quarter, so **replace** rather than append — unless the team's existing file keeps prior quarters, in which case follow that convention. Match the file's exact formatting (Step 3); change nothing else on the page.

Run the repo's formatter if it's wired up (`bin/fmt`, or `pnpm prettier`/the documented command) and revert any reformatting it makes to lines you didn't touch.

### Step P4: Commit, push, open the PR

Never push or open a PR without explicit user confirmation. On confirmation:

```bash
source scripts/config.sh
git -C "$QP_POSTHOG_COM_DIR" add "$QP_OBJECTIVES_PATH"
git -C "$QP_POSTHOG_COM_DIR" commit -m "${QP_TEAM_NAME} ${next_label} objectives"
git -C "$QP_POSTHOG_COM_DIR" push -u origin HEAD
```

Open the PR with `gh`, using the repo's PR template if present (`.github/pull_request_template.md`); otherwise a short Problem / Changes body, written in the `rs-tone` `pr-description` register. Request review from `QP_BLITZSCALE_REVIEWER` — if it's empty, ask the user who the team's Blitzscale member is before opening.

```bash
source scripts/config.sh
reviewer_flag=""
[ -n "$QP_BLITZSCALE_REVIEWER" ] && reviewer_flag="--reviewer $QP_BLITZSCALE_REVIEWER"
gh pr create --repo "PostHog/posthog.com" \
  --title "${QP_TEAM_NAME} ${next_label} objectives" \
  --body "$(cat <<'EOF'
<the PR body>
EOF
)" $reviewer_flag
```

Report the PR URL.
