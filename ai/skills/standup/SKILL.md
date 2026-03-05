---
name: standup
description: "Generate a daily standup summary from GitHub and Slack activity, then write to ~/standups/YYYY-MM-DD.md."
user_invocable: true
---

# Standup

Generate a daily standup summary from GitHub and Slack activity, then write to ~/standups/YYYY-MM-DD.md.

## Arguments

- `/standup` - Today (previous day 7pm local → now; Friday 7pm → now on Mondays)
- `/standup yesterday` - Previous standup window
- `/standup monday`, `tuesday`, etc. - That day's standup window
- `/standup N days` - N days ago at 7pm local to now

## Prerequisites

- GitHub CLI (`gh`) must be authenticated.
- Slack MCP server must be configured (handles Slack authentication).

## Your Task

### Step 1: Preflight Checks

```bash
gh auth status 2>&1
```

If gh is not authenticated, tell the user to run `gh auth login` and stop.

### Step 2: Compute the Standup Window

The standup hour is **19:00 local time** (7pm). Compute the window based on the argument:

| Argument | SINCE | UNTIL | FILE_DATE |
| -------- | ----- | ----- | --------- |
| (none) / today | Yesterday 19:00 local → UTC | Now (UTC) | Today |
| (none) on Monday | Friday 19:00 local → UTC | Now (UTC) | Today |
| yesterday | 2 days ago 19:00 local → UTC | Yesterday 19:00 local → UTC | Yesterday |
| day name (e.g. monday) | Day before that 19:00 local → UTC | That day 19:00 local → UTC | That day |
| N days | N days ago 19:00 local → UTC | Now (UTC) | Today |

Compute all values silently in a single bash command and output only the final values. Do NOT echo intermediate calculations or run separate verification commands. Output exactly these four lines:

```text
SINCE=<UTC ISO 8601>
UNTIL=<UTC ISO 8601>
FILE_DATE=<YYYY-MM-DD>
```

### Step 3: Gather GitHub Activity

Get the GitHub username and run ALL of these in parallel (use separate Bash calls). Replace `$SINCE` and `$UNTIL` with the computed UTC timestamps, and `$USER` with the GitHub username. Include `gh api /user --jq '.login'` as one of the parallel calls:

1. PRs I opened:

    ```bash
    gh search prs --author=@me --created="$SINCE..$UNTIL" --json repository,title,number,url,state --limit 50
    ```

2. PRs I merged:

    ```bash
    gh search prs --author=@me --merged --json repository,title,number,url --limit 50 -- "merged:$SINCE..$UNTIL"
    ```

3. PRs I reviewed:

    ```bash
    gh search prs --reviewed-by=@me --updated=">=$SINCE" --json repository,title,number,url,author --limit 50 -- "-author:$USER"
    ```

4. Issues I created:

    ```bash
    gh search issues --author=@me --created="$SINCE..$UNTIL" --json repository,title,number,url --limit 50
    ```

5. Issues/PRs I commented on:

    ```bash
    gh search issues --commenter=@me --updated=">=$SINCE" --include-prs --json repository,title,number,url,author --limit 50 -- "-author:$USER"
    ```

6. My commits:

    ```bash
    gh search commits --author=@me --author-date="$SINCE..$UNTIL" --json repository,sha,commit --limit 50
    ```

7. PRs awaiting my review:

    ```bash
    gh search prs --review-requested=@me --state=open --json repository,title,number,url,author --limit 50
    ```

8. My open PRs:

    ```bash
    gh search prs --author=@me --state=open --json repository,title,number,url --limit 50
    ```

### Step 4: Gather Slack Activity

The Slack user ID is `U0A008HMS48`.

Extract date-only values from SINCE and UNTIL for Slack's date filters. Both `filter_date_after` and `filter_date_before` are **exclusive** (messages on those exact dates are excluded), so subtract 1 day from SINCE_DATE and add 1 day to UNTIL_DATE. For example, if the window is `2026-02-23T17:00:00Z` to `2026-02-24T18:00:00Z`, use `filter_date_after: "2026-02-22"` and `filter_date_before: "2026-02-25"`.

Use the `mcp__slack__conversations_search_messages` tool for both searches. Run both in parallel:

1. Messages I sent:

    ```text
    mcp__slack__conversations_search_messages(
      filter_users_from: "U0A008HMS48",
      filter_date_after: "$SINCE_DATE_MINUS_1",
      filter_date_before: "$UNTIL_DATE_PLUS_1",
      limit: 50
    )
    ```

2. Messages in threads/DMs involving me (from others):

    ```text
    mcp__slack__conversations_search_messages(
      filter_users_with: "U0A008HMS48",
      filter_date_after: "$SINCE_DATE_MINUS_1",
      filter_date_before: "$UNTIL_DATE_PLUS_1",
      limit: 30
    )
    ```

If either call fails, report the error and stop.

### Step 5: Synthesize the Standup

Using all the gathered data, synthesize a standup summary. Your output must start with "Did:" - no preamble, commentary, or explanations.

**Grouping:**

- Group closely related items (e.g., 3 PRs for the same feature = one bullet with sub-bullets or inline links)
- Group by theme/project, not by artifact type
- A PR that was both opened and merged is one bullet, not two
- Only use sub-bullets when there are multiple distinct items under one theme

**Writing style:**

- Casual, conversational tone
- Lead with strong action verbs: "Shipped", "Landed", "Merged", "Opened", "Continued work on", "Reviewed/approved", "Debugged", "Pitched", "Chatted with", "Synced with", "Met with"
- Include non-code activity naturally: meetings, 1:1s, syncs, Slack discussions, support, pitches
- Include repo name when it adds useful context or when multiple repos are involved
- Weave in Slack context where it relates to a GitHub item
- Append Slack-formatted links to PRs/issues: `<URL|label>` where label is "PR", "issue", etc.
- When a bullet references multiple PRs, list each link inline: `<url|PR>` `<url|PR>`

**Inferring "Will do":**

- Open PRs I authored = will continue/land
- PRs awaiting my review = will review
- Active Slack threads = may continue discussion
- Do NOT fabricate work - only list items with evidence

**Output format - ONLY output this, nothing else:**

```text
Did:
- bullet
- bullet

Will do:
- bullet
- bullet
```

**Rules:**

- No headers beyond "Did:" and "Will do:"
- No preamble or closing
- No mention of tools, sources, or data availability
- Use `-` for bullets, 4-space indented `-` for sub-bullets
- Blank line between Did and Will do sections
- If no activity, output: "No activity found for the given date range."

### Step 6: Write Output

```bash
mkdir -p ~/standups
```

Write the synthesized standup to `~/standups/{FILE_DATE}.md` using the Write tool.

Tell the user the file path when done.
