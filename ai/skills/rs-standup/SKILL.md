---
name: rs-standup
description: "Generate a daily standup entry from your PostHog GitHub and Slack activity since your previous standup, composed as terse bullets in your house style and archived locally. Use when the user asks to write, generate, or prep their standup / daily update / standup notes, or asks 'what did I do yesterday?' in a standup context."
---

# Standup Notes Generator

Generate a daily standup entry — terse bullets of what you did, ready to post under your name wherever your team keeps standups.

Load the `rs-activity-harvest` skill first — it owns the window mechanics, the GitHub and Slack harvest queries, and the archive step this workflow references.

## Purpose

Standups are retrospective — only what you did in the window, never what you plan to do next. In-flight work is described in the past tense as "started …" or "continuing …", not as a future intention.

## Style

Diction comes from `rs-tone` register `slack-status` (terse, lowercase, no AI tells, concrete over abstract). On top of that, the standup-specific shape — these override the register where they differ:

- **Write it like you'd say it out loud to a teammate** — what you actually got done and why it matters, **not** a list of the PRs you merged. The GitHub/Slack passes are how you *find* the work; they are not the shape of the output. Reading back as a changelog ("landed X (4 PRs): a, b, c") is the failure mode to avoid.
- **Lead with the outcome, in plain language.** Say what changed for the world, not which artifacts you touched. "keys no longer get revoked while in use, and session admission is O(1) instead of summing every in-flight hold" beats "landed the credential last-used drain (4 PRs)". The reader should learn what's true now that wasn't before.
- **One work stream, one bullet — told as a sentence or two**, not a header with a bulleted parts list. Fold the concrete pieces into the prose. Reach for sub-bullets only when a stream genuinely has distinct strands worth separating.
- **Full thoughts are fine** — a bullet can be a sentence. Trailing punctuation is optional; be consistent within an entry. **No links** (overrides the register's `description (link)` bullet shape).
- **Drop the PR counting and the conventional-commit titles.** "(5 PRs)" and "feat(gateway): …" are changelog tells. Describe the thing, not the paperwork.
- **Flag in-flight work** in the past tense — "started …", "continuing …". Never a future intention.
- **Include non-code work** — reviews, incidents, debugging, support, decisions, design discussions, meetings, calls, streams, holidays. Meetings, calls, and holidays won't show up in the harvest, so ask or let the user add them.

Example of the target voice:

```text
- shipped the gateway credential plumbing that was in flight — keys no longer get revoked while in use, and session admission is O(1) instead of summing every in-flight hold
- figured out how to stop the gateway double-billing AIO — sorted the provenance design with ingestion so a customer can't forge their way to free usage, landed on emitter-signed events that capture verifies inline
- spent most of the day on observability — RED metrics across the hot path, admission, upstreams, and billing, plus OTel tracing and alerts. built it overnight with an autopilot loop, now writing the invariants down by hand
- unbroke master
- lots of pr reviews — worked through the gateway auth stack and unblocked the ingestion provenance PRs
```

## Your Task

### Step 1: Get the Window

```bash
~/.claude/skills/rs-activity-harvest/scripts/activity-dates.sh PostHog/standup day reuse
```

Store the five fields per the harvest skill's *Dates script* section. The file and header are dated the business day the standup is **for** — an evening run is for today, a morning run for the previous business day — not necessarily the day you're generating on (see the harvest skill's *Dates script* section). `reuse` gives the standup its re-run semantics: when the entry for that date already exists, the window covers only the delta since the earlier run.

### Step 2: Read the Previous Standup

If `prev_file_path` is non-empty, read it. Items marked "started" or "continuing" there may still be in flight and worth carrying as "continuing …" if GitHub shows more activity on them. (On a re-run for the same entry date `prev_file_path` is that same entry — that's fine; it tells you what you already reported earlier, which is exactly what to avoid duplicating.)

### Step 3: Harvest Activity in Parallel

Run all three passes concurrently per the harvest skill's *Run the passes concurrently* section — GitHub, Slack, and PostHog Code, one subagent each spawned in a single message (parallel tool calls where subagents aren't available), each returning a digest per that section's contract. Standup-specific notes per pass:

- **GitHub** — `github-harvest.sh "${window_start}" active skip`. Any activity counts — reviewing others' PRs, commenting, opening issues, triaging — not just your own PRs. `merged` is the "landed" signal; `active` PRs' commit headlines tell you what was done — "started …" (new this window) or "continuing …" (carried from a previous entry).
- **Slack** — the harvest skill's *Slack harvest* section as written.
- **PostHog Code** — the harvest skill's *PostHog Code harvest* section as written — a memory-jogger for investigation, testing, and triage work invisible to the other passes.

Cast a wide net; judging what's worth a bullet happens at compose time.

### Step 4: Compose the Entry

Write the entry per the Style section, merging the three digests into one picture of the window. A stack of related PRs becomes one bullet describing the thing they add; fold a Slack thread and its PR into a single bullet. If it reads back like a changelog, rewrite it as something you'd say out loud.

If activity looks thin across the sources, note that to the user — they likely have meetings, calls, or offline work to add.

### Step 5: Write the Archive File

Write the entry at `new_file_path` per the harvest skill's *Archive to notes* section, commit prefix `standup:`. Example:

```text
# 4 June

- posthog api keys can now auth straight through the gateway (phx_/pha_), no separate credential to mint
- spend is attributed per-product now via the X-PostHog-Product header
- started routing per-product gateways under /g/{slug}
- phcode: rich text now pastes as markdown in the composer

<!-- generated-at: 2026-06-04T17:30:00Z -->
```

**Re-run for the same entry** (`new_file_path` already exists): append the new bullets under the existing ones rather than overwriting the earlier run's work, and update the `generated-at:` marker to the new `now`.

### Step 6: Report to User

Display:

1. The generated entry (plain text for review)
2. The file path for easy access
