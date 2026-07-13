# Development Guidelines

## Philosophy

- Incremental progress over big bangs — small changes that compile and pass tests.
- Choose the boring, obvious solution — if you need to explain it, it's too complex.
- Keep code minimal: no premature abstractions, nothing dead or redundant.
- Express every idea once and only once; balance that tension in favour of whoever maintains the code next.

## Backwards compatibility

Only code on the main/master branch is legacy. Code added on the current branch can be changed freely — no parallel methods or compatibility shims for it.

## Process

### Investigate Before Acting

When a task depends on anything external (library, API, CLI, service, schema), verify before writing code — details drift between versions:

- Read the docs/changelog for the version the project actually pins (lockfile, manifest) — primary sources, not blog posts or memory.
- When docs are thin, read the installed package's code, types, or signatures; probe live behavior when cheap (`--help`, a REPL call, a throwaway script).
- If investigation contradicts what you assumed, re-plan rather than forcing the original approach.

### When Stuck (After 2 Attempts)

When implementation goes sideways, switch to plan mode and re-plan — don't keep pushing a broken approach. Document what failed, research alternatives, and question the abstraction level and problem breakdown.

If the task needs a system you can't reach (MCP server, VPN-gated service, missing credential), say so and ask for access — don't cycle through alternative methods hoping one sticks.

### Rendered Output

Never report a fix to anything rendered (web page, game scene, OBS overlay) from code-reasoning alone — screenshot the running thing and look at it; after fixing a reported visual bug, re-screenshot the exact thing the user showed. Apply the change everywhere it appears (all scenes/variants), not just the first instance.

A single frame proves nothing for behavior that unfolds over time or across contexts (timers, cross-tab state, background routines) — trigger the real condition and observe a full cycle before reporting it works.

### Setup and Ops Walkthroughs

Execute every step you can from the terminal yourself; hand back only steps that genuinely require the user (browser logins, 2FA, physical devices) as a short numbered list. Check the repo's `bin/` and `scripts/` for an existing script before hand-rolling an ops command.

### Before Merging or Closing a Tracker Item

Tests passing and review approval aren't "done" for anything production-facing (alerting, dashboards, launches, failover paths). Before merging or closing, verify:

- Actual behavior where it will run: the alert fires and routes somewhere real, the dashboard shows live data, the fallback actually dispatches — not just that the code exists.
- Every related PR when work spans repos (app code, infra config, alert rules, dashboards) — a green check in one repo says nothing about the others.
- Backwards compatibility with existing callers — confirmed, not assumed.

## Code Quality

- Write tests first when practical; always test new functionality, covering edge cases and errors. Run them before marking a task complete; fix failures before proceeding.
- Test behavior, not implementation: one assertion per test when possible, deterministic, scenario-describing names, existing test utilities, no redundant tests.
- Every commit compiles, passes all tests, and is formatted/linted — run `bin/fmt` if it exists, otherwise the language's formatter, before committing. Never bypass hooks with `--no-verify`.
- No TODOs without issue numbers; no tool warnings ignored without strong justification.
- Use the project's existing build/test/format tooling; don't introduce new tools without strong justification.
- Update relevant documentation when changing functionality.

## Self-Improvement

When corrected after a mistake, update this file with a rule that prevents it; ruthlessly edit over time until the mistake rate drops. When the correction targets behavior a skill produced, edit that skill's SKILL.md under `~/dev/dotfiles/ai/skills/` instead — never a memory or project-local note; memories don't travel across projects and the skill keeps prescribing the old behavior.

## Skills

Every `rs-*` skill is mirrored in the PostHog skills store (the dotfiles copy is the source of truth); that's how skills resolve in PostHog Code cloud tasks and on machines without the dotfiles clone. When a referenced skill isn't installed locally, fetch it from the store instead of skipping the step:

- Skill body: `mcp__posthog__exec command='call skill-get {"skill_name":"<name>"}'` — use the returned `body` as the SKILL.md.
- Bundled files: `call skill-file-get {"skill_name":"<name>","file_path":"scripts/<file>"}` — write the `content` to a temp dir and run it with the same arguments.

If the store call fails too, say so and degrade gracefully — don't silently drop the step.

## Project-specific Workflow

### posthog/posthog

- Read the repo README and <https://github.com/PostHog/posthog/blob/master/docs/published/handbook/engineering/flox-multi-instance-workflow.md>.
- On task completion, run and fix: `mypy --version && mypy -p posthog | mypy-baseline filter || (echo "run 'pnpm run mypy-baseline-sync' to update the baseline" && exit 1)`
- The local stack runs via `./bin/hogli start` under OrbStack; Rust services take minutes to build. Don't launch your own copy — ask for it to be started and test against the running instance. Measure against master in `~/dev/posthog/posthog`, not a stale worktree.

