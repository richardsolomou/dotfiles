---
name: rs-standup
description: "Generate a daily standup entry from your GitHub and Slack activity — queries everything you touched on GitHub since the last standup (PRs merged, opened, reviewed, commented; issues) plus your Slack messages (debugging, incidents, decisions, support), composes terse Slack-canvas bullets in your house style, archives the entry locally, and copies it to the clipboard as rich text. Use when the user asks to write, generate, or prep their standup / daily update / standup notes, or asks 'what did I do yesterday?' in a standup context."
---

# Standup Notes Generator

Generate a daily standup entry for the team's shared Slack canvas (<https://posthog.slack.com/docs/TSS5W8YQZ/F0B50R20SMA>).

## Purpose

Standups are daily (weekdays), written as bullets under your `@Richard` name in the canvas. Each day has a date header (e.g. "4 June"), newest at the top, and each person adds a bullet list of what they did that day. It is purely retrospective — only what you did today/yesterday, never what you plan to do next. In-flight work is described in the past tense as "started …" or "continuing …", not as a future intention.

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

### Step 1: Get Date Context

Run the helper script to get standup dates:

```bash
scripts/standup-dates.sh
```

This returns tab-separated: `<today>\t<last_standup_date>\t<new_file_path>\t<canvas_date_header>`

Store these values:

- `today` - Today's date (for the new standup file)
- `last_standup_date` - Previous weekday (for the GitHub and Slack queries)
- `new_file_path` - Where to write the new standup notes
- `canvas_date_header` - Date header for the canvas entry (e.g. "5 June")

### Step 2: Find Previous Standup Notes

Run the helper script to find previous standup notes:

```bash
scripts/standup-find.sh
```

This returns tab-separated: `<status>\t<path>\t<date>`

If `status` is "found", read the previous notes — items marked "started" or "continuing" there may still be in flight and worth carrying as "continuing …" if GitHub shows more activity on them.

### Step 3: Query GitHub for Activity

GitHub only tells half the story, and within GitHub it's not just your own PRs and commits — **any** activity counts: reviewing others' PRs, commenting, opening issues, triaging. Cast a wide net, then judge what's worth a bullet.

**Your PRs — merged and in-flight.** Run the helper script with `last_standup_date`:

```bash
scripts/standup-prs.sh "${last_standup_date}"
```

It emits a single JSON object:

```json
{
  "merged": [ {"number", "title", "repo", "merged_at"}, ... ],
  "active": [ {"number", "title", "repo", "isDraft", "commits": ["headline", ...]}, ... ]
}
```

- `merged` — PRs you authored that merged on/after `last_standup_date` (the "landed" signal).
- `active` — open PRs you authored with at least one commit on/after `last_standup_date`; the per-PR commit headlines tell you what was done, so treat them as "started …" (new this period) or "continuing …" (carried from a previous entry). PRs with no commits in the window are omitted.

Use the script rather than reaching for `gh` directly — it bakes in lessons that are easy to regress:

- It uses `gh api` throughout. `gh pr view --json commits` shells out to `git` and dies with "not a git repository" unless run from inside a clone — which the standup flow is not.
- It paginates the commits endpoint (commits come oldest-first, so a long-lived PR's recent commits are on the last page; a single page would miss them).
- It avoids `gh search prs --merged`, whose date filtering returns stale results.

**Everything else you touched** (PRs and issues you authored, commented on, were mentioned in, or assigned to, updated since last standup):

```bash
gh api search/issues --method GET -f q="involves:richardsolomou updated:>=${last_standup_date} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url, is_pr: (.pull_request != null)}'
```

**PRs you reviewed** (`involves:` does not cover reviews, so query separately):

```bash
gh api search/issues --method GET -f q="reviewed-by:richardsolomou is:pr updated:>=${last_standup_date} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url}'
```

**Deduplication**: these queries overlap with `standup-prs.sh` and each other — the same PR can appear several times. Dedup by `number` + repo, and exclude anything already reported in the previous standup (the date qualifiers include the last standup day itself). A heavy review/comment day is real standup material ("lots of pr reviews", "reviewed the X stack") even with no PRs of your own.

### Step 4: Query Slack for Activity

Much of what you did never reaches GitHub — debugging in a thread, incident response, design decisions, helping someone unblock, cross-team coordination, sales/support input. Search your own messages since the last standup to surface it.

Use the `mcp__slack__conversations_search_messages` tool with its **structured filters** (not Slack search-operator syntax):

- `filter_users_from: "U0A008HMS48"` — always your **user ID**, not display name or handle; name/handle lookups don't reliably resolve in this tool.
- `filter_date_after: <last_standup_date>` — this filter is **inclusive**, so it captures the last standup day onward, matching the GitHub `>=` qualifiers. Omit any `before`/date-on filter so the window runs through now.
- `limit: 100`

Then make sense of the results:

- **Group by channel.** A burst of messages in one channel is usually one work stream — name it ("helped debug the gateway 5xx spike in #team-ai-gateway"), don't enumerate individual messages. For a substantive thread whose point isn't clear from your messages alone, pull the surrounding context with `conversations_replies` (channel + thread ts from the hit).
- **Keep substantive contributions** — debugging, decisions, incident response, design discussion, support, unblocking others. These are standup-worthy even with no PR attached.
- **Drop noise** — emoji reactions, GM/bye, social chatter, and your own standup-canvas posts.
- **Cross-reference GitHub** — Slack threads often discuss the same work as a PR; fold them into one bullet rather than double-counting.

If the search returns nothing useful, note that and lean on GitHub plus whatever the user adds.

### Step 5: Compose the Entry

Write the canvas entry: terse lowercase bullets per the Style section, merging the GitHub and Slack passes into one picture of the day. Don't repeat PR titles verbatim — summarize like you'd say it out loud ("first-party gateway auth for posthog api keys", not the conventional-commit title). Group stacks of related PRs into a lead bullet with sub-bullets, and fold a Slack thread and its PR into a single bullet.

If activity looks thin across both sources, note that to the user — they likely have meetings, calls, or offline work to add.

### Step 6: Write the Archive File

Create the plain markdown file at `new_file_path`:

```text
# 4 June

- first-party gateway auth for posthog api keys (phx_/pha_)
- per-product attribution via X-PostHog-Product header
- started per-product gateways via /g/{slug} routing
- phcode: merged rich text → markdown paste in the composer
```

### Step 7: Copy to Clipboard as Rich Text

Load the `rs-copy` skill via the Skill tool and hand it the bullets as HTML — it converts to RTF and puts a real Slack list (not fake spacing) on the clipboard. Copy just the bullets; the date header and `@Richard` line usually already exist in the canvas or are added by hand. Use nested `<ul><li>` for sub-bullets, e.g.:

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
3. A message: "Copied to clipboard as rich text — paste under your name in the standup canvas!"

## Notes

- The standup notes are stored in `~/dev/richardsolomou/notes/PostHog/standup/`
- Files are named `YYYY-MM-DD.md` for easy sorting
- The canvas is the source of truth; the local files are just an archive of your own entries
- Step 4 reads your Slack *messages* via the MCP, but the canvas itself is a Slack file and the MCP token lacks `files:read` — so the canvas can't be read or written programmatically. Delivery stays clipboard-paste (Step 7), and if you need prior canvas context beyond the local archive, ask the user to paste it.
