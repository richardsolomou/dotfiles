---
name: rs-stream-recap
description: "Turn a finished build-in-public stream VOD into a frozen per-stream recap note (and optionally the X + LinkedIn recap posts). Pulls the YouTube spoken-word transcript and live chat, mines them for what shipped, what changed vs the plan, bugs hit, and chat ideas, then writes the note in ~/dev/rs/notes/<project>/streams/ deferring to the project repo's docs for current truth. Use when the user asks to recap/write up a stream, prep the next stream's plan, or draft post-stream social posts."
---

# Stream Recap & Plan

Turn a finished stream VOD into a **frozen, one-folder-per-stream record** — the VOD, the transcript + chat, a recap (what shipped, what changed vs the plan, bugs hit, ideas from chat, the next-stream plan), and the stream's social posts — all in a single `streams/<stream>/` folder.

This is for Richard's build-in-public streams (currently **tro.gg**). It is retrospective: it records what happened, in the past tense, as of when you run it.

## The two-layer model (read this first — it's the whole point)

Richard's notes are **frozen-in-time thinking**, not living docs. The **living source of truth is the project repo's own docs** (for tro.gg: `~/dev/tro.gg/docs/` — `gdd.md`, `analytics.md`, etc.). The recap note must **defer to the repo** for anything that is "currently true," and only *record* what the stream observed and decided.

Consequences you must respect:

- **Never write the recap as if it were the current spec.** Architecture, schema, milestones — those live in the repo. The note captures *the snapshot and the deltas*, then points at the repo.
- **A stream almost always diverges from the pre-stream plan.** The most valuable section is usually "what changed vs the plan" — capture it precisely, but frame it as "this changed; the repo docs are now authoritative," not "update the plan."
- **The note is frozen.** Don't promise to keep it in sync. Future runs write new per-stream folders; they don't edit old ones.

## Where things live

- **Notes repo:** `~/dev/rs/notes/` (private, git-backed). Per-project folder, e.g. `~/dev/rs/notes/tro.gg/`.
  - `README.md` — **the single home for the workspace's conventions** (frozen-truth rule, source-of-truth = repo `docs/`, folder layout, cadence summary) and the **stream index table**. Individual files do NOT repeat these conventions — they carry only their own facts. Read it first, and add a row to its index when you write a new note.
  - `initial-plan.md` — the frozen pre-stream thinking (defers to the repo too).
  - `streams/YYYY-MM-DD-stream-N-<slug>/` — **one folder per stream**, holding everything for it:
    - `stream.md` — the entry note: the VOD (embedded + linked) and pointers to the rest.
    - `recap.md` — **the frozen recap.** The main thing you write (step 3).
    - `posts.md` — the stream's social posts (step 4).
    - `transcript.txt`, `chat.txt` — the fetched spoken-word transcript + live chat the recap is built from (step 1 writes these here; they're committed with the note).
  - `social-playbook.md` — the one **living** doc: cadence, voice, and templates for the posts.
- **Project repo (source of truth):** `~/dev/tro.gg/` with `docs/`. Read it to know what's *currently* true; cite it in the note.
- Read the most recent stream's `recap.md` before writing so the new note picks up where the last left off (open questions, the previous "next stream" plan).

## Workflow

### 1. Get the transcript + chat

Create the stream's folder, fetch the VOD, then copy the transcript + chat into it (they're committed with the note, not throwaway):

```bash
dir=~/dev/rs/notes/<project>/streams/YYYY-MM-DD-stream-N-<slug>
mkdir -p "$dir"
scripts/fetch-captions.sh "<youtube-url>"        # prints an outdir in its === summary ===
cp <outdir>/transcript.txt <outdir>/chat.txt "$dir"/
```

The script prints a `=== summary ===` block with the output dir and whether `transcript.txt` and `chat.txt` are present. (It nests output under `<outdir>/<video-id>/`, hence the copy step — copy the two `.txt` files into the stream folder; an absent transcript copies nothing, which is fine.)

- **Transcript ABSENT?** YouTube hasn't generated auto-captions yet — normal for a long, freshly-uploaded VOD (can take a day+). You still get `chat.txt`. Tell the user, offer to (a) proceed from chat + their own recollection now, or (b) retry in a day for the full transcript. Don't fake spoken content you don't have.
- The transcript is auto-caption text: expect mis-hearings (names, product terms, "PostHog" → "Poshog/Bosok", "Colyseus" → "Colus/Kissios", "Fable", "meep"). Read through them; don't quote them verbatim if garbled.

### 2. Mine it

