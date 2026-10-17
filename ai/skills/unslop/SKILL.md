---
name: unslop
description: "Make AI-built code look deliberate without changing what it does: reuse and consolidate the project's existing patterns, replace hand-rolled code with the standard library or a maintained package, and strip residue such as narration comments, speculative wrappers, and hollow tests. Works on a code change (default, edits stay inside it) or a whole repository (ranked findings first). Use when asked to unslop, simplify, de-AI, clean up, deduplicate, make code consistent, or find custom code a package could replace; use review-only mode when the user asks for findings instead of edits."
---

# Unslop

Code built across many AI sessions drifts the same way: each session solves its problem afresh, hand-rolls what a library already does, and leaves explanation and defensive padding behind. Undo that drift. The target is the smallest clear implementation that solves each problem the way the project already solves it, and owns only what the project cannot get elsewhere.

For any piece of code, prefer in this order: delete it, call something the project already has, use the language's standard library or the framework in use, use a dependency already in the lockfile, add a new package, and only then keep the custom version.

Preserve behaviour, public contracts, validation, observability, accessibility, and useful error context throughout. Do not redesign features or trade readable code for clever code; a longer implementation is sometimes the honest one.

## Scope

Pick one scope before reading code and state it in the report.

**Change scope** is the default. Use the files the user names or the complete working change. Resolve the parent from PR metadata when available; otherwise infer or confirm the parent branch and its merge-base rather than treating the feature branch's same-named upstream as its parent. Include committed branch changes, tracked staged and unstaged changes, and every untracked non-ignored file. Edit only lines the change introduced or modified, plus the minimum outside them that a cleanup requires, such as a caller of a renamed helper. Everything else you notice goes in the report as out of scope, so the PR stays reviewable.

**Repo scope** applies when the user asks about the repository, codebase, project, or a directory as a whole, or when there is no change to scope to. Cover every tracked file (`git ls-files`) except vendored, generated, and lockfile content, grouped by area. In a large repository, split the areas across parallel subagents that each return candidate findings with file and line evidence, then verify every candidate yourself. Return ranked findings first and apply only the ones the user picks, unless they asked to fix everything up front. Apply in batches of one concern each, verifying each batch before starting the next.

**Review-only** applies in either scope when the user asks to inspect or review: return findings and edit nothing.

## Learn the project first

Nothing can be judged a reinvention until you know what exists. Before judging code:

- Read the manifests and lockfiles, the pinned language and framework versions, the check and test commands, and any conventions docs (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING`, READMEs).
- Map the shared homes: where helpers, types, components, clients, constants, and test fixtures live, and what they are called.
- For each block in scope, search for code doing the same job, by name, by the calls and libraries involved, and by the shape of the data. In change scope this search still covers the whole repository; only edits are limited.
- In repo scope, run the ecosystem's dead-code, unused-dependency, and duplication detectors (such as knip, depcheck, vulture, `cargo shear`, `cargo machete`, jscpd) when the project already installs or configures them, or when they run without changing the repository. Treat their output as candidates to verify, not findings; never add them to the project unasked.

## What to look for

### Reinvented internals

- Code that rebuilds an existing helper, type, component, constant, client, or fixture instead of calling it.
- The same job done two or more ways across the codebase. Pick the way that should win (most used, best tested, or documented as the convention), say why, and move the others to it.
- Three or more near-copies with a stable shared shape and no shared home. Extract one abstraction, named for what it does, placed where the existing code would look for it.
- An existing abstraction that is bypassed, or extended with a parallel variant instead of a parameter it could take.

Look hardest at error handling, logging, configuration and environment loading, API and database clients, request and response shaping, validation, retries, UI components and styling, state management, file layout and naming, CLI structure, script helpers, and test setup.

Do not abstract on a guess. Two copies, copies diverging for real reasons, or a shared shape that needs a flag per caller are better left duplicated. An abstraction earns its place with at least three real callers, a clear name, and a more stable boundary than the code it replaces. Compare each copy's edge cases before merging them so no call site changes behaviour.

In change scope, new code uses the existing pattern even where that is less convenient. If the change adds another copy of a pattern that already has several, extract the shared version only when that does not mean rewriting unrelated callers; otherwise use the closest existing form and report the consolidation as out of scope.

### Reinvented externals

Look for hand-rolled argument parsing, date and duration handling, CSV/YAML/TOML/INI parsing, semver comparison, URL and path manipulation, glob matching, deep merge and clone, schema validation, retry and backoff, rate limiting, concurrency pools, caching, templating, diffing, terminal output, HTTP clients, and shell scripts that reimplement an existing CLI. Before recommending a replacement:

- Read the docs or types for the version the project pins or would install, not memory.
- List what the custom code actually does, including edge cases and error handling, and confirm the replacement covers all of it.
- For a new package, check that it is actively maintained, widely used, licence-compatible, and proportionate in size and transitive dependencies. Do not add a dependency to replace a few obvious lines.

Switching to the standard library or an existing dependency needs no approval. Adding a new dependency is the user's decision: propose it with the rationale and the code it removes, add it only after approval, and record the rationale wherever the repository documents its dependencies.

The reverse also counts: a dependency used for one or two calls the standard library or framework now covers, and two dependencies doing the same job, such as two date libraries or an HTTP client alongside the platform's `fetch`. Pick the one to keep by the same reasoning as internal patterns, migrate every use, then remove the other from the manifest and lockfile.

### Residue

- Comments that narrate, record change history, repeat names, or could be derived from the code. Keep a comment only for a necessary invariant or non-obvious reason, in the shortest accurate form; if it calls work bounded, confirm the code enforces a concrete limit.
- One-use wrappers, pass-through helpers, speculative interfaces, and options or configuration with one meaningful value.
- Temporaries, conversions, and fallbacks that do not make the data flow easier to follow, and defensive branches no real caller can reach.
- Generic fallbacks that hide an impossible state or a real failure, and errors that restate that something failed instead of naming the operation and preserving the cause.
- Tests that cannot fail for the right reason: self-derived fixtures, permissive assertions, excessive mocks, tests of implementation details, and duplicates. Each test should rule out a specific wrong result using expectations independent of the code under test.
- Prose padding: needless headings, recaps, throat-clearing, and repeated claims.

### Dead and stale code (repo scope)

- Unused files, exports, scripts, config, and declared dependencies, confirmed by searching for every reference, including dynamic ones such as config keys, CLI entry points, and string-built imports.
- Docs, READMEs, and comments that describe behaviour the code no longer has.

## Guardrails

Follow every candidate into its callers, types, and tests before changing it; do not delete code merely because it looks verbose. Keep intentional repetition when it makes ownership, control flow, or failure handling clearer, and keep boundary checks whose callers or trust model justify them. If a simplification cannot be proved behaviour-preserving, leave it and name the uncertainty.

## Verify and report

Review the final diff for accidental behaviour changes. Run the narrowest relevant formatter, linter, type-checker, and tests, then the repository check command when practical.

After edits, report what became simpler, any deliberate complexity retained, out-of-scope observations (change scope), and the verification performed. For findings (repo scope or review-only), return only verified items ranked by payoff against risk, each with its location, evidence, proposed change, and whether it needs a new dependency, followed by the scope actually audited and the checks performed. Do not commit or push unless asked.
