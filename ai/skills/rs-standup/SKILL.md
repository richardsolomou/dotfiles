---
name: rs-standup
description: "Generate a daily standup entry from your GitHub and Slack activity — queries everything you touched on GitHub since your previous standup (PRs merged, opened, reviewed, commented; issues) plus your Slack messages (debugging, incidents, decisions, support), composes terse bullets in your house style, archives the entry locally, and copies it to the clipboard as rich text. Use when the user asks to write, generate, or prep their standup / daily update / standup notes, or asks 'what did I do yesterday?' in a standup context."
---

# Standup Notes Generator

Generate a daily standup entry — terse bullets of what you did, ready to post under your name wherever your team keeps standups.

## The window (read this first)

A standup covers **everything you did from the moment of your previous standup until the moment you ask for this one** — a timestamp window, not a calendar day. Each entry records a `generated-at:` marker; the next run reads it and starts there. Consequences you must respect:

- **No overlap, no duplication.** Work already reported in the previous standup is before `window_start` and won't be picked up again.
- **No gaps.** Everything since the last standup is in scope, even if that was several days ago.
- **Generating advances the window.** The assumption is that you post right after generating, so anything you do *after* this run lands in the next standup. If you generated but did **not** post (or want a wider window for any reason), say so and widen `window_start` manually.

`window_start` comes from the script (Step 1) — never reach for "yesterday" or "the previous weekday".

## Purpose

Standups are retrospective — only what you did in the window, never what you plan to do next. In-flight work is described in the past tense as "started …" or "continuing …", not as a future intention.

## Style

Model entries on Brandon's approach:

- **Terse, lowercase phrases** — "phc PRs", "rate limits", "lots of pr reviews". No full sentences, no trailing punctuation.
- **No links.** Refer to PR counts instead — "put up 6 PRs to build out better status classifiers".
- **Lead bullet names the work stream or outcome**, sub-bullets enumerate the concrete pieces:

  ```text
  - landed the gateway operator admin stack (5 PRs)
    - per-team rate-limit overrides
    - force pricing refresh
    - provider host health overrides
  ```

- **Group related PRs** into one lead bullet rather than listing each.
- **Flag in-flight work** — "started per-product gateway routing", "continuing to try to get an e2e working in dev".
- **Include non-code work** — reviews, incidents, debugging, support, decisions, meetings, sales calls, holidays. The GitHub and Slack passes surface a lot of this; meetings, calls, and holidays still won't show up, so ask or let the user add them.

## Your Task

### Step 1: Get the Window

Run the helper script:

```bash
scripts/standup-dates.sh
```

It returns tab-separated: `<window_start>\t<now>\t<new_file_path>\t<date_header>\t<prev_file_path>`

Store these values:

- `window_start` — ISO 8601 UTC instant of your previous standup; the start of this entry's window. Feed it to every GitHub and Slack query below.
- `now` — ISO 8601 UTC instant of this run; the end of the window. Stamp it into the new entry's `generated-at:` marker (Step 6).
- `new_file_path` — where to write this entry (`YYYY-MM-DD.md`).
- `date_header` — header for the entry, e.g. "17 June".
- `prev_file_path` — the most recent existing entry, or empty. Used in Step 2.

### Step 2: Read the Previous Standup

If `prev_file_path` is non-empty, read it. Items marked "started" or "continuing" there may still be in flight and worth carrying as "continuing …" if GitHub shows more activity on them. (On a same-day re-run `prev_file_path` is today's own entry — that's fine; it tells you what you already reported earlier today, which is exactly what to avoid duplicating.)

### Step 3: Query GitHub for Activity

GitHub only tells half the story, and within GitHub it's not just your own PRs and commits — **any** activity counts: reviewing others' PRs, commenting, opening issues, triaging. Cast a wide net, then judge what's worth a bullet.

**Your PRs — merged and in-flight.** Run the helper script with `window_start`:

```bash
scripts/standup-prs.sh "${window_start}"
```

It emits a single JSON object:

```json
{
  "merged": [ {"number", "title", "repo", "merged_at"}, ... ],
  "active": [ {"number", "title", "repo", "isDraft", "commits": ["headline", ...]}, ... ]
}
```

- `merged` — PRs you authored that merged at/after `window_start` (the "landed" signal).
- `active` — open PRs you authored with at least one commit at/after `window_start`; the per-PR commit headlines tell you what was done, so treat them as "started …" (new this window) or "continuing …" (carried from a previous entry). PRs with no commits in the window are omitted.

Use the script rather than reaching for `gh` directly — it bakes in lessons that are easy to regress:

