---
name: rs-standup
description: "Generate a daily standup entry from your GitHub PR activity — queries merged and active PRs since the last standup, composes terse Slack-canvas bullets in your house style, archives the entry locally, and copies it to the clipboard as rich text. Use when the user asks to write, generate, or prep their standup / daily update / standup notes, or asks 'what did I do yesterday?' in a standup context."
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
- **Include non-PR work** the user mentions — reviews, incidents, meetings, sales calls, holidays. GitHub queries won't surface these; ask or let the user add them.

## Your Task

### Step 1: Get Date Context

Run the helper script to get standup dates:

```bash
scripts/standup-dates.sh
```

This returns tab-separated: `<today>\t<last_standup_date>\t<new_file_path>\t<canvas_date_header>`

Store these values:

- `today` - Today's date (for the new standup file)
- `last_standup_date` - Previous weekday (for PR queries)
- `new_file_path` - Where to write the new standup notes
- `canvas_date_header` - Date header for the canvas entry (e.g. "5 June")

### Step 2: Find Previous Standup Notes

Run the helper script to find previous standup notes:

```bash
scripts/standup-find.sh
```

This returns tab-separated: `<status>\t<path>\t<date>`

If `status` is "found", read the previous notes — items marked "started" or "continuing" there may still be in flight and worth carrying as "continuing …" if GitHub shows more activity on them.

### Step 3: Query GitHub for PR Activity

**Merged PRs** (merged since last standup):

```bash
gh api search/issues --method GET -f q="author:richardsolomou is:pr is:merged merged:>=${last_standup_date}" --jq '.items[] | {number, title, url: .html_url, repo: .repository_url, merged_at: .pull_request.merged_at}'
```

Note: `gh search prs --merged` is unreliable for date filtering — it returns stale results. Always use `gh api search/issues` with the `merged:` qualifier instead, which returns accurate `merged_at` timestamps.

**Deduplication**: The `merged:>=` query includes PRs merged on the last standup day itself, which may already appear in the previous standup's notes. Exclude anything already reported.

**Active PRs** (open PRs across the PostHog org):

```bash
gh api search/issues --method GET -f q="author:richardsolomou is:pr is:open org:PostHog" --jq '.items[] | {number, title, url: .html_url, repo: .repository_url}'
```

For each open PR found, check for commits since `last_standup_date`:

```bash
gh pr view <number> --repo <owner/repo> --json isDraft,commits
```

Open PRs with recent commits represent work done — include them as "started …" (new this period) or "continuing …" (carried from a previous entry).

### Step 4: Compose the Entry

Write the canvas entry: terse lowercase bullets per the Style section. Don't repeat PR titles verbatim — summarize like you'd say it out loud ("first-party gateway auth for posthog api keys", not the conventional-commit title). Group stacks of related PRs into a lead bullet with sub-bullets.

If GitHub activity looks thin (mostly reviews/meetings days), note that to the user — they likely have non-PR items to add.

### Step 5: Write the Archive File

Create the plain markdown file at `new_file_path`:

```text
# 4 June

- first-party gateway auth for posthog api keys (phx_/pha_)
- per-product attribution via X-PostHog-Product header
- started per-product gateways via /g/{slug} routing
- phcode: merged rich text → markdown paste in the composer
```

### Step 6: Copy to Clipboard as Rich Text

The entries contain no links, so nested `<ul><li>` is safe (the Slack link-in-list quirk only bites when `<a>` tags are inside list items). Copy just the bullets — the date header and `@Richard` line usually already exist in the canvas or are added by hand:

```bash
swift scripts/copy-html-to-clipboard.swift <<'EOF'
<ul>
<li>landed the gateway operator admin stack (5 PRs)
<ul>
<li>per-team rate-limit overrides</li>
<li>force pricing refresh</li>
</ul>
</li>
<li>started per-product gateway routing</li>
</ul>
EOF
```

### Step 7: Report to User

Display:

1. The generated entry (plain text for review)
2. The file path for easy access
3. A message: "Copied to clipboard as rich text — paste under your name in the standup canvas!"

## Notes

- The standup notes are stored in `~/dev/richardsolomou/notes/PostHog/standup/`
- Files are named `YYYY-MM-DD.md` for easy sorting
- The canvas is the source of truth; the local files are just an archive of your own entries
- The Slack MCP token lacks `files:read`, so the canvas itself can't be read programmatically — ask the user to paste it if you need recent context beyond the local archive
