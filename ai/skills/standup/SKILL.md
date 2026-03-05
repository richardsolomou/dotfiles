---
name: standup
description: Generate standup notes from GitHub PR activity
disable-model-invocation: true
---

# Standup Notes Generator

Generate standup notes for PostHog standups (Monday, Wednesday, Friday).

## Purpose

Every standup, you need to report:

- **Did**: PRs merged since last standup
- **Will do**: PRs with recent activity + items from last standup not yet done

## Your Task

### Step 1: Get Date Context

Run the helper script to get standup dates:

```bash
~/.claude/skills/standup/scripts/standup-dates.sh
```

This returns tab-separated: `<today>\t<last_standup_date>\t<new_file_path>`

Store these values:

- `today` - Today's date (for the new standup file)
- `last_standup_date` - When the previous standup was (for PR queries)
- `new_file_path` - Where to write the new standup notes

### Step 2: Find Previous Standup Notes

Run the helper script to find previous standup notes:

```bash
~/.claude/skills/standup/scripts/standup-find.sh
```

This returns tab-separated: `<status>\t<path>\t<date>`

If `status` is "found":

- Read the previous standup notes at `<path>`
- Extract the "Will do" items that are NOT completed (for carry-over)

### Step 3: Query GitHub for PR Activity

**Completed PRs** (merged since last standup):

```bash
gh api search/issues --method GET -f q="author:richardsolomou is:pr is:merged merged:>=${last_standup_date}" --jq '.items[] | {number, title, url: .html_url, repo: .repository_url, merged_at: .pull_request.merged_at}'
```

Note: `gh search prs --merged` is unreliable for date filtering — it returns stale results. Always use `gh api search/issues` with the `merged:` qualifier instead, which returns accurate `merged_at` timestamps.

**Active PRs** (open PRs across the PostHog org with recent activity):

```bash
gh api search/issues --method GET -f q="author:richardsolomou is:pr is:open org:PostHog" --jq '.items[] | {number, title, url: .html_url, repo: .repository_url}'
```

For each open PR found, fetch draft status and review requests:

```bash
gh pr view <number> --repo <owner/repo> --json isDraft,reviewRequests
```

### Step 4: Analyze and Compose Standup Notes

Build the standup content with clickable links for Slack. You'll generate both:

1. **Plain text** (for the archive file)
2. **HTML** (for RTF clipboard copy - links work when pasted into Slack)

**Did Section:**

- List all PRs that were merged since `last_standup_date`
- Use **past tense** for the description
- If no PRs were merged, use a single item: "Nothing merged since last standup"

Plain text format:

```text
Added `getFeatureFlagResult` method for efficient flag + payload retrieval (https://github.com/PostHog/posthog-js/pull/2920)
```

**Will Do Section:**

- Include open PRs with recent activity
- Carry over items from the previous standup's "Will do" — but verify each one first:
  - For items with a PR URL, check the PR state: `gh pr view <number> --repo <owner/repo> --json state,mergedAt`
  - If **MERGED** since last standup: add it to the Did section (deduplicate by PR number — the merged PR search may not catch every PR, so this is the safety net)
  - If **CLOSED**: drop it from the standup entirely
  - If **OPEN**: keep it in Will do
- Description first, then status indicator in parentheses as a link
- Determine PR status:
  - If `isDraft` is true: link text is "draft"
  - If `reviewRequests` includes "llm-analytics" team or any reviewer: link text is "needs review"
  - Otherwise for open PRs: link text is "PR"
- For non-PR work items: just plain text description

Plain text format:

```text
Simplify readiness probe to prevent cascade failures (https://github.com/PostHog/posthog/pull/46589 - draft)
```

### Step 5: Write the Standup Notes

Create the **plain text file** at `new_file_path` for archival:

```text
Did:
Did something awesome (https://github.com/org/repo/pull/123)
Fixed the thing that was broken (https://github.com/org/repo/pull/456)

Will do:
Description of draft work (https://github.com/org/repo/pull/789 - draft)
Description of work needing review (https://github.com/org/repo/pull/101 - needs review)
Non-PR work item description
```