- It uses `gh api` throughout. `gh pr view --json commits` shells out to `git` and dies with "not a git repository" unless run from inside a clone — which the standup flow is not.
- It paginates the commits endpoint (commits come oldest-first, so a long-lived PR's recent commits are on the last page; a single page would miss them).
- It avoids `gh search prs --merged`, whose date filtering returns stale results.

**Everything else you touched** (PRs and issues you authored, commented on, were mentioned in, or assigned to, updated since the window start):

```bash
gh api search/issues --method GET -f q="involves:richardsolomou updated:>=${window_start} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url, is_pr: (.pull_request != null)}'
```

**PRs you reviewed** (`involves:` does not cover reviews, so query separately):

```bash
gh api search/issues --method GET -f q="reviewed-by:richardsolomou is:pr updated:>=${window_start} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url}'
```

The `updated:>=` qualifier accepts the full ISO timestamp, so it respects the sub-day window start.

**Deduplication**: these queries overlap with `standup-prs.sh` and each other — the same PR can appear several times. Dedup by `number` + repo. The window already excludes anything from before your last standup, so you won't re-report it. A heavy review/comment day is real standup material ("lots of pr reviews", "reviewed the X stack") even with no PRs of your own.

### Step 4: Query Slack for Activity

Much of what you did never reaches GitHub — debugging in a thread, incident response, design decisions, helping someone unblock, cross-team coordination, sales/support input. Search your own messages since the window start to surface it.

Use the `mcp__slack__conversations_search_messages` tool with its **structured filters** (not Slack search-operator syntax):

- `filter_users_from: "U0A008HMS48"` — always your **user ID**, not display name or handle; name/handle lookups don't reliably resolve in this tool.
- `filter_date_after: <date part of window_start>` — pass just the `YYYY-MM-DD` (this filter is date-granular and inclusive). Omit any `before`/date-on filter so the window runs through now.
- `limit: 100`

Because the Slack filter is only day-granular, **post-filter the results to the exact window**: drop any message whose `Time` (the ISO column in the results) is at or before `window_start`. This is what keeps a same-day re-run, or a window that starts mid-morning, from re-reporting earlier messages.

Then make sense of what remains:

- **Group by channel.** A burst of messages in one channel is usually one work stream — name it ("helped debug the gateway 5xx spike in #team-ai-gateway"), don't enumerate individual messages. For a substantive thread whose point isn't clear from your messages alone, pull the surrounding context with `conversations_replies` (channel + thread ts from the hit).
- **Keep substantive contributions** — debugging, decisions, incident response, design discussion, support, unblocking others. These are standup-worthy even with no PR attached.
- **Drop noise** — emoji reactions, GM/bye, social chatter, and your own standup posts.
- **Cross-reference GitHub** — Slack threads often discuss the same work as a PR; fold them into one bullet rather than double-counting.

If the search returns nothing useful, note that and lean on GitHub plus whatever the user adds.

### Step 5: Compose the Entry

Write the entry: terse lowercase bullets per the Style section, merging the GitHub and Slack passes into one picture of the window. Don't repeat PR titles verbatim — summarize like you'd say it out loud ("first-party gateway auth for posthog api keys", not the conventional-commit title). Group stacks of related PRs into a lead bullet with sub-bullets, and fold a Slack thread and its PR into a single bullet.

If activity looks thin across both sources, note that to the user — they likely have meetings, calls, or offline work to add.

### Step 6: Write the Archive File

Write the plain markdown file at `new_file_path`, ending with a `generated-at:` marker set to `now` from Step 1. The marker is how the next run finds this window's end — do not omit it.

```text
# 4 June

- first-party gateway auth for posthog api keys (phx_/pha_)
- per-product attribution via X-PostHog-Product header
- started per-product gateways via /g/{slug} routing
- phcode: merged rich text → markdown paste in the composer

<!-- generated-at: 2026-06-04T17:30:00Z -->
```

**Same-day re-run** (`new_file_path` already exists): append the new bullets under the existing ones rather than overwriting the morning's work, and update the `generated-at:` marker to the new `now`. The clipboard (Step 7) still carries only the new delta — that's what you'd post.

### Step 7: Copy to Clipboard as Rich Text

Load the `rs-copy` skill via the Skill tool and hand it the bullets as HTML — it converts to RTF and puts a real list (not fake spacing) on the clipboard. Copy just the bullets; the date header and your name line are added wherever you post. Use nested `<ul><li>` for sub-bullets, e.g.:

```html
<ul>
<li>landed the gateway operator admin stack (5 PRs)
<ul>
<li>per-team rate-limit overrides</li>
<li>force pricing refresh</li>
</ul>
</li>
<li>started per-product gateway routing</li>
</ul>
```

Standup entries contain no links, so nested lists are always safe here (the Slack link-in-list quirk rs-copy warns about only bites when `<a>` tags sit inside list items).

### Step 8: Report to User

Display:

1. The generated entry (plain text for review)
2. The file path for easy access
3. A message: "Copied to clipboard as rich text — paste under your name in your standup!"

## Notes

- The standup notes are stored in `~/dev/richardsolomou/notes/PostHog/standup/`, named `YYYY-MM-DD.md` for easy sorting.
- The local files are the archive *and* the source of truth for the window: each entry's `generated-at:` marker is what the next run reads to find `window_start`. Don't strip the marker.
- The window is timestamp-precise on both passes: GitHub qualifiers take the full ISO instant directly; Slack's filter is day-granular, so you post-filter by message `Time` (Step 4).
