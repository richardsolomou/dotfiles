---
name: activity-harvest
description: "Shared machinery for the cadence skills (standup, sprint-planning, and quarterly-planning): the activity window, the GitHub and Slack harvest queries, and the archive-to-notes step. Load only when one of those skills points here; not useful standalone."
user-invocable: false
---

# Activity Harvest

Shared mechanics for the cadence skills. Each caller defines its own cadence, style, and output; this skill owns how the activity window works, how GitHub and Slack are queried, and how entries are archived. Identity constants live here once: GitHub user `richardsolomou`, Slack user ID `U0A008HMS48`.

## The window

An entry covers **everything from the moment of the previous entry until the moment of this run** — a timestamp window, not a calendar day/week. Each archived entry ends with a `generated-at:` marker; the next run reads it as `window_start`.

- **No overlap, no duplication.** Work already reported is before `window_start` and won't be picked up again.
- **No gaps.** Everything since the last entry is in scope, even if that was longer ago than the nominal cadence.
- **Generating advances the window.** The assumption is that you post right after generating. If the user generated but did **not** post (or wants a wider window), widen `window_start` manually on request.

`window_start` always comes from the dates script — never reach for "yesterday" or "last Monday".

### Dates script

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh <notes-subdir> <header-style: day|week> <same-day: reuse|previous>
```

Returns tab-separated: `<window_start>\t<now>\t<new_file_path>\t<header>\t<prev_file_path>`

- `window_start` — ISO 8601 UTC instant of the previous entry; feed it to every GitHub and Slack query.
- `now` — ISO 8601 UTC instant of this run; stamp it into the new entry's `generated-at:` marker.
- `new_file_path` — where to write this entry (`YYYY-MM-DD.md` under `~/dev/notes/<notes-subdir>/`, dated per below).
- `header` — human header ("17 June" for `day`, "Week of 17 June" for `week`), matching the file date.
- `prev_file_path` — the most recent existing entry, or empty.

For `day` style, the file and header carry the date the entry is **for** — the business day it covers — not the generation day: a run at noon or later is for today (a worked weekend keeps its own date); a morning run is for the previous business day (Tuesday 9am → Monday's entry, Monday 9am → Friday's, weekend work included via the window). `generated-at:` still records the real instant, so windows stay gapless. `week` style is dated the generation day.

The `same-day` argument sets re-run semantics when `new_file_path` already exists: `reuse` treats that same-date entry as the previous one, so a daily standup covers only the delta since the earlier run. `previous` skips it, so a weekly sync reaches back to the prior real sync and regenerates the current artifact.

## Run the passes concurrently

The GitHub, Slack, and T3 Code passes are independent. Issue them as parallel tool calls when the runtime permits it. Do not spawn agents only to collect activity.

Each result must follow this digest contract:

- **Facts, not conclusions.** Commit headlines, PR titles and numbers, quoted comment/message substance, channel names. The caller writes the narrative; a pre-summarized digest launders away the evidence the house style needs.
- **Join keys on everything.** Repo + number for GitHub items; channel plus any PR/issue numbers mentioned for Slack threads. Folding a thread and its PR into one bullet happens at compose time and is impossible without them.
- **Grouped by candidate work stream**, evidence under each.
- **Gaps declared.** Failed queries, empty passes, truncations — stated in the digest, never silently dropped.

## GitHub harvest

One call fetches the whole pass concurrently — your PRs, the wider searches, and the per-repo comment sweeps:

```bash
~/.agents/skills/activity-harvest/scripts/github-harvest.sh "${window_start}" <open-key> <untouched: skip|include>
```

Emits a single JSON object:

- `merged` / `<open-key>` — your PRs, exactly as author-prs.sh below.
- `involved` — everything you touched (authored, commented, mentioned, assigned) updated since the window start.
- `reviewed` — PRs you reviewed (`involves:` does not cover reviews).
- `issue_comments` / `review_comments` — your comments across every surfaced repo, fully paginated (busy repos bury yours past page one).
- `reviews` — summary-only reviews on reviewed PRs that left no inline comments.
- `errors` — partial failures. **Never ignore this**: a non-empty list means a blind spot in the harvest; say so.

Reading rules:

- **Dedup by number + repo** — the same PR appears in several lists.
- **Personal repos are never material.** Queries are scoped `org:PostHog`; drop anything from `richardsolomou/*` (tro.gg, stream-setup) entirely — not even folded into another bullet.
- Comment/review bodies are truncated to 500 chars — fetch the full text with `gh` when a digest needs more.
- A heavy review/comment period is real material ("lots of pr reviews", "reviewed the X stack") even with no PRs of your own.
- The `updated:`/`merged:` qualifiers take the full ISO timestamp, so the window is sub-day precise.

**Your PRs only** — the wrapper's inner pass, usable standalone when the wider sweep isn't needed:

```bash
~/.agents/skills/activity-harvest/scripts/author-prs.sh "${window_start}" <open-key> <untouched: skip|include>
```

Emits `{"merged": [{number, title, repo, merged_at}, …], "<open-key>": [{number, title, repo, isDraft, commits: [headline, …]}, …]}`. `merged` is PRs you authored that merged at or after `window_start`. The open list carries each PR's in-window commit headlines. `untouched: skip` drops open PRs with no commits in the window. `include` keeps the full in-flight backlog for weekly focus candidates.

Use the scripts rather than reaching for `gh` directly — they bake in lessons that are easy to regress: `gh pr view --json commits` dies outside a clone (everything uses `gh api`); `gh search prs --merged` has stale date filtering; the per-PR commits endpoint pages oldest-first, so recent commits need pagination; the comment endpoints return all users' comments, so skipping `--paginate` silently drops yours on busy repos.

## Slack harvest

Much of the work never reaches GitHub — debugging in a thread, incident response, design decisions, unblocking others, cross-team coordination. Search your own messages with `mcp__slack__conversations_search_messages` using its **structured filters** (not Slack search-operator syntax):

- `filter_users_from: "U0A008HMS48"` — always the user ID; name/handle lookups don't reliably resolve in this tool.
- `filter_date_after: <date part of window_start>` — just `YYYY-MM-DD` (day-granular, inclusive). Omit any before/on filter so the window runs through now.
- `limit: 100`

Because the Slack filter is only day-granular, **post-filter the results to the exact window**: drop any message whose `Time` is at or before `window_start`.

Then make sense of what remains:

- **Group by channel.** A burst in one channel is usually one work stream — name it, don't enumerate messages. Pull surrounding context with `conversations_replies` when your messages alone don't tell the story.
- **Keep substance** — debugging, decisions, incidents, design discussion, support, unblocking others.
- **Drop noise** — reactions, GM/bye, social chatter, and your own standup/sync posts.
- **Cross-reference GitHub** — fold a thread and its PR into one bullet rather than double-counting.

If the search returns nothing useful, note that and lean on GitHub plus whatever the user adds.

## T3 Code harvest

Work driven through T3 Code that never reaches GitHub or Slack: investigations, live testing, debugging that ended without a PR. Threads live in T3 Code's local state database, read in place and read-only, so the app can stay open:

```bash
~/.agents/skills/activity-harvest/scripts/t3code-activity.sh "${window_start}" [window_end]
```

One tab-separated line per thread that received a prompt inside the window: the first in-window prompt instant, the project relative to `~/dev`, the branch, the thread title, any linked PR URLs, and the in-window prompts joined with ` | ` and truncated to 240 characters.

This is a **memory-jogger, not a primary source**: most threads wrap work that already surfaces in the GitHub or Slack passes, and a linked PR URL is the join key for folding them together. A thread earns material only when its outcome is invisible to the other passes. Ignore greetings, one-word follow-ups, and meta threads. A burst of near-identical prompts can be evidence of live testing. The personal-repo rule applies here too: drop threads whose project is outside `posthog/`.

Write the entry as plain markdown at `new_file_path`, ending with the marker the next run reads — do not omit it:

```text
<!-- generated-at: <now> -->
```

Then commit and push so the archive is backed up to the private `notes` repo. Stage only the generated entry, using its path relative to `~/dev/notes`:

```bash
git -C ~/dev/notes add -- <relative-entry-path>
git -C ~/dev/notes diff --cached --quiet || git -C ~/dev/notes commit -q -m "<prefix>: <header>"
git -C ~/dev/notes push -q
```

The `diff --cached --quiet` guard skips a no-op commit. If the push fails (offline, auth), report it but don't block — the file is already written locally.

## Notes

- The local files are the archive *and* the source of truth for the window: each entry's `generated-at:` marker is what the next run reads for `window_start`.
- The window is timestamp-precise on both passes: GitHub qualifiers take the full ISO instant directly; Slack is day-granular, so you post-filter by message `Time`.
