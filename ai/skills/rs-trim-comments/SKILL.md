---
name: rs-trim-comments
description: "Keep in-code comments brief, terse, and only where they earn their place — and strip the ones that don't. Use as a reference when writing or editing code in any language, or invoke directly to sweep the current diff (or a named file) for comment noise and fix it. TRIGGER when about to write a comment, when reviewing a diff that adds comments, or when the user asks to clean up / tighten / trim comments. SKIP for doc comments that a public API contract or doc generator requires (those follow the language's docstring conventions), commit messages, and PR descriptions."
argument-hint: "[file-path | diff (default)]"
---

# Comments

Most code needs no comment. Comment only on what a skilled reader can't get from the code itself, and earn each one — every comment is a line future readers must read, trust, and keep true. When in doubt, leave it out.

Two ways to use this skill:

1. **Reference** — load it before writing or editing code so comments come out right the first time. This is the default and the cheapest path: not writing noise beats deleting it later.
2. **Sweep** — invoked directly (`/rs-comments`, optionally with a file path) to scan the current diff or named file for comment noise and fix it in place.

## The bar: does this comment earn its place?

Keep a comment only if it carries something the code can't:

- **The why behind a non-obvious choice** — why this approach and not the obvious one.
- **An invariant or constraint** the reader must hold to edit safely.
- **A gotcha** — a sharp edge that bites if you don't know it's there.
- **A link to a still-live spec or upstream issue** that explains a workaround (`workaround for grpc/grpc#1234`).

Delete it if it does any of these:

- **Restates the code.** `// increment the counter` above `count += 1`, `# loop over users` above the loop. The code already says it.
- **Narrates the obvious.** `// constructor`, `// return the result`, `// import deps`.
- **Pads with filler.** Openers like "This function…", "Here we…", "Note that…" — cut them; lead with the point.

While editing, hold existing comments to the same bar. Delete the ones that fail it — don't preserve clutter just because it was already there.

## How to write the ones that stay

Earning a place is not all-or-nothing. A comment can deserve to exist and still be twice as long as it needs to be. Once you've decided to keep one, compress it:

- **Apply the bar word by word, not just comment by comment.** Cut every clause a skilled reader doesn't need: throat-clearing ("for the same reason as above"), mechanics the code already shows, hedges, and asides. Keep the load-bearing facts — the number, the constraint, the name of the trap — and drop the connective prose around them.
- **Terse means dense, not vague.** Say the why or the constraint in the fewest words that land it — one tight sentence beats three. "Never drop the detail that makes a comment worth reading" means keep the *facts*, not the *words* — the same facts almost always fit in half the lines.
- **Treat length as a smell.** A comment that runs many lines or reads like a paragraph is a candidate to halve, not a finished product. Default target: a keeper is one to three dense lines. Past that you're usually narrating mechanics the code already shows — find the two or three facts doing the work and cut the rest.
- **Proper grammar and punctuation.** No dramatic phrasing, no all-caps.
- **No three-dot ellipses (`...`)** — use a real ellipsis (`…`) if you need one, but a period usually serves.

## Describe the state, not the change

IMPORTANT: A comment describes the code as it is — it should read the same a year later, with no trace of how the code got there. The single most common failure is writing meta-commentary about the edit instead of the state.

Telltale signs you're doing it:

- **Narrating the edit:** "now uses X instead of Y", "switched to…", "refactored to…".
- **Referencing old behavior or the bug just fixed:** "this used to throw on empty", "previously double-counted".
- **Describing the problem the change eliminates** rather than the behavior that remains: "fixes the race where…", "prevents the old deadlock". State what the code guarantees now — "holds the lock across the read so the count stays consistent" — not the defect it retired.
- **Citing a PR/issue as the reason a change was made:** "#78 dropped the retry", "match django_redis (#77)".

The why behind a change belongs in the commit and PR, not the code. Linking a *still-live* spec or upstream issue is fine — that constraint is still true today.

## Examples

❌ Restates the code:

```python
# increment the counter
count += 1
```

✅ Cut it. Or, if there's a real reason:

```python
count += 1  # off-by-one bug here last time we used len(); count as we go
```

❌ Meta-commentary about the edit:

```go
// switched to a mutex here to fix the race in #4421
mu.Lock()
```

✅ States the invariant that holds now:

```go
// hold the lock across read+write so the count stays consistent under concurrent callers
mu.Lock()
```

❌ Filler opener, says nothing:

```ts
// This function takes a user and returns their display name
function displayName(u: User): string {
```

✅ No comment — the signature says it. Comment only if there's a gotcha:

```ts
// falls back to email local-part; SSO users have no displayName set
function displayName(u: User): string {
```

❌ Earns its place but bloated — eight lines of prose for three facts:

```ts
//
// pixi.js (and subpaths like pixi.js/unsafe-eval) is externalized for
// the same single-instance reason: pixi is already a dependency, so
// consumers resolve one shared copy from their tree rather than a ~1.3MB
// duplicate welded into this bundle. Inlining it also makes pixi
// unreachable — consumers can't apply `pixi.js/unsafe-eval` (needed under
// strict-CSP / MV3 hosts that forbid `new Function`) or otherwise
// configure the renderer, because the patch can't see the bundled copy.
external: [/^react($|\/)/, /^react-dom($|\/)/, /^pixi\.js($|\/)/],
```

✅ Same three facts — shared instance, ~1.3MB saved, stays patchable — in three lines:

```ts
// Externalize pixi.js for the same single-instance reason as React: it's already
// a consumer dependency, so they share one copy (~1.3MB) and can still patch it
// (e.g. pixi.js/unsafe-eval, required under strict-CSP/MV3 hosts that ban new Function).
external: [/^react($|\/)/, /^react-dom($|\/)/, /^pixi\.js($|\/)/],
```

## Sweep mode

When invoked directly:

1. **Resolve the target.** If the user named a file, use it. Otherwise sweep the current diff (`git diff` for unstaged work, or the branch against its base).
2. **Find the offenders.** Comments that restate code, narrate edits, pad with filler, or reference retired behavior — flag any that fail [the bar](#the-bar-does-this-comment-earn-its-place). Also flag the **verbose keepers**: comments whose content earns a place but that sprawl across more lines than their facts need.
3. **Fix in place.** Delete the noise; compress the keepers. Earning a place is not a pass on length — apply the [length smell](#how-to-write-the-ones-that-stay) to every comment you keep, including ones already in the file. A legitimate multi-line why-block is still a target: keep the load-bearing facts, cut the prose around them. Leave a comment untouched only when it's already at its densest.
4. **Preserve required doc comments.** Leave docstrings / doc comments that a public API or doc generator needs — those follow the language's own conventions, not this skill.
5. **Report briefly** — what was cut and what was tightened, no diff recap beyond what's useful.
