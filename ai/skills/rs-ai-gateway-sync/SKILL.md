---
name: rs-ai-gateway-sync
description: "Prep your weekly AI Gateway sync — a Monday retrospective of what you shipped last week plus what you're focusing on this week, drawn from your GitHub and Slack activity since the previous sync. Use when the user asks to prep, write, or generate their AI Gateway sync / weekly sync / Monday sync."
---

# AI Gateway Weekly Sync

Prep the weekly AI Gateway sync — two short sections, ready to post under your name: **Last week** (what you shipped, retrospective) and **This week** (what you're focusing on, forward-looking).

This is the standup's weekly sibling with a forward half — same window mechanics, different cadence (Monday-to-Monday) and a much terser shape. Load the `rs-activity-harvest` skill first — it owns the window mechanics, the GitHub and Slack harvest queries, and the archive step this workflow references.

## The two sections

- **Last week** is retrospective — only what you did in the window, past tense. In-flight work reads as "started …" / "continuing …", never as a future intention.
- **This week** is forward-looking — what you intend to focus on. It draws from your still-open PRs and carried-over "started/continuing" items as *candidates*, but the tools can't see meetings, planned work, or anything not yet on GitHub, so this section is always finished by hand. Treat the auto-surfaced items as a checklist to confirm, cut, or expand — not the final answer.

## Style

Diction comes from `rs-tone` register `slack-status`, compressed hard: this is read live in a meeting, scanned at a glance — **very brief fragments, not sentences**. One short line per work stream, just enough to jog your memory and say it out loud.

- **Fragments, not prose.** A few words each — `gateway live in prod-us + prod-eu, phs_ auth, gated per-team`. No filler verbs where a noun phrase lands it.
- **One work stream, one line.** Fold concrete pieces in with commas or `→`; no sub-bullets.
- **Terse and lowercase.** No trailing punctuation. Abbreviate freely (`w/`, `+`, `→`, PR numbers).
- **Lead with the thing, compress the why.** `billing bypass: gzip nil-usage went free → fail closed`.
- **No PR counting, no conventional-commit titles.** A bare `#147/#148` reference is fine when it's the quickest pointer.
- **Last week is past/done; this week is intent** (`land …`, `close …`, `pick up …`).
- **Include non-code work** — reviews, incidents, design, meetings — same one-line treatment. Meetings/calls/offline won't show up in the harvest, so ask or let the user add them.

Example of the target shape:

```text
## Last week

- gateway live in prod-us + prod-eu, phs_ auth, gated per-team
- credential last-used → no revoking in-use keys; O(1) session admit
- AIO double-bill: provenance design w/ ingestion (HMAC sign + verify)
- billing bypass: gzip nil-usage went free → fail closed
- autopilot build→review loop → whole obs stack

## This week

- land obs stack (metrics, tracing, alerts + runbooks)
- land AIO provenance chain w/ ingestion
- close billing bypass (#147/#148)
- bedrock fallback allowlist (e2e) + phe_ scoped tokens (blocked: attribution)
```

## Your Task

### Step 1: Get the Window

```bash
~/.claude/skills/rs-activity-harvest/scripts/activity-dates.sh PostHog/ai-gateway-sync week previous
```

Store the five fields per the harvest skill's *Dates script* section. `previous` gives the sync its same-day re-run semantics: the window stretches back to the real previous sync, not this morning's run. A skipped Monday widens the window automatically.

### Step 2: Read the Previous Sync

If `prev_file_path` is non-empty, read it. Its **This week** section is the strongest signal for what was in flight — items still open are prime candidates for this week's **Last week** (did they ship?) and possibly this week's focus again (still going?). Its "started/continuing" notes carry the same way.

### Step 3: Query GitHub for Activity

```bash
~/.claude/skills/rs-activity-harvest/scripts/author-prs.sh "${window_start}" open include
```

- `merged` → **Last week** ("shipped …").
- `open` with non-empty `commits` → **Last week** in-flight work ("started …" / "continuing …").
- `open` (all of it, regardless of `commits`) → **This week** focus candidates — the in-flight backlog. A draft or untouched-this-week PR is exactly the kind of thing that becomes next week's focus.

Then run the harvest skill's wider queries — *everything you touched*, *PRs you reviewed*, *issue comments and inline review comments* — and dedup per its rules. A heavy review week is real sync material even with no PRs of your own.

### Step 4: Query Slack for Activity

Apply the harvest skill's *Slack harvest* section as written. For #team-ai-gateway threads especially, the channel bursts are where the substance is.

### Step 5: Compose the Entry

Write both sections per the Style section.

- **Last week**: merge the GitHub and Slack passes into one picture, one brief fragment per work stream.
- **This week**: lay out the surfaced candidates (open PRs, carried "started/continuing" items) as focus bullets in intent voice, then **explicitly ask the user what else to add or cut** — meetings, planned work, priorities the tools can't see. This section is collaborative by design; don't present it as complete.

If activity looks thin, say so — the user likely has offline work and plans to add.

### Step 6: Write the Archive File

Write the entry at `new_file_path` per the harvest skill's *Archive to notes* section, commit prefix `ai-gateway-sync:`. Shape:

```text
# Week of 22 June

## Last week

- …

## This week

- …

<!-- generated-at: 2026-06-22T16:30:00Z -->
```

**Same-day re-run** (`new_file_path` exists): update both sections and the `generated-at:` marker rather than blindly overwriting — preserve any focus items the user hand-added earlier.

### Step 7: Report to User

Display:

1. The generated entry (plain text for review).
2. The file path.
3. The open question for **This week**: "Anything to add or cut from the focus list — meetings, planned work, priorities I can't see from GitHub/Slack?"

## Notes

- The **This week** section is never fully machine-derived — always close the loop with the user before considering the entry done.
