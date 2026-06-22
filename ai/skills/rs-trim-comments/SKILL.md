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

- **Terse means dense, not vague.** Say the why or the constraint in the fewest words that land it — one tight sentence beats three. But never drop the detail that makes the comment worth reading.
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

## Sweep mode

When invoked directly:

1. **Resolve the target.** If the user named a file, use it. Otherwise sweep the current diff (`git diff` for unstaged work, or the branch against its base).
2. **Find the offenders.** Comments that restate code, narrate edits, pad with filler, or reference retired behavior. Flag any comment that fails [the bar](#the-bar-does-this-comment-earn-its-place).
3. **Fix in place.** Delete the noise; tighten the keepers (terser, state-not-change). Don't touch comments that already earn their place.
4. **Preserve required doc comments.** Leave docstrings / doc comments that a public API or doc generator needs — those follow the language's own conventions, not this skill.
5. **Report briefly** — what was cut and what was tightened, no diff recap beyond what's useful.
