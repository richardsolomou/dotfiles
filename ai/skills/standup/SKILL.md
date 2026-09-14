---
name: standup
description: "Generate a daily standup or weekly AI Gateway sync from GitHub, Slack, and relevant PostHog Code activity. Use for standup notes, daily updates, 'what did I do yesterday?', or the Monday AI Gateway weekly sync."
argument-hint: "[weekly]"
---

# Standup and Weekly Sync

Generate a terse activity update in the user's voice and archive it in the notes repo. Default to a daily retrospective. Use weekly mode when the user says `weekly`, `AI Gateway sync`, or `Monday sync`.

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
~/.agents/skills/activity-harvest/scripts/activity-dates.sh PostHog/standup day reuse
```

For weekly mode, run:

```bash
~/.agents/skills/activity-harvest/scripts/activity-dates.sh PostHog/ai-gateway-sync week previous
```

Store `window_start`, `now`, `new_file_path`, `header`, and `prev_file_path` per the harvest skill. Daily same-day reruns append only new activity. Weekly same-day reruns rebuild the same weekly artifact from the previous real sync.

### 2. Read the previous entry

Read `prev_file_path` when present. Use prior "started" or "continuing" items to identify work that may still be active. In weekly mode, the prior `This week` section is the strongest starting point for unfinished work.

### 3. Harvest activity

Run independent source reads concurrently with parallel tool calls. Do not spawn agents only to collect activity.

Daily mode uses:

- GitHub: `github-harvest.sh "${window_start}" active skip`.
- Slack: follow the harvest skill's Slack query and exact timestamp filter.
- PostHog Code: `posthog-code-activity.sh "${window_start}" "${now}"`.

Weekly mode uses:

- GitHub: `github-harvest.sh "${window_start}" open include`. Merged and recently changed PRs inform `Last week`. All open PRs are candidates for `This week`.
- Slack: follow the harvest skill's Slack query and exact timestamp filter.

Group related source items into one work stream. Fold a Slack discussion and its PR into one item. Drop greetings, reactions, automated noise, and activity from personal repositories.

### 4. Compose

Compose the selected mode using the style rules above. The activity sources help find work. They do not define the output structure.

If activity is thin, say so because meetings or offline work may be missing. In weekly mode, finish with one direct question about additions or removals from the focus list.

### 5. Archive

Daily output shape:

```text
# <header>

- <outcome>
- <outcome>

<!-- generated-at: <now> -->
```

Write it to `new_file_path` with commit prefix `standup:`. On a same-day rerun, append only new bullets and update the timestamp marker.

Weekly output shape:

```text
# <header>

## Last week

- <outcome>

## This week

- <focus>

<!-- generated-at: <now> -->
```

Write it to `new_file_path` with commit prefix `ai-gateway-sync:`. On a same-day rerun, regenerate both sections but preserve focus items the user added manually.

Use the harvest skill's archive procedure to commit and push the notes repository. A failed notes push does not invalidate the local file.

### 6. Report

Show the generated entry and its path. In weekly mode, also ask what to add or remove from `This week`.