### Step 6: Copy to Clipboard as Rich Text

Generate HTML and copy to clipboard as rich text using the helper script. The script converts HTML to RTF via NSAttributedString for proper rendering when pasted into Slack.

**IMPORTANT — Slack clipboard quirk**: `<a>` links inside `<ul><li>` list items break Slack's list rendering when pasting rich text. To work around this, use `<p>` tags with bullet characters (`•`) instead of `<ul><li>` for items that contain links. Items without links can use either format.

Use `<p>` tags for section headers (bold) and `<p>` tags with `•` for each item. Separate sections with `<br>` for spacing.

Create the HTML content:

```html
<p><b>Did:</b></p>
<p>• Did something awesome (<a href="https://github.com/org/repo/pull/123">PR</a>)</p>
<p>• Fixed the thing that was broken (<a href="https://github.com/org/repo/pull/456">PR</a>)</p>
<br>
<p><b>Will do:</b></p>
<p>• Description of draft work (<a href="https://github.com/org/repo/pull/789">draft</a>)</p>
<p>• Description of work needing review (<a href="https://github.com/org/repo/pull/101">needs review</a>)</p>
<p>• Non-PR work item description</p>
```

Copy to clipboard using the helper script:

```bash
swift ~/.claude/skills/standup/scripts/copy-html-to-clipboard.swift <<'EOF'
<p><b>Did:</b></p>
<p>• ...</p>
<br>
<p><b>Will do:</b></p>
<p>• ...</p>
EOF
```

### Step 7: Report to User

Display:

1. The generated standup notes (plain text version for review)
2. The file path for easy access
3. A message: "Copied to clipboard as rich text — paste directly into Slack!"

## Example Output

**Plain text (saved to file):**

```text
Did:
Added `getFeatureFlagResult` method for efficient flag + payload retrieval (https://github.com/PostHog/posthog-js/pull/2920)
Added bin scripts for setup, build, and test (https://github.com/PostHog/posthog-js/pull/2824)

Will do:
Simplify readiness probe to prevent cascade failures (https://github.com/PostHog/posthog/pull/46589 - draft)
Add source field to feature flag created analytics (https://github.com/PostHog/posthog/pull/46782 - needs review)
Add HyperCache support to flag definitions cache (https://github.com/PostHog/posthog/pull/44701 - needs review)
Completing migration of celery tasks to dedicated flags queue
```

**HTML (copied to clipboard as rich text):**

```html
<p><b>Did:</b></p>
<p>• <a href="https://github.com/PostHog/posthog-js/pull/2920">Added <code>getFeatureFlagResult</code> method for efficient flag + payload retrieval</a></p>
<p>• <a href="https://github.com/PostHog/posthog-js/pull/2824">Added bin scripts for setup, build, and test</a></p>
<br>
<p><b>Will do:</b></p>
<p>• Simplify readiness probe to prevent cascade failures (<a href="https://github.com/PostHog/posthog/pull/46589">draft</a>)</p>
<p>• Add source field to feature flag created analytics (<a href="https://github.com/PostHog/posthog/pull/46782">needs review</a>)</p>
<p>• Add HyperCache support to flag definitions cache (<a href="https://github.com/PostHog/posthog/pull/44701">needs review</a>)</p>
<p>• Completing migration of celery tasks to dedicated flags queue</p>
```

## Notes

- The standup notes are stored in `~/dev/richardsolomou/notes/PostHog/standup/`
- Files are named `YYYY-MM-DD.md` for easy sorting
- Previous standup notes are used to identify carry-over work items
- **Rich text clipboard**: Uses `<p>` tags with `•` bullet characters and `<a>` links — Slack breaks list rendering when `<a>` tags are inside `<ul><li>`, so we avoid that combination
- **Plain text file**: Archived for reference with URLs in parentheses
- Did items use past tense with the whole description as link text
- Will do items have plain text description + status as link in parentheses
- Sections are separated by `<br>` for visual spacing in Slack
