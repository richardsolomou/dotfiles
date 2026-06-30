---
name: rs-ai-gateway-sync
description: "Prep your weekly AI Gateway sync — a Monday retrospective of what you shipped last week plus what you're focusing on this week. Auto-pulls your GitHub PR activity (merged + in-flight) and Slack messages since the previous sync, composes a two-part entry (Last week / This week) as very brief at-a-glance bullets, surfaces open PRs as candidate focus items for you to confirm and extend, and archives the entry locally. Use when the user asks to prep, write, or generate their AI Gateway sync / weekly sync / Monday sync."
---

# AI Gateway Weekly Sync

Prep the weekly AI Gateway sync — two short sections, ready to post under your name: **Last week** (what you shipped, retrospective) and **This week** (what you're focusing on, forward-looking).

This is the standup's weekly sibling with a forward half. Same window mechanics and house voice as `rs-standup`; the difference is the second section and the cadence (Monday-to-Monday, not since-yesterday).

## The window (read this first)

The retrospective covers **everything you did from the moment of your previous sync until the moment you ask for this one** — a timestamp window, not a calendar week. Each entry records a `generated-at:` marker; the next run reads it and starts there.

- **No overlap, no duplication.** Work already in the previous sync is before `window_start` and won't reappear.
- **No gaps.** Everything since the last sync is in scope, even if that was more than a week ago (a skipped Monday widens the window automatically).
- **Generating advances the window.** Anything you do after this run lands in next week's sync. If you generated but didn't post, or want a wider window, say so and widen `window_start` manually.

`window_start` comes from the script (Step 1) — never reach for "last Monday".

## The two sections

- **Last week** is retrospective — only what you did in the window, past tense. In-flight work reads as "started …" / "continuing …", never as a future intention. This is the standup half.
- **This week** is forward-looking — what you intend to focus on. It draws from your still-open PRs and carried-over "started/continuing" items as *candidates*, but the tools can't see meetings, planned work, or anything not yet on GitHub, so this section is always finished by hand. Treat the auto-surfaced items as a checklist to confirm, cut, or expand — not the final answer.

## Style

This is read live in a meeting, scanned at a glance — **very brief fragments, not sentences**. One short line per work stream, just enough to jog your memory and say it out loud. The GitHub/Slack passes are how you *find* the work; the output is the shortest label that still means something.

- **Fragments, not prose.** A few words each — `gateway live in prod-us + prod-eu, phs_ auth, gated per-team`, not a full sentence. No filler verbs where a noun phrase lands it.
- **One work stream, one line.** Fold concrete pieces in with commas or `→`; no sub-bullets.
- **Terse and lowercase.** No trailing punctuation. Abbreviate freely (`w/`, `+`, `→`, PR numbers).
- **Lead with the thing, compress the why.** `billing bypass: gzip nil-usage went free → fail closed`, not a paragraph explaining it.
- **No PR counting, no conventional-commit titles.** A bare `#147/#148` reference is fine when it's the quickest pointer.
- **Last week is past/done; this week is intent** (`land …`, `close …`, `pick up …`).
- **Include non-code work** — reviews, incidents, design, meetings — same one-line treatment. GitHub and Slack surface a lot; meetings/calls/offline won't, so ask or let the user add them.

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
scripts/sync-dates.sh
```

Tab-separated: `<window_start>\t<now>\t<new_file_path>\t<week_header>\t<prev_file_path>`. Store each:

- `window_start` — ISO 8601 UTC of your previous sync; start of this window. Feed every GitHub/Slack query below.
- `now` — ISO 8601 UTC of this run; end of the window. Stamp into the `generated-at:` marker (Step 6).
- `new_file_path` — where to write (`YYYY-MM-DD.md`).
- `week_header` — header, e.g. "Week of 22 June".
- `prev_file_path` — most recent existing entry, or empty.

### Step 2: Read the Previous Sync

If `prev_file_path` is non-empty, read it. Its **This week** section is the strongest signal for what was in flight — items still open are prime candidates for this week's **Last week** (did they ship?) and possibly this week's focus again (still going?). Its "started/continuing" notes carry the same way.

### Step 3: Query GitHub for Activity

```bash
scripts/sync-github.sh "${window_start}"
```

Emits:

```json
{
  "merged": [ {"number","title","repo","merged_at"}, ... ],
  "open":   [ {"number","title","repo","isDraft","recentCommits":["headline", ...]}, ... ]
}
```

- `merged` → **Last week** ("shipped …").
- `open` with non-empty `recentCommits` → **Last week** in-flight work ("started …" / "continuing …").
- `open` (all of it, regardless of `recentCommits`) → **This week** focus candidates — the in-flight backlog. A draft or untouched-this-week PR is exactly the kind of thing that becomes next week's focus.

Then cast wider for non-authored work. **Everything you touched:**

```bash
gh api search/issues --method GET -f q="involves:richardsolomou updated:>=${window_start} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url, is_pr: (.pull_request != null)}'
```

**PRs you reviewed** (`involves:` doesn't cover reviews):

```bash
gh api search/issues --method GET -f q="reviewed-by:richardsolomou is:pr updated:>=${window_start} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url}'
```

`updated:>=` accepts the full ISO timestamp, so it respects the sub-day window start. **Dedup** by `number` + repo across all three queries. A heavy review week is real sync material even with no PRs of your own.

### Step 4: Query Slack for Activity

Much of the gateway work never reaches GitHub — debugging a 5xx spike in a thread, incident response, design decisions, cross-team coordination with ingestion/billing. Search your own messages since the window start.

Use `mcp__slack__conversations_search_messages` with **structured filters** (not search-operator syntax):

- `filter_users_from: "U0A008HMS48"` — always your user ID.
- `filter_date_after: <date part of window_start>` — just `YYYY-MM-DD` (day-granular, inclusive). Omit any before/on filter so it runs through now.
- `limit: 100`

Because the Slack filter is day-granular, **post-filter to the exact window**: drop any message whose `Time` is at or before `window_start`. Then:

- **Group by channel** — a burst in one channel is one work stream; name it, don't enumerate. For #team-ai-gateway threads especially, this is where the substance is. Pull surrounding context with `conversations_replies` when your messages alone don't tell the story.
- **Keep substance** — debugging, decisions, incidents, design, unblocking others. **Drop noise** — reactions, GM/bye, social chatter, your own sync/standup posts.
- **Cross-reference GitHub** — fold a thread and its PR into one bullet.

If the search returns nothing useful, note that and lean on GitHub plus what the user adds.

### Step 5: Compose the Entry

Write both sections per the Style section.

- **Last week**: merge the GitHub and Slack passes into one picture, one brief fragment per work stream.
- **This week**: lay out the surfaced candidates (open PRs, carried "started/continuing" items) as focus bullets in intent voice, then **explicitly ask the user what else to add or cut** — meetings, planned work, priorities the tools can't see. This section is collaborative by design; don't present it as complete.

If activity looks thin, say so — the user likely has offline work and plans to add.

### Step 6: Write the Archive File

Write plain markdown at `new_file_path`: the `# {week_header}` line, the two `##` sections, ending with a `generated-at:` marker set to `now`. The marker is how the next run finds the window — don't omit it.

```text
# Week of 22 June

## Last week

- …

## This week

- …

<!-- generated-at: 2026-06-22T16:30:00Z -->
```

**Same-day re-run** (`new_file_path` exists): update both sections and the `generated-at:` marker rather than blindly overwriting — preserve any focus items the user hand-added earlier. (`sync-dates.sh` already points `window_start` at the real previous sync, not this morning's run, so the retrospective window is correct.)

Then back up to the private `notes` repo:

```bash
git -C ~/dev/notes add -A
git -C ~/dev/notes diff --cached --quiet || git -C ~/dev/notes commit -q -m "ai-gateway-sync: ${week_header}"
git -C ~/dev/notes push -q
```

The `diff --cached --quiet` guard skips a no-op commit; the push is a no-op when there's nothing new. If the push fails (offline, auth), report it but don't block — the file is written locally.

### Step 7: Report to User

Display:

1. The generated entry (plain text for review).
2. The file path.
3. The open question for **This week**: "Anything to add or cut from the focus list — meetings, planned work, priorities I can't see from GitHub/Slack?"

## Notes

- Entries live in `~/dev/notes/PostHog/ai-gateway-sync/`, named `YYYY-MM-DD.md` for sorting.
- The local files are the archive *and* the window source: each `generated-at:` marker is what the next run reads for `window_start`. Don't strip it.
- The window is timestamp-precise on both passes: GitHub qualifiers take the full ISO instant; Slack's filter is day-granular, so you post-filter by message `Time` (Step 4).
- The **This week** section is never fully machine-derived — always close the loop with the user before considering the entry done.