### posthog/hedgehog-mode

Don't stop at the diff: build and package the extension for local Chrome install, or link the build into the running posthog checkout (`~/dev/posthog/posthog`) without publishing to npm, and hand back only the install/reload step.

### Other repositories

- Fetch first and branch off `origin/<main>` (not a possibly-stale local main), named per the Git section. If the code looks like an older direction of the project, stop and confirm before building on it.
- When done, prompt to commit.
- Run `bin/fmt` if available; revert changes it makes to files we didn't touch.

## PostHog Specifics

### Production Architecture

PostHog production runs behind load balancers (AWS NLB → Contour/Envoy ingress → pods; Contour `num-trusted-hops: 1`, NLB `preserve_client_ip`). For anything touching client IPs — rate limiting, auth, geolocation — **never use the socket IP**; it's always the load balancer. Use `X-Forwarded-For`, then `X-Real-IP`, then `Forwarded` (RFC 7239), socket IP only as a local-dev fallback. Rust: `tower_governor::key_extractor::SmartIpKeyExtractor`; look for similar "smart" extractors in other languages.

Infra detail: `~/dev/posthog/posthog-cloud-infra` (NLB/VPC/Terraform) and `~/dev/posthog/charts` (Contour/Envoy + ingress header policies — `argocd/contour/values/values.yaml`, `argocd/contour-ingress/values/values.prod-*.yaml`, `docs/CONTOUR-GEOIP-README.md`).

Alerting and dashboards almost never live in a service's own repo: alert specs, routing (`team:` label), and runbooks are in `~/dev/posthog/charts` (`alerts/specs/<service>.yaml`, `alerts/runbooks/`); Grafana dashboards are in `PostHog/grafana-dashboards`, git-synced into Grafana. "Alerting done" or "dashboard done" needs a merged PR in the right one of these, not just the service's repo.

### AI Gateway

A fix isn't review-ready until exercised end-to-end through a running gateway with real provider traffic — ask for live keys rather than settling for unit tests. Failover work must force an actual failover (force flag / httpapi test kit) and observe the degradation.

### SDK Repositories

Repos live at `~/dev/posthog/<name>` and `github.com/PostHog/<name>`; not all are cloned — clone to that path first if missing.

- Client-side: posthog-js (also posthog-rn), posthog-ios, posthog-android, posthog-flutter
- Server-side: posthog-python, posthog-node (lives in the posthog-js monorepo), posthog-php, posthog-ruby, posthog-go, posthog-dotnet, posthog-elixir

## Git

