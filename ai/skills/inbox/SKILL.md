---
name: inbox
description: "Plan Richard's day from his calendar, the current sprint plan, GitHub work waiting on him, Slack mentions, DMs, and saved items, and the support queue when he is support hero. Use in the morning, or for 'what should I work on today?', 'plan my day', or 'what needs me?'. Also use to work the plan as a checklist: 'pick up the next item', 'take the Rebecca one', 'mark that done'."
---

# Inbox

Turn everything that might claim Richard's day into a short, ordered checklist that fits the time he actually has. Agent sessions then work it top-down (section 6). This is forward-looking; `standup` covers what already happened.

When the request is to pick up, take, finish, or mark an item, skip straight to section 6.

Load `activity-harvest` for the window and archive mechanics. Its identity constants apply here.

## 1. Window and previous plan

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh PostHog/today date previous
```

`window_start` bounds the "new since last time" searches: Slack mentions and DMs, and GitHub mentions. Everything else is current state. Read `prev_file_path` when present. Its unchecked items are the strongest candidates for today: call each one out as carried over rather than repeating it silently, and carry over the ⏸️ note on any item that was handed back. Re-check its open owed items too. They predate `window_start`, so the searches below will not find them again. Checked items are done, so drop them.

## 2. Gather

Issue these as parallel tool calls; only the support pass waits, on the sprint comment. Do not spawn agents only to collect.

- **Calendar.** Discover the available calendar tools before choosing a call. With the Google Calendar plugin, use `list_calendars` to resolve `primary`, `User interviews`, and `Holidays in Cyprus`, then `search_events` on each calendar from now to the end of today with explicit RFC3339 bounds and `timezone_str: "Asia/Nicosia"`, following every page. Use `read_event` for attendee lists and any missing descriptions or attachments; a shared calendar's `my_response_status` is not Richard's RSVP. With the standalone calendar MCP, use `get-current-time`, then `list-events` across those calendars with `timeZone: "Asia/Nicosia"` and `fields: ["description", "attachments"]`. Events on the shared `User interviews` calendar are teammates' interviews unless `richard.s@posthog.com` is an attendee; list those as optional joins that do not reduce capacity. Drop events he declined and all-day markers that do not block time; a Cyprus public holiday or an out-of-office event means he may be off. Convert every time to his timezone; events carry their organizer's offset. If no calendar tools are exposed, report that separately from a failed connection; a Slack digest is partial evidence and cannot establish availability, RSVP states, or the absence of meetings.
- **Sprint.** Run `~/.agents/skills/sprint-planning/scripts/detect-sprint.sh`, then `~/.agents/skills/sprint-planning/scripts/fetch-previous-comment.sh <current_number>` for the team's current comment. Extract Richard's high-priority and side-quest plan items with their links, the support hero, who is off, and the working days left in the sprint.
- **GitHub.** `~/.agents/skills/inbox/scripts/github-queue.sh "${window_start}"` returns direct review requests, the team's review queue, Richard's open PRs with review decision, mergeability, and check state, his assigned issues, and new mentions. A non-empty `errors` list is a blind spot; say so.
- **Slack mentions and DMs.** `conversations_search_messages` with `search_query: "<@U0A008HMS48>"`, then again with `search_query: "is:dm"`, each with `filter_date_after` set to `slack_after` and `limit: 100`, following the cursor. Post-filter to `[window_start, now)`. Drop notifier messages (GitHub, proke, Google Calendar, and similar apps, including `#github` PR unfurls that list him as a reviewer); the GitHub and calendar passes are authoritative for those.
- **Support.** When the sprint comment names Richard support hero, list the team's tickets through the PostHog MCP in project 2: note the active project from `project-get`, `switch-project` to `2`, then `conversations-tickets-list` with `status: "new,open,pending,on_hold"`, `assignee: "role:019eb60b-096c-0000-78a1-5fd9f7d15511"`, and `date_from: "all"` so old tickets are not filtered out, paging with `offset` until exhausted, and switch back afterwards. Read the thread of any ticket that is breached, at risk, or new with `conversations-tickets-messages-retrieve`. If project 2 is unreachable, say so, link the [team queue](https://us.posthog.com/project/2/support/tickets?status=%5B%22new%22%2C%22open%22%2C%22pending%22%2C%22on_hold%22%5D&assignee=%5B%22role%3A019eb60b-096c-0000-78a1-5fd9f7d15511%22%5D), and fall back to the SLA pings in `#support-context-and-mcp` since `window_start`, using `slack_after` as the search's `filter_date_after`.
- **Slack saved items.** `saved_list` with `filter: "saved"` and a limit high enough to exhaust it, plus the newest `*-index.md` under `~/dev/notes/PostHog/todos`.
- **Yesterday.** The newest entry under `~/dev/notes/PostHog/standup`, for work described as started or continuing.

## 3. Work out what is actually waiting

Source items are candidates; establish current state before ranking them.