Read `transcript.txt` (it's one long line — wrap it to read, or read in offsets) and `chat.txt`. Pull out:

- **What actually shipped** — concrete, working-at-end-of-stream outcomes. Be honest about how far it got (don't under- or over-sell).
- **What changed vs the plan** — diff against `initial-plan.md` and the previous stream note. Backend/stack/scope pivots are the high-value ones. Frame as deltas that the repo docs now own.
- **Bugs / friction hit live** — especially against the tools being dogfooded (PostHog Code). Keep a running tally across streams.
- **Ideas from chat** — the genuinely good/funny/clippable ones (these are gold for both the next stream and the posts).
- **Stated next steps** — what the user said they'd do next; turn it into a recommended next-stream spine.
- **The broadcast itself (don't skip this — it's half the value).** Assess the stream *as a stream*, not just the code: pacing (how long before real work started; did he lose track of time; preamble length), tangent control (charming-about-the-work vs meandering off it), chat engagement (how early he checked the room, whether he welcomed/prompted lurkers, rapport quality), on-screen legibility (multi-agent panes that even he got lost in; fonts/flashbang), the open and the ending (did it land on a high or drag), and ops/tooling failures (multistream, dictation, audio, capture). The transcript is full of tells — time-surprise asides ("oh my god it's been 4 hours"), "am I talking to the void?", "which one did it open?", long shout-out wind-downs. Be honest and specific; this is craft feedback, give a verdict plus concrete fixes.

### 3. Write the note

Write into the stream folder from step 1. Match the structure of the most recent stream's files (read them first).

**`recap.md`** — the recap proper:

1. **Header: a one-line blockquote of this file's own facts only** — e.g. `> Frozen as of <date>. The VOD, transcript, chat, and posts are in [stream.md](stream.md).` The VOD/aired/platform metadata lives in `stream.md`, not here; do NOT duplicate it. Do NOT re-explain frozen-truth or source-of-truth either — those conventions live in the folder `README.md`.
2. **What shipped.**
3. **What changed vs the plan** (defer to repo for current truth).
4. **Bugs filed** (running tally).
5. **Ideas from chat** (keep).
6. **Next-stream plan** — an opinionated spine, not a laundry list. Lead with closing loops the audience watched break; give it a hook.
7. **The stream as a broadcast** — a verdict, then what worked / what dragged / fixes, covering pacing, tangents, chat engagement, on-screen legibility, the open and ending, and ops/tooling. Treat the stream rig (capture, audio, multistream, Discord) as the actionable tail of this section, not a separate one.
8. **Open questions** — explicitly "answered in the repo docs, not tracked here."

**`stream.md`** — the folder's entry note. Title (`# <project> — Stream N (<date>, <day>)`), a one-line blockquote with the aired date/duration/platforms and a one-line summary, the **VOD embedded** as `![Stream N VOD](<youtube-url>)` (Obsidian renders the player; the alt text keeps markdownlint happy) followed by a plain `VOD: <url>` line, then an **"In this stream"** list linking `recap.md`, `posts.md`, `transcript.txt`, `chat.txt`.

Add a row for the new stream to the `README.md` index table (link the folder's `stream.md`). Run `markdownlint <files> README.md` (the notes repo's `.markdownlint.json` allows long lines). Commit with a terse message; **do not** add AI attribution. Leave `.obsidian/workspace.json` churn unstaged. (Commits are SSH-signed via 1Password; if signing errors, retry — never disable it.)

### 4. Optionally draft the social posts

If the user wants the recap posts, draft **X** and **LinkedIn** versions into `posts.md` in the same stream folder. First read `social-playbook.md` (cadence, voice, templates) and the **previous** stream's `posts.md` **"story state after stream N"** footer, so the serialized story stays continuous. The new file's header is a one-liner (VOD link only — conventions live in the README), and it ends with a fresh **"story state after stream N"** footer for the next run. Apply `rs-tone` (register: casual/`external`). House notes for these specifically:

- PostHog brand voice: opinionated, concrete, no marketing-speak, honest to the point of self-deprecation — lean *into* the bugs and the chaos. James-Hawkins-shitposter energy works for LinkedIn (fake-corporate-flex opener, then undercut it).
- Be accurate to what shipped (the transcript is the fact-check). Don't claim products that weren't wired up.
- Keep the strongest chat idea as the hook. Match the format of the previous stream's posts if the user liked them.

## Notes

- The fetch script uses `uvx yt-dlp` — nothing is installed permanently.
- Don't put stream-rig config tooling here; that's `~/dev/rs/stream-setup/bin`. This skill is post-production content, a separate concern.