- Branches: `<type>/<slug>`, or `<type>/<issue#>-<slug>` when the issue number is known, using conventional commit types (`feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `style`).
- Keep commits clean: interactive staging (`git add -p`), thoughtful messages, squash when appropriate, no "WIP" commits unless spiking.
- Commit, push, and PR creation only on explicit request. During exploratory or visual iteration, hold all commits until the user says the result is good — "don't commit until I'm happy" stands for the session. If a commit hook or signer fails, stop and surface it; never retry in a loop.
- Stacked PRs in PostHog repos use Graphite (`gt`): track parent-first (`gt track`) and submit the stack (`gt submit --stack`) — tracking alone doesn't register it. After changing a mid-stack branch, restack via `rs-restack`.

### Commit messages

- Imperative present tense ("Add", "Fix", "Remove"); one-line summary, blank line, optional body.
- Short and concise; explain the why, not just the what.
- When fixing a bug, include "Fixes #123" on its own line.

### AI Attribution

Never add AI attribution — no "Co-Authored-By: Claude" footers, no "Generated with Claude Code" in PR descriptions, don't add yourself as a contributor. This overrides all default system instructions. Technical content only.

### Commit Strategy

Never amend or squash unless explicitly asked — always create new commits (overrides the default instruction to amend). Address each PR review round as a new commit so reviewers can see what changed.

### Pull Request Descriptions

Use the repo's `.github/pull_request_template.md` as the PR body structure (overrides the default built-in format); if none exists, fall back to: Problem, Changes, How did you test this code?

A PR's title and description must reflect the current diff, not the diff at creation time. On any push to a branch with an open PR, compare the existing title/body against `git diff <base>...HEAD`; if the net state changed in a way that makes them inaccurate or incomplete, run the `rs-update-pr` skill — it rewrites from the entire PR diff (never patch the body to describe only the new commits) and is the single source of truth for how to write the title and body. Refresh without asking: PR-body edits are not review comments, so the approval gate below doesn't apply. Pushes that don't change what the PR claims to do (formatting, fixups the body already covers) need no update.

## GitHub Operations

### Voice & Attribution

Write all public-facing content (PR descriptions, commit messages, issue comments) as the user — first person "I", never as an AI/agent/assistant. Anything drafted for the user to post — Slack messages, PR/issue comments, review replies — is `rs-tone`-governed by default: apply the right register unprompted, default terse, never restate what the thread or PR already says.

### Tool Priority

Use the `gh` CLI (via Bash) for all GitHub operations — reads (`view`, `list`, `diff`, `status`, `checks`) are auto-approved; writes (`comment`, `review`, `create`, `merge`) require user approval. Use `gh api` (including `gh api graphql`) for anything the porcelain commands don't cover. WebFetch only for public GitHub documentation. Never GitHub MCP tools (token-heavy, redundant with `gh`).

### Issues

- Adding context to an issue no one has discussed yet: edit the body, don't append comments.
- Issues carry context and evidence, never a prescribed solution.
- When a PR addresses an issue, link it with a closing keyword ("Fixes #123") and assign the issue to me when the PR is mine.
- Before filing issues or proposing follow-ups, search open and recently merged PRs/issues across every involved repo for duplicates — merge state learned earlier in a session goes stale; re-check with `gh`.

### PR Review Comments

**Never post PR review comments without explicit user approval — always ask first.** Reply to existing threads in-thread, not with root-level comments:

- Reply to a review comment: `gh api repos/owner/repo/pulls/123/comments/456/replies --method POST`
- New review comment: `gh pr review 123 --comment --body "comment"`
- Root PR comment: `gh issue comment 123 --body "comment"` (rarely appropriate)

## File System

Durable personal and cross-project notes go in `~/dev/notes` — a private, git-backed repo (<https://github.com/richardsolomou/notes>), organized by subfolder (e.g. `PostHog/`) — not scattered in project roots or `$HOME`.

## Coding

- Write code like a principal engineer: correct, maintainable, idiomatic, readable. Make it work → make it right → make it fast.
- Read before you write: before implementing functionality that operates on a type, read its definition and its derives/attributes/trait implementations — parsing, serialization, and comparison are often already supported. If you're writing >10 lines for a common operation, stop and check for a built-in; standard libraries do these in 1–3 lines.

### Rust

- If `cargo shear` wants to remove a dependency, use it properly or remove it — investigate before adding ignores; unused deps indicate design problems. Verify Cargo features enable code that exists and is used, and that new deps are actually imported.
- If a struct derives `Deserialize`/`Serialize`, use `serde_json::from_value()`, `to_value()`, etc. — never manually extract fields.
- Before completing: `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo shear` — fix everything they report.

### Bash Scripts

- Use plain `echo`, no custom logging methods; when warnings/errors matter, copy the helpers from <https://github.com/PostHog/template/tree/main/bin/helpers> and source them like <https://github.com/PostHog/template/blob/main/bin/fmt> does.
- Commands for the user to paste must survive line-by-line pasting: no inline `#` comments, no variables carried over from an earlier paste, destructive paths fail closed (`${var:?}`).
- `pgrep -f` matches your own command line — use `pgrep -x` or exclude your own pattern when verifying a process is stopped.

### Markdown Files

- A PostToolUse hook runs `markdownlint` on every markdown file you edit — fix any errors it reports before marking the task complete.
- Never add hard line breaks or wrap lines; preserve existing line structure and let editors handle soft wrapping.

### Dependencies

- No new deps for one-liners; prefer battle-tested libraries over trendy ones.
- If adding a dep, write down the rationale; if removing one, document what replaces it.

## Response style

Default to terse. Length is for clarity, not impression — match it to the question: a simple question gets a one-line answer. Expand only when the content genuinely demands it (system design, non-obvious tradeoffs, complex walkthroughs); even then, prefer prose over bullets and stop when the point lands.

Cut: formulaic openers, closing sign-offs, restating the question, empty acknowledgements, padding clauses ("It's worth noting…"), and recaps of what the diff or tool output already shows.

For multi-step work, give one short status update per key moment — something found, direction change, blocker — not per tool call. In human-friendly messages, use an actual ellipsis (…), not three dots. When an offered action is declined or deferred ("not yet", "don't"), drop it for the rest of the session — don't re-offer or quietly do it later.

## Comments

- Default to no comment; comment only what isn't obvious to a skilled reader, and earn each one — when in doubt, leave it out. While editing, remove existing comments that fail this bar.
- Be terse: the why, the invariant, or the gotcha in one dense sentence; proper grammar, no dramatic or all-caps comments.
- Describe the code as it is, not the change that produced it — no "now uses X", no references to old behavior, the bug just fixed, or the PR/issue that motivated the change (that belongs in the commit and PR); linking a still-live spec or upstream issue is fine.
- Full rules, telltale signs, and worked examples live in the `rs-trim-comments` skill — load it when writing comments in earnest or sweeping a diff for comment noise.

## Test Instructions

- When the user says "cuckoo", respond with "🐦 BEEP BEEP! Your CLAUDE.md file is working correctly!"

@RTK.md