- **Mentions and DMs.** Read each distinct thread with `conversations_replies`. It is waiting on Richard only when the latest substantive message is not his and it asks him something, hands him something, or is blocked on him. Answered threads, FYIs, and cc's drop out.
- **Saved items.** Reuse the to-do index's rank and recommended action for items it already covers, refreshing status only for the top few. Read items saved after the index was written. When those are numerous or the index is more than a few days old, say the index is stale rather than reproducing its deep triage.
- **Richard's PRs.** Changes requested, failing checks, or conflicts are his move; approved and green is a merge; awaiting review may need a nudge. A PR untouched for weeks is a decision to finish or close, not a daily task.
- **Sprint items.** Match every Richard high-priority and side-quest plan item to its evidence: an open PR, a recent thread, yesterday's standup. Note which have momentum and which have not started. Account for every item in the output: actionable work goes in Focus or Owed, deferred work goes in Not today with its link and reason, and completed work is acknowledged briefly with its evidence. Include teammates' time off when it affects reviews, dependencies, or handoffs.
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

- [ ] 💬 [<who>: <what they need>](<thread>): <why it is his move> · [note](<to-do note>)

## 🎯 Focus

- [ ] 🛠️ [<sprint item>](<plan link>): <next step> · [#123](<PR>)

## 👀 Team reviews

- [ ] ⏱️ <timebox>: [#123](<PR>) <why first>, [#456](<PR>)

## 💤 Not today

- 🧹 <item> · [link](<source>)

⚠️ <failed, truncated, or unreachable sources>

<!-- generated-at: <now> -->
```

Owed, Focus, and Team reviews items are tasks (`- [ ]`). Their order from top to bottom is the priority order agents follow, so put each item in its final rank. Calendar and Not today items stay plain bullets. Meeting prep that needs work is an Owed task, and the Calendar line only points to it. Make each task one self-contained unit of work, so that an agent can pick it up with only this line and its links. Split an item that has two independent next steps.

After the checkbox, lead every item with one action emoji so the next move reads at a glance: 💬 reply, 👀 review, 🛠️ build, 🔍 investigate, ✅ verify, 🔀 merge or fix his PR, 🧹 housekeeping, 🙋 optional. Use those and the section emojis only; no decorative extras.

Link every item, and make the link text name its destination: the person and ask for a thread, `#123` for a PR or issue, `note` for a to-do note. Put the main link on the item's subject and secondary links after a `·`. Use absolute paths for notes files so they open from the terminal too, and check each one exists; the index can link notes that were never written. Omit empty sections and the ⚠️ line when every source succeeded. Do not draft replies; point to the to-do note when one exists.

GitHub and the Slack mention and DM searches are bounded by `window_start`, so a failure or truncation there would drop requests for good once `generated-at` advances: show the plan marked incomplete, name the pass to rerun, and do not write it. Every other source is current state that the next run reads again; its failures go on the ⚠️ line only.

For a targeted correction rather than a full rerun, preserve `generated-at` so unqueried GitHub and Slack activity remains in the next run's window.

Otherwise write the plan to `new_file_path`. A same-day rerun replaces it but keeps the progress already made. Match each new task to an old one by its main link. Keep the checkbox and status suffix of a matched task, and keep checked tasks that no longer match, in their sections. Commit and push per the harvest skill's archive procedure with prefix `today:`. Planning posts nothing and changes nothing in Slack, GitHub, or the calendar.

## 6. Work the list

Each agent session works one task. The plan file at `~/dev/notes/PostHog/today/<today>.md` is the shared board. Git is the lock, because several sessions can pick up items at the same time.

A task's state is its checkbox plus at most one status suffix after a ` · `:

| State | Line |
| --- | --- |
| Open | `- [ ] 💬 [Rebecca: …](…): …` |
| In progress | `- [ ] … · 🚧 09:40 <session>` |
| Needs Richard | `- [ ] … · ⏸️ <what he must do> · [draft](<path>)` |
| Done | `- [x] … · ✅ 10:15 <outcome link>` |

`<session>` names the session: its T3 thread link when there is one, otherwise its branch or worktree. Use his local time. Replace the suffix when the state changes, and do not stack suffixes.

**Claim.** Run `git -C ~/dev/notes pull -q --rebase`, then choose the task. "Next" means the first task with no suffix, from top to bottom. Never pick it from Not today. A named task ("the Rebecca one") must be open or ⏸️. If it is 🚧, say who has it and stop. Add the 🚧 suffix, then commit `today: claim <short name>` and push. A rejected push means another session wrote first. Pull, check the task again, and claim the next open task if this one is taken. If no file exists for today, or no task is open, say so. Do not plan the day as a side effect.

**Work.** Treat the line and its links as the brief, and check the current state before acting, because the plan can be hours old. Follow the user's normal rules: nothing is posted, sent, commented, merged, or enqueued without his approval in this session. Thus most 💬 and 👀 tasks end with a draft. Write it with `tone` into `~/dev/notes/PostHog/todos/` and link it.

**Finish.** Pull again, then set the outcome on the claimed line only:

- Done (`- [x]`, ✅): the next step in the line happened, and you can link the evidence (the PR, the sent reply, the merged change).
- Needs Richard (⏸️): only he can do the rest, for example send, approve, decide, or log in. Say exactly what, and link the draft. The next "pick up next" skips the task, and he checks it or tells a session that it is done.
- Back to open: you stopped without progress. Remove the suffix and give the reason in your reply.

Commit `today: <done|hand back|release> <short name>` and push, then report the outcome and the next open task. Leave every other line as it is, and do not re-rank the list.
