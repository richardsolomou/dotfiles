---
name: rs-activity-harvest
description: "Shared machinery for the cadence skills (rs-standup, rs-ai-gateway-sync, rs-sprint-planning, rs-quarterly-planning): the activity window, the GitHub and Slack harvest queries, and the archive-to-notes step. Load when one of those skills points here; not useful standalone."
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
~/.claude/skills/rs-activity-harvest/scripts/activity-dates.sh <notes-subdir> <header-style: day|week> <same-day: reuse|previous>
```

Returns tab-separated: `<window_start>\t<now>\t<new_file_path>\t<header>\t<prev_file_path>`

- `window_start` — ISO 8601 UTC instant of the previous entry; feed it to every GitHub and Slack query.
- `now` — ISO 8601 UTC instant of this run; stamp it into the new entry's `generated-at:` marker.
- `new_file_path` — where to write this entry (`YYYY-MM-DD.md` under `~/dev/notes/<notes-subdir>/`).
- `header` — human header ("17 June" for `day`, "Week of 17 June" for `week`).
- `prev_file_path` — the most recent existing entry, or empty.

The `same-day` argument sets re-run semantics: `reuse` treats today's own entry as the previous one (the window covers only the delta since the morning run — rs-standup, which appends); `previous` skips today's file so the window stretches back to the real previous entry (rs-ai-gateway-sync, which regenerates in full). This divergence is deliberate — a standup accumulates through the day, a sync is one weekly artifact.

## GitHub harvest

**Your PRs — merged and in-flight:**

```bash
~/.claude/skills/rs-activity-harvest/scripts/author-prs.sh "${window_start}" <open-key> <untouched: skip|include>
```

Emits `{"merged": [{number, title, repo, merged_at}, …], "<open-key>": [{number, title, repo, isDraft, commits: [headline, …]}, …]}`. `merged` is PRs you authored that merged at/after `window_start`; the open list carries each PR's in-window commit headlines. `untouched: skip` drops open PRs with no commits in the window (rs-standup); `include` keeps them all — the in-flight backlog (rs-ai-gateway-sync's This-week candidates).

Use the script rather than reaching for `gh` directly — it bakes in lessons that are easy to regress: `gh pr view --json commits` dies outside a clone (the script uses `gh api` throughout); `gh search prs --merged` has stale date filtering; the per-PR commits endpoint pages oldest-first, so recent commits need pagination.

**Everything else you touched** (authored, commented, mentioned, assigned — updated since the window start):

```bash
gh api search/issues --method GET -f q="involves:richardsolomou updated:>=${window_start} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url, is_pr: (.pull_request != null)}'
```

**PRs you reviewed** (`involves:` does not cover reviews):

```bash
gh api search/issues --method GET -f q="reviewed-by:richardsolomou is:pr updated:>=${window_start} org:PostHog" --jq '.items[] | {number, title, state, url: .html_url, repo: .repository_url}'
```

**Personal repos are never material.** Every query stays scoped to `org:PostHog`; drop anything from `richardsolomou/*` (tro.gg, stream-setup) entirely — not even folded into another bullet.

**Issue comments and inline review comments** — `involves:` misses substantive design-thread comments on issues that aren't otherwise "updated", and no search qualifier covers inline PR review comments at all. Query both directly for **every repo the other queries surfaced**, not just one:

```bash
gh api "repos/PostHog/<repo>/issues/comments?since=${window_start}&per_page=100" --paginate --jq '.[] | select(.user.login=="richardsolomou") | {issue: (.issue_url | split("/") | last), created_at, body}'
gh api "repos/PostHog/<repo>/pulls/comments?since=${window_start}&per_page=100" --paginate --jq '.[] | select(.user.login=="richardsolomou") | {pr: (.pull_request_url | split("/") | last), created_at, body}'
```

`--paginate` is load-bearing: these endpoints return **all users'** comments, and on a busy repo (PostHog/posthog) more than a page arrives within even a one-day window, silently dropping yours. Reviews with only a summary or only inline threads live on yet another endpoint — for any PR the reviewed-by search surfaced with no comments here, check `repos/PostHog/<repo>/pulls/<n>/reviews` before concluding the review left no trace.

The `updated:>=`/`merged:>=` qualifiers accept the full ISO timestamp, so they respect a sub-day window start. **Dedup** across all queries by `number` + repo — the same PR appears several times. A heavy review/comment period is real material ("lots of pr reviews", "reviewed the X stack") even with no PRs of your own.

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

## Archive to notes

Write the entry as plain markdown at `new_file_path`, ending with the marker the next run reads — do not omit it:

```text
<!-- generated-at: <now> -->
```

Then commit and push so the archive is backed up to the private `notes` repo (`git -C` avoids depending on the working directory):

```bash
git -C ~/dev/notes add -A
git -C ~/dev/notes diff --cached --quiet || git -C ~/dev/notes commit -q -m "<prefix>: <header>"
git -C ~/dev/notes push -q
```

The `diff --cached --quiet` guard skips a no-op commit. If the push fails (offline, auth), report it but don't block — the file is already written locally.

## Notes

- The local files are the archive *and* the source of truth for the window: each entry's `generated-at:` marker is what the next run reads for `window_start`.
- The window is timestamp-precise on both passes: GitHub qualifiers take the full ISO instant directly; Slack is day-granular, so you post-filter by message `Time`.
