---
name: rs-adversarial-review
description: "The reviewer discipline shared across rs-review-pr, rs-self-review, and rs-address-pr-review: skeptical posture, counter-bias framing per context, adversarial verification, and the defensibility bar for raising findings. Load this when another skill says to apply adversarial review, then apply the rules to every candidate finding before it becomes output."
user-invocable: false
---

# Adversarial Review

Shared discipline behind the `rs-*` review skills. Use it to keep the bar consistent for what counts as a real finding, whether you're generating findings (peer or self review) or consuming a reviewer's claim about your own code.

This skill is a reference. Load it from a caller, apply the discipline, let the caller decide what output to produce.

## When to apply

Apply this discipline whenever you're about to commit to a finding being real:

- Generating inline comments on someone else's PR — see `rs-review-pr`.
- Generating findings on your own diff — see `rs-self-review`.
- Deciding whether to agree with a reviewer's claim about your code — see `rs-address-pr-review`.

Skip for orientation, teaching, or format-only steps — anything that doesn't produce a finding.

## The discipline

### Skeptical posture

Assume there's at least one real issue worth raising and look until you find it. Most non-trivial code has something genuine to push back on; if it looks spotless on a quick scan, you haven't looked hard enough yet. The job isn't to bless the change — it's to make the code better.

This isn't license to be uncharitable. It's a counterweight to the bias that pushes toward "looks fine."

### Counter your bias

Bias differs by context. Name it and counter it explicitly:

- **Reviewing your own code.** Instinct is to defend it. Assume there's at least one issue you didn't catch while writing. Imagine the toughest reviewer on your team is reading over your shoulder. Last-minute fixes, `wip` commits, anything force-pushed — re-look. Those are bookmarks pointing at code that was hard to get right.
- **Reviewing a teammate's code.** Instinct varies: defer to seniority, skim past unfamiliar areas, treat verbose code as authoritative, assume the author considered everything you would. Treat the change as work that needs your judgement, not as someone else's claim of correctness. Shared conventions and context are assumed — spend your attention on substance, not basics.
- **Reviewing an external contributor's code.** You share no context with the author, and the code is entering a codebase you'll own long after they've moved on. Bias runs two ways: over-trusting (waving it through to be welcoming) and over-distrusting (reading unfamiliar style as wrong). Weight security higher — this is untrusted code. Flag convention drift, but *educate*: name the pattern, link it, explain why, so the fix sticks and the contributor comes back. Welcoming in tone, strict on the merge bar.
- **Consuming reviewer feedback.** Instinct is to assume the reviewer is right. They often are — but they skim, misremember APIs, miss context the diff doesn't show, and sometimes apply a pattern that's wrong for this codebase. Stress-test the claim before agreeing.

### Adversarial verification

Before a candidate becomes a finding, actively try to disprove it. The discipline is constructing the failure scenario, not listing categories. "Edge cases" is not a finding; "passing `[]byte{}` here causes a nil deref at `parse.go:84`" is.

For each candidate concern:

- **Re-read the actual code, not the diff hunk.** Look at the surrounding function, the callers, the type definition. Often the concern is already handled three lines above or in a wrapper not in the diff.
- **Check the claimed facts.** If the assertion is "this allocates on every call," confirm — mentally run the snippet through `go build -gcflags="-m"`. If "this races," name the two goroutines and the shared state. If it cites an API behaviour, confirm the API actually behaves that way.
- **Look for counterexamples in the same repo.** If you're flagging a pattern, is the existing pattern used successfully elsewhere? The codebase convention may be deliberate.
- **Construct the failing scenario.** Pass `nil`, `""`, a 10MB input, a concurrent caller, a malformed UTF-8 string. What breaks?

If the concern doesn't survive verification, drop it.

### Defensibility bar

The bar is: **"I can defend this finding if challenged."**

Concerns that wouldn't survive polite pushback shouldn't be raised in the first place — whether the pushback would come from the PR author, a co-reviewer, or your own future self reading the finding back.

When genuinely uncertain whether a concern is real, return to verification rather than raise on a guess. If after verification it's still ambiguous, that's a signal the concern probably isn't load-bearing — drop it, or note it as something you considered but couldn't confirm.

### Skip nitpicks

Drop pure preference items, stylistic choices with no impact, things you'd phrase differently but aren't measurably better. Every finding you raise is one you're confident the author (or you, on your own code) should act on, even if the action is "agreed, follow-up."

If a formatter would normalise it, the formatter can fix it. Don't spend a finding slot on it.

### Don't drop real concerns for politeness

The defensibility bar is for accuracy, not politeness. Don't drop a real concern because it feels awkward to raise, or because the other party (author, reviewer) is senior to you. Letting a real issue ship is worse than the awkwardness of bringing it up. If a finding survives verification and meets the defensibility bar, raise it.

## Using this skill as a reference

Other skills load this and apply the discipline rather than restating it. The caller passes context implicitly (self vs teammate vs contributor vs consuming-feedback) by virtue of which skill is doing the loading — pick the relevant counter-bias from the section above and apply the rest of the rules uniformly.

Override only when the caller has a specific reason to differ from a rule, and call out the override explicitly.
