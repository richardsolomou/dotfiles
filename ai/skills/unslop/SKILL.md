---
name: unslop
description: "Remove low-value AI-shaped residue from a code change without changing its intended behaviour. Use when asked to unslop, simplify, de-AI, or clean up an implementation after it works; use review-only mode when the user asks for findings instead of edits."
---

# Unslop

Make the change look deliberate: the smallest clear implementation that fits the surrounding code. Preserve behaviour, public contracts, validation, observability, accessibility, and useful error context.

## Scope

Default to the files the user names or the complete working change. Resolve the parent from PR metadata when available; otherwise infer or confirm the parent branch and its merge-base rather than treating the feature branch's same-named upstream as its parent. Include committed branch changes, tracked staged and unstaged changes, and every untracked non-ignored file. Read the complete changed functions and their neighbouring code before editing. If the user asks to inspect or review, return findings only; otherwise apply the cleanup and verify it.

Do not redesign the feature, broaden its scope, or trade readable code for clever code. A longer implementation is sometimes the honest one.

## Interrogate the change

For each changed block, ask:

- What behaviour here is essential, and which lines do not contribute to it?
- Is this duplicating an existing helper, type, parser, validation path, or standard-library operation?
- Does an abstraction have at least three real callers, a clear name, and a more stable boundary than the code it replaces?
- Is a defensive branch reachable from a real caller, or is it handling an imagined state?
- Does each temporary, wrapper, option, fallback, and conversion make the data flow easier to follow?
- Can a comment be derived from the code? If not, does it state a necessary invariant or non-obvious reason in the shortest accurate form?
- If a shortened comment calls work bounded, does the implementation enforce a concrete limit on the relevant rows, payload, or loop?
- Does an error add the failed operation and preserve the cause, or merely restate that something failed?
- Does each test rule out a specific wrong result, using expectations independent of the implementation and fixture that produced the actual value?
- Does the result match the idiom and level of abstraction in neighbouring files?

Follow the answers into callers, types, and tests. Do not delete code merely because it looks verbose.

## Remove only demonstrated residue

Typical candidates are:

- narration comments, change-history comments, and comments that repeat names;
- one-use wrappers, speculative interfaces, pass-through helpers, and configuration with one meaningful value;
- duplicate parsing, validation, conversions, error branches, and tests;
- generic fallback behaviour that hides an impossible state or a real failure;
- self-derived fixtures, permissive assertions, excessive mocks, and tests of implementation details;
- needless headings, recaps, throat-clearing, and repeated claims in prose.

Keep intentional repetition when it makes ownership, control flow, or failure handling clearer. Keep boundary checks whose callers or trust model justify them.

## Verify

Review the final diff for accidental behaviour changes. Run the narrowest relevant formatter, linter, type-checker, and tests, then the repository check command when practical. If a proposed simplification cannot be proved behaviour-preserving, leave it alone and name the uncertainty.

After cleanup, report what became simpler, any deliberate complexity retained, and the verification performed. In review-only mode, return only verified findings and the checks performed. Do not commit or push unless asked.
