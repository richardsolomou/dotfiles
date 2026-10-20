---
name: today
description: "Plan Richard's day from his calendar, the current sprint plan, GitHub work waiting on him, Slack mentions, DMs, and saved items, and the support queue when he is support hero. Use in the morning, or for 'what should I work on today?', 'plan my day', or 'what needs me?'."
---

# Today

Turn everything that might claim Richard's day into a short, ordered plan that fits the time he actually has. This is forward-looking; `standup` covers what already happened.

Load `activity-harvest` for the window and archive mechanics. Its identity constants apply here.

## 1. Window and previous plan

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh PostHog/today date previous
```

`window_start` bounds the "new since last time" searches: Slack mentions and DMs, and GitHub mentions. Everything else is current state. Read `prev_file_path` when present: its focus items are the strongest candidates for today, and anything planned there but untouched since should be called out as carried over rather than silently repeated. Re-check its owed items too: they predate `window_start`, so the searches below will not find them again.

## 2. Gather

Issue these as parallel tool calls; only the support pass waits, on the sprint comment. Do not spawn agents only to collect.

- **Calendar.** `get-current-time`, then `list-events` across `primary`, `User interviews`, and `Holidays in Cyprus` from now to the end of today, with `timeZone` set to his and `fields: ["description", "attachments"]`. Events on the shared `User interviews` calendar are teammates' interviews unless `richard.s@posthog.com` is an attendee; list those as optional joins that do not reduce capacity. Drop events he declined and all-day markers that do not block time; a Cyprus public holiday or an out-of-office event means he may be off. Convert every time to his timezone; events carry their organizer's offset.
- **Sprint.** Run `~/.agents/skills/sprint-planning/scripts/detect-sprint.sh`, then `~/.agents/skills/sprint-planning/scripts/fetch-previous-comment.sh <current_number>` for the team's current comment. Extract Richard's high-priority and side-quest plan items with their links, the support hero, who is off, and the working days left in the sprint.
- **GitHub.** `~/.agents/skills/today/scripts/github-queue.sh "${window_start}"` returns direct review requests, the team's review queue, Richard's open PRs with review decision, mergeability, and check state, his assigned issues, and new mentions. A non-empty `errors` list is a blind spot; say so.
- **Slack mentions and DMs.** `conversations_search_messages` with `search_query: "<@U0A008HMS48>"`, then again with `search_query: "is:dm"`, each with `filter_date_after` set to the date part of `window_start` and `limit: 100`, following the cursor. Post-filter to `[window_start, now)`. Drop notifier messages (GitHub, proke, Google Calendar, and similar apps, including `#github` PR unfurls that list him as a reviewer); the GitHub and calendar passes are authoritative for those.
- **Support.** When the sprint comment names Richard support hero, list the team's tickets through the PostHog MCP in project 2: note the active project from `project-get`, `switch-project` to `2`, then `conversations-tickets-list` with `status: "new,open,pending,on_hold"`, `assignee: "role:019eb60b-096c-0000-78a1-5fd9f7d15511"`, and `date_from: "all"` so old tickets are not filtered out, paging with `offset` until exhausted, and switch back afterwards. Read the thread of any ticket that is breached, at risk, or new with `conversations-tickets-messages-retrieve`. If project 2 is unreachable, say so, link the [team queue](https://us.posthog.com/project/2/support/tickets?status=%5B%22new%22%2C%22open%22%2C%22pending%22%2C%22on_hold%22%5D&assignee=%5B%22role%3A019eb60b-096c-0000-78a1-5fd9f7d15511%22%5D), and fall back to the SLA pings in `#support-context-and-mcp` since the date part of `window_start`.
- **Slack saved items.** `saved_list` with `filter: "saved"` and a limit high enough to exhaust it, plus the newest `*-index.md` under `~/dev/notes/PostHog/todos`.
- **Yesterday.** The newest entry under `~/dev/notes/PostHog/standup`, for work described as started or continuing.

## 3. Work out what is actually waiting

Source items are candidates; establish current state before ranking them.

