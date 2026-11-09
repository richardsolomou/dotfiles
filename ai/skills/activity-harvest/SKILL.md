---
name: activity-harvest
description: "Shared machinery for standup, inbox, sprint-planning, and quarterly-planning: the activity window, GitHub and Slack harvest queries, and archive-to-notes. Load only when one of those skills points here."
user-invocable: false
---

# Activity Harvest

Each caller defines its own cadence, style, and output. Identity constants: GitHub user `richardsolomou`, Slack user ID `U0A008HMS48`.

## The window

An entry covers the immutable half-open interval **`[window_start, window_end)`** — a timestamp window, not a calendar day/week. `window_start` is the previous archived entry's `generated-at:` marker; `window_end` is the `now` returned by the dates script. Pass both instants to every source query so activity arriving during composition cannot appear in two entries.

- **No gaps.** Everything since the last entry is in scope, even if that was longer ago than the nominal cadence.
- **Generating advances the window.** If the user generated but did **not** post (or wants a wider window), widen `window_start` manually on request.

`window_start` always comes from the dates script — never reach for "yesterday" or "last Monday".

### Dates script

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh <notes-subdir> <header-style: date|week> <same-day: reuse|previous>
```

Returns tab-separated: `<window_start>\t<now>\t<new_file_path>\t<header>\t<prev_file_path>\t<slack_after>`

- `window_start`, `now` — ISO 8601 UTC instants; `now` is stamped into the new entry's `generated-at:` marker.
- `new_file_path` — where to write this entry (`YYYY-MM-DD.md` under `~/dev/notes/<notes-subdir>/`, dated the generation day).
- `header` — human header ("17 June" for `date`, "Week of 17 June" for `week`), matching the file date.
- `prev_file_path` — the most recent existing entry, or empty.
- `slack_after` — the value for Slack's `filter_date_after`; see [Slack harvest](#slack-harvest).

The `same-day` argument sets re-run semantics when `new_file_path` already exists: `reuse` treats that same-date entry as the previous one, so a daily standup covers only the delta since the earlier run. `previous` skips it, so a weekly sync reaches back to the prior real sync and regenerates the current artifact.

### Per-day split

Callers that keep one entry per day split a multi-day window with:

```bash
~/.agents/skills/activity-harvest/scripts/activity-days.sh "${window_start}" "${now}" "$(dirname "${new_file_path}")"
```

Returns one tab-separated line per local calendar day: `<day_start>\t<day_end>\t<file_path>\t<header>`. Days run from `window_start`'s local date through today. Each day ends at the next local midnight, and today ends at `now`. Harvest each sub-window with its own bounds.

## Run the passes concurrently

Issue the GitHub, Slack, and T3 Code passes as parallel tool calls when the runtime permits it. Do not spawn agents only to collect activity.

Each result must follow this digest contract:

- **Facts, not conclusions.** Commit headlines, PR titles and numbers, quoted comment/message substance, channel names.
- **Join keys on everything.** Repo + number for GitHub items; channel plus any PR/issue numbers mentioned for Slack threads.
- **Grouped by candidate work stream**, evidence under each.
- **Gaps declared.** Failed queries, empty passes, truncations — stated in the digest, never silently dropped.

## GitHub harvest

One call fetches the whole pass concurrently:

```bash
~/.agents/skills/activity-harvest/scripts/github-harvest.sh "${window_start}" "${now}" <open-key> <untouched: skip|include>
```

Emits a single JSON object:

- `merged` / `<open-key>` — your PRs, exactly as author-prs.sh below.
- `involved` — everything you touched (authored, commented, mentioned, assigned) updated since the window start.
- `reviewed` — PRs you reviewed (`involves:` does not cover reviews).
- `issue_comments` / `review_comments` — your comments across every surfaced repo, fully paginated.
- `reviews` — summary-only reviews on reviewed PRs that left no inline comments.
- `errors` — partial failures. **Never ignore this**: a non-empty list means a blind spot in the harvest; say so.

Reading rules:

- **Dedup by number + repo** — the same PR appears in several lists.
- **Personal repos are never material.** Queries are scoped `org:PostHog`; drop anything from `richardsolomou/*` (tro.gg, stream-setup) entirely — not even folded into another bullet.
- Comment/review bodies are truncated to 500 chars — fetch the full text with `gh` when a digest needs more.
- A heavy review/comment period is real material ("lots of pr reviews", "reviewed the X stack") even with no PRs of your own.
- The `updated:`/`merged:` qualifiers take the full ISO timestamp.

**Your PRs only** — the wrapper's inner pass, usable standalone when the wider sweep isn't needed:

```bash
~/.agents/skills/activity-harvest/scripts/author-prs.sh "${window_start}" "${now}" <open-key> <untouched: skip|include>
```

Emits `{"merged": [{number, title, repo, merged_at}, …], "<open-key>": [{number, title, repo, isDraft, commits: [headline, …]}, …]}`. `merged` is PRs you authored that merged inside the window. The open list carries each PR's in-window commit headlines. `untouched: skip` drops open PRs with no commits in the window. `include` keeps the full in-flight backlog for weekly focus candidates.

Use the scripts rather than `gh` directly: `gh pr view --json commits` dies outside a clone (everything uses `gh api`); `gh search prs --merged` has stale date filtering; the per-PR commits endpoint pages oldest-first, so recent commits need pagination; the comment endpoints return all users' comments, so skipping `--paginate` silently drops yours on busy repos.

## Slack harvest

Search your own messages with `mcp__slack__conversations_search_messages` using its **structured filters** (not Slack search-operator syntax):

- `filter_users_from: "U0A008HMS48"` — always the user ID; name/handle lookups don't reliably resolve in this tool.
- `filter_date_after: <slack_after>` from the dates script. The filter is day-granular and **excludes** the date it is given, so the date part of `window_start` would drop that day's messages. Omit any before/on filter.
- `limit: 100`, following the cursor until it is empty.

**Post-filter the results to the exact half-open window**: keep messages whose `Time` is at or after `window_start` and before `now`.

Then make sense of what remains:

- **Group by channel.** A burst in one channel is usually one work stream — name it, don't enumerate messages. Pull surrounding context with `conversations_replies` when your messages alone don't tell the story.
- **Keep substance** — debugging, decisions, incidents, design discussion, support, unblocking others, cross-team coordination.
- **Drop noise** — reactions, GM/bye, social chatter, and your own standup/sync posts.
- **Cross-reference GitHub** — fold a thread and its PR into one bullet rather than double-counting.

If the search returns nothing useful, note that and lean on GitHub plus whatever the user adds.

## T3 Code harvest

Reads T3 Code's local state database in place and read-only, so the app can stay open:

```bash
~/.agents/skills/activity-harvest/scripts/t3code-activity.sh "${window_start}" "${now}"
```

Exit 3 means T3 Code moved its database or changed its schema: treat it as a failed pass and fix the script, never as an empty result.

One tab-separated line per thread that received a prompt inside the window: the first in-window prompt instant, the project relative to `~/dev`, the branch, the thread title, any linked PR URLs, and the in-window prompts joined with ` | ` and truncated to 240 characters.

This is a **memory-jogger, not a primary source**. A linked PR URL is the join key for folding a thread into the GitHub or Slack passes. A thread earns material only when its outcome is invisible to the other passes. Ignore greetings, one-word follow-ups, and meta threads. A burst of near-identical prompts can be evidence of live testing. Drop threads whose project is outside `posthog/`.

## Archive to notes

Before writing, ask: which source supports each completion or outcome claim, and does another source contradict it? A source item may nominate a work stream, but intent, a prompt, or an open artifact does not prove completion.

If any required pass failed or was truncated, show an explicitly incomplete draft and name the pass that must be rerun. Do not write or replace the archived entry, and do not advance `generated-at`, unless the caller explicitly defined that pass as optional. An empty successful pass is not a failure.

Write the complete entry as plain markdown at `new_file_path`, ending with the marker the next run reads — do not omit it:

```text
<!-- generated-at: <now> -->
```

Then commit and push, staging only the generated entry, using its path relative to `~/dev/notes`:

```bash
git -C ~/dev/notes add -- <relative-entry-path>
git -C ~/dev/notes diff --cached --quiet || git -C ~/dev/notes commit -q -m "<prefix>: <header>"
git -C ~/dev/notes push -q
```

If the push fails (offline, auth), report it but don't block.
