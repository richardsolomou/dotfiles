---
name: standup
description: "Generate a daily standup or weekly Context & MCP sync from GitHub, Slack, and T3 Code activity. Use for standup notes, daily updates, 'what did I do yesterday?', or the Monday Context & MCP weekly sync."
argument-hint: "[weekly]"
---

# Standup and Weekly Sync

Generate a terse activity update in the user's voice and archive it in the notes repo. Default to a daily retrospective. Use weekly mode when the user says `weekly`, `Context & MCP sync`, or `Monday sync`.

Load `activity-harvest` for activity windows, source queries, and archive mechanics. Load `tone` with `register: slack-status` before composing.

## Modes

### Daily

Write retrospective bullets about outcomes since the previous standup. Describe in-flight work as "started" or "continuing". Do not add future plans.

- Write one work stream per bullet, using one or two short sentences.
- Lead with what changed or what was learned, not PR titles or counts.
- Include reviews, incidents, debugging, support, design, and meetings when they mattered.
- Use lowercase, plain language, and no links.

### Weekly

Write two short sections: `Last week` and `This week`.

- `Last week` contains completed and in-flight outcomes from the activity window.
- `This week` contains focus candidates from open PRs and unfinished work. Treat them as a draft because tools cannot see all planned work.
- Use brief fragments, one work stream per line, lowercase, and no trailing punctuation.
- Do not count PRs or copy conventional commit titles.
- Ask the user what to add or remove from `This week` before treating it as final.

## Workflow

### 1. Get the activity window

For daily mode, run:

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh PostHog/standup date reuse
```

For weekly mode, run:

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh PostHog/context-and-mcp-sync week previous
```

Store `window_start`, `now`, `new_file_path`, `header`, `prev_file_path`, and `slack_after` per the harvest skill. In daily mode, split the window into one entry per local day with the harvest skill's `activity-days.sh "${window_start}" "${now}" "$(dirname "${new_file_path}")"`. Daily mode can run at any time: missed days get their own entries, today's work so far goes in today's entry, and a rerun covers only the activity since the previous run. Weekly same-day reruns rebuild the same weekly artifact from the previous real sync.

### 2. Read the previous entry

Read `prev_file_path` when present. Use prior "started" or "continuing" items to identify work that may still be active. In weekly mode, the prior `This week` section is the strongest starting point for unfinished work.

### 3. Harvest activity

Do not spawn agents only to collect activity.

Daily mode uses, for each day's `day_start` and `day_end`:

- GitHub: `github-harvest.sh "${day_start}" "${day_end}" active skip`.
- Slack: run the harvest skill's Slack query once for the whole window, then assign each message to the day whose sub-window contains its `Time`.
- T3 Code: `t3code-activity.sh "${day_start}" "${day_end}"`.

Run every day's passes concurrently. Credit each work stream to the day its evidence falls in. A PR worked on across days can appear in more than one entry, with verbs matched to that day's evidence.

Weekly mode uses:

- GitHub: `github-harvest.sh "${window_start}" "${now}" open include`. Merged and recently changed PRs inform `Last week`. All open PRs are candidates for `This week`.
- Slack: follow the harvest skill's Slack query and exact timestamp filter.

Group related source items into one work stream. Fold a Slack discussion and its PR into one item. Drop greetings, reactions, automated noise, and activity from personal repositories. Reconcile prior focus items against their live merged, closed, draft, or open state before carrying them forward.

### 4. Compose

Compose the selected mode using the style rules above. The activity sources help find work. They do not define the output structure. Match verbs to evidence: use `shipped` or `fixed` only for merged or explicit completion evidence; use `started` or `continuing` for in-window open work; use `investigated` or `planning` for T3 prompts and intent-only Slack messages unless another source proves the outcome.

If activity is thin, say so because meetings or offline work may be missing. If a required source failed or truncated, present the incomplete draft and do not archive until the source succeeds or the user explicitly accepts the gap. In weekly mode, finish with one direct question about additions or removals from the focus list.

### 5. Archive

Daily output shape:

```text
# <header>

- <outcome>
- <outcome>

<!-- generated-at: <now> -->
```

Write each day's entry to its `file_path` with that day's `header`, stamping `generated-at:` with its `day_end`. Skip days with no material activity. The latest written entry takes `now` as its marker, so the next window starts after everything harvested. When a day's file already exists, append only new bullets and update its marker. Commit all written entries together with commit prefix `standup:`.

Weekly output shape:

```text
# <header>

## Last week

- <outcome>

## This week

- <focus>

<!-- generated-at: <now> -->
```

Present the weekly draft and wait for the user's additions or removals. Then write the confirmed version to `new_file_path` with commit prefix `context-and-mcp-sync:`. On a same-day rerun, regenerate both sections but preserve focus items the user added manually.

Use the harvest skill's archive procedure to commit and push the notes repository. A failed notes push does not invalidate the local file.

### 6. Report

Show each generated entry and its path. In weekly mode, also ask what to add or remove from `This week`.