- **Mentions and DMs.** Read each distinct thread with `conversations_replies`. It is waiting on Richard only when the latest substantive message is not his and it asks him something, hands him something, or is blocked on him. Answered threads, FYIs, and cc's drop out.
- **Saved items.** Reuse the to-do index's rank and recommended action for items it already covers, refreshing status only for the top few. Read items saved after the index was written. When those are numerous or the index is more than a few days old, say the index is stale rather than reproducing its deep triage.
- **Richard's PRs.** Changes requested, failing checks, or conflicts are his move; approved and green is a merge; awaiting review may need a nudge. A PR untouched for weeks is a decision to finish or close, not a daily task.
- **Sprint items.** Match each plan item to its evidence: an open PR, a recent thread, yesterday's standup. Note which have momentum and which have not started.
- **Meetings.** Flag any that need preparation: he is presenting or interviewing, the description asks for pre-reading, or a doc is attached.

Keep evidence separate from interpretation. A Slack promise is not a shipped fix, and a merged PR is not a confirmed recovery.

## 4. Plan the day

Measure capacity first: list meetings, then the free blocks of an hour or more between now and the end of his working day. Plan only what fits; say plainly when the day is mostly meetings.

Rank in this order, then explain any ordering that would surprise him:

1. **Owed today.** People blocked on him, direct review requests, commitments with a date, meeting prep, and his PRs that need only his move. If he is support hero this sprint, the support queue belongs here.
2. **Focus.** One to three sprint plan items for the free blocks, each with the concrete next step rather than the item's title. Prefer items with momentum, items that unblock teammates, and items at risk given the days left and planned time off. Carry over yesterday's focus unless something displaced it.
3. **Team reviews.** A timeboxed slot for the oldest team review requests, naming the few worth taking first.
4. **Not today.** Lower-priority side quests, stale assigned issues, and the saved-items tail, in one line each, so he can see they were considered.

If the calendar or sprint comment shows him off today, say so and stop.

## 5. Output

```text
# ☀️ Today, <header>

<one line on the shape of the day: meeting count, focus hours, anything unusual>

📋 [Sprint plan](<sprint comment URL>) · 📅 [Calendar](https://calendar.google.com/calendar/u/0/r/day/<YYYY>/<M>/<D>) · 📥 [Slack to-dos](<to-do index path>)

## 📅 Calendar

- 🗓️ 10:00–10:30 [<meeting>](<event link>) (prep: <what>)
- 🙋 Optional: [<teammate's interview>](<event link>) at 16:00

## 🔥 Owed today

- 💬 [<who>: <what they need>](<thread>): <why it is his move> · [note](<to-do note>)

## 🎯 Focus

- 🛠️ [<sprint item>](<plan link>): <next step> · [#123](<PR>)

## 👀 Team reviews

- ⏱️ <timebox>: [#123](<PR>) <why first>, [#456](<PR>)

## 💤 Not today

- 🧹 <item> · [link](<source>)

⚠️ <failed, truncated, or unreachable sources>

<!-- generated-at: <now> -->
```

Lead every item with one action emoji so the next move reads at a glance: 💬 reply, 👀 review, 🛠️ build, 🔍 investigate, ✅ verify, 🔀 merge or fix his PR, 🧹 housekeeping, 🙋 optional. Use those and the section emojis only; no decorative extras.

Link every item, and make the link text name its destination: the person and ask for a thread, `#123` for a PR or issue, `note` for a to-do note. Put the main link on the item's subject and secondary links after a `·`. Use absolute paths for notes files so they open from the terminal too, and check each one exists; the index can link notes that were never written. Omit empty sections and the ⚠️ line when every source succeeded. Do not draft replies; point to the to-do note when one exists.

GitHub and the Slack mention and DM searches are bounded by `window_start`, so a failure or truncation there would drop requests for good once `generated-at` advances: show the plan marked incomplete, name the pass to rerun, and do not write it. Every other source is current state that the next run reads again; its failures go on the ⚠️ line only.

Otherwise write the plan to `new_file_path`; a same-day rerun overwrites it. Commit and push per the harvest skill's archive procedure with prefix `today:`. Nothing is posted, marked done, or changed in Slack, GitHub, or the calendar.
