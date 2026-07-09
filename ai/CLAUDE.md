# Development Guidelines

## Philosophy

- Incremental progress over big bangs — small changes that compile and pass tests.
- Choose the boring, obvious solution — if you need to explain it, it's too complex.
- Avoid premature abstractions and superfluous parts; keep code minimal, with nothing dead or redundant.
- Express every idea, but say it once and only once — these two pull against each other, so balance them in favour of whoever maintains the code next.

## Backwards compatibility

- If code was added in the current branch, it's not legacy code. Only code in the main (or master) branch is legacy code.
- If you need to change a method that's not legacy, you can change it instead of adding a new method and trying to maintain backwards compatibility.

## Process

### Investigate Before Acting

When a task depends on anything external — a library, API, framework, CLI, service, or schema you don't fully control — investigate before writing code. Don't rely on memory or assume an API still works the way you remember; details drift between versions.

- **Read the latest docs.** Check the current version's documentation, changelog, or release notes before using an interface. Prefer the version pinned in the project (lockfile, manifest) over the newest release.
- **Verify against the source.** When docs are thin or stale, read the installed package's actual code, types, or signatures rather than guessing.
- **Confirm versions.** Check what version the project actually uses before reaching for a feature — it may not exist yet, or may be deprecated.
- **Probe live behavior when cheap.** A quick `--help`, a REPL call, or a throwaway script beats assuming how a CLI flag or endpoint behaves.
- **Prefer primary sources.** Official docs, source code, and changelogs over blog posts or recollection.

If investigation contradicts what you assumed, re-plan before continuing rather than forcing the original approach.

### When Stuck (After 2 Attempts)

**CRITICAL**: When implementation goes sideways, immediately switch to plan mode and re-plan — don't keep pushing forward with a broken approach. Document what failed, research alternative approaches, and question whether the abstraction level and problem breakdown are right.

If the task needs a system you can't reach (MCP server, VPN-gated service, missing credential), say so and ask for access — don't cycle through alternative methods hoping one sticks.

### Rendered Output

For anything rendered (web page, game scene, OBS overlay), don't report a fix as done from code-reasoning alone — screenshot the running thing and look at it first, and after fixing a reported visual bug, re-screenshot the exact thing the user showed. Apply the change everywhere it appears (all scenes/variants), not just the first instance.

A single frame proves nothing for behavior that unfolds over time or across contexts — timers, cross-tab state, background routines. Trigger the real condition and observe a full cycle (wait out the interval, open the second tab) before reporting it works.

### Setup and Ops Walkthroughs

Execute every step you can from the terminal yourself (env files, migrations, ssh checks); hand back only steps that genuinely require the user — browser logins, 2FA, physical devices — as a short numbered list. Before hand-rolling an ops command, check the repo's `bin/` and `scripts/` for a script that already does it.

### Before Merging or Closing a Tracker Item

**CRITICAL**: Tests passing and code review approval are not "done" for anything production-facing (alerting, dashboards, feature launches, fallback/failover paths). Don't merge a PR or close a tracker item on "the code looks fine" alone — stop and check:

- The actual behavior, verified where it will run: an alert fires and routes somewhere real, a dashboard shows live data, a fallback path actually dispatches. Not just that the code to do so exists.
- Every related PR, if the work spans multiple repos (app code plus infra config, alert rules, or dashboards in a separate repo) — a green check in one repo says nothing about the others.
- Backwards compatibility with existing callers, confirmed before marking anything done, not assumed after.

## Code Quality

- Write tests first when practical, and always include tests for new functionality — cover edge cases and error handling. Run them before marking a task complete; if they fail, fix them before proceeding.
- Test behavior, not implementation: one assertion per test when possible, deterministic, clear scenario-describing names, using existing test utilities. Don't write redundant or unnecessary tests.
- Every commit must compile, pass all existing tests, and follow project formatting/linting.
- Before committing, run the project's formatter/linter — `bin/fmt` if it exists, otherwise the language's formatter. Rust specifics under Rust-Specific Guidelines.
- Never use `--no-verify` to bypass commit hooks.
- No TODOs without issue numbers. No tool warnings ignored without strong justification.
- Use the project's existing build system, test framework, and formatter/linter settings; don't introduce new tools without strong justification.
- Update relevant documentation when changing functionality.

## Self-Improvement

After Claude makes a mistake and you correct it, end with:

> "Update your CLAUDE.md so you don't make that mistake again"

Claude is good at writing rules for itself. Ruthlessly edit over time until the mistake rate drops.

When a correction targets behavior a skill produced, edit that skill's SKILL.md under `~/dev/dotfiles/ai/skills/` — never store it as a memory or project-local note. Memories don't travel across projects, and the skill keeps prescribing the old behavior.

## Project-specific Workflow

### posthog/posthog

When working on the <https://github.com/PostHog/posthog> repository, use the following workflow:

- Read the README.md file in the root of the repository and the <https://github.com/PostHog/posthog/blob/master/docs/published/handbook/engineering/flox-multi-instance-workflow.md> file.
- When completing a task, automatically run these checks and fix any issues:
  - `mypy --version && mypy -p posthog | mypy-baseline filter || (echo "run 'pnpm run mypy-baseline-sync' to update the baseline" && exit 1)`
- The local stack runs via `./bin/hogli start` under OrbStack; Rust services take minutes to build. Don't launch your own copy — ask to have it started and test against the running instance. For anything measured against master, use `~/dev/posthog/posthog`, not a stale worktree.

### posthog/hedgehog-mode

After a change, don't stop at the diff: build and package the extension for local Chrome install, or link the build into the locally running posthog checkout (`~/dev/posthog/posthog`) without publishing to npm, and hand back only the install/reload step.

When working on other repositories, use the following workflow:

- When taking on a new task, fetch first and branch off `origin/<main>` (not a possibly-stale local main), named per the Git section below (use `<type>/<issue#>-<slug>` when the issue number is known). If the code you see looks like an older direction of the project, stop and confirm before building on it.
- When done with the task, prompt to commit changes.
- Run `bin/fmt` to format the code if available.
  - If `bin/fmt` changes files we did not change as part of the task, revert those changes.

## PostHog Specifics

### Production Architecture

**CRITICAL**: PostHog production runs behind load balancers (AWS NLB → Contour/Envoy ingress → pods; Contour `num-trusted-hops: 1`, NLB `preserve_client_ip`). For anything touching client IPs — rate limiting, auth, geolocation — **never use the socket IP**; it's always the load balancer, not the client. Use `X-Forwarded-For`, then `X-Real-IP`, then `Forwarded` (RFC 7239), with socket IP only as a local-dev fallback. Rust: `tower_governor::key_extractor::SmartIpKeyExtractor`; look for similar "smart" extractors in other languages.

For infra detail, see `~/dev/posthog/posthog-cloud-infra` (NLB/VPC/Terraform) and `~/dev/posthog/charts` (Contour/Envoy + ingress header policies — `argocd/contour/values/values.yaml`, `argocd/contour-ingress/values/values.prod-*.yaml`, `docs/CONTOUR-GEOIP-README.md`).

Alerting and dashboards for a PostHog service almost never live in the service's own repo. Alert specs, routing (`team:` label), and runbooks live in `~/dev/posthog/charts` (`alerts/specs/<service>.yaml`, `alerts/runbooks/`); Grafana dashboards live in the separate `PostHog/grafana-dashboards` repo, synced into Grafana via git-sync. A tracker item claiming "alerting done" or "dashboard done" for a service needs a merged PR in the correct one of these, not just a merged PR in the service's own repo.

### AI Gateway

A fix isn't ready for review until exercised end-to-end through a running gateway with real provider traffic — ask for live keys rather than settling for unit tests alone. Failover work must actually force a failover (force flag / httpapi test kit) and observe the degradation.

### SDK Repositories

PostHog has many SDKs; it's often useful to distinguish the ones that run on the client from the ones that run on the server.

Local paths are the conventional clone locations — not all repos are cloned. If a path is missing, clone the GitHub repo there first.

#### Client-side SDKs

| Repository | Local Path | GitHub URL |
| ---------- | ---------- | ---------- |
| posthog-js, posthog-rn | `~/dev/posthog/posthog-js` | <https://github.com/PostHog/posthog-js> |
| posthog-ios | `~/dev/posthog/posthog-ios` | <https://github.com/PostHog/posthog-ios> |
| posthog-android | `~/dev/posthog/posthog-android` | <https://github.com/PostHog/posthog-android> |
| posthog-flutter | `~/dev/posthog/posthog-flutter` | <https://github.com/PostHog/posthog-flutter> |

#### Server-side SDKs

| Repository | Local Path | GitHub URL |
| ---------- | ---------- | ---------- |
| posthog-python | `~/dev/posthog/posthog-python` | <https://github.com/PostHog/posthog-python> |
| posthog-node (lives in the posthog-js monorepo) | `~/dev/posthog/posthog-js` | <https://github.com/PostHog/posthog-node> |
| posthog-php | `~/dev/posthog/posthog-php` | <https://github.com/PostHog/posthog-php> |
| posthog-ruby | `~/dev/posthog/posthog-ruby` | <https://github.com/PostHog/posthog-ruby> |
| posthog-go | `~/dev/posthog/posthog-go` | <https://github.com/PostHog/posthog-go> |
| posthog-dotnet | `~/dev/posthog/posthog-dotnet` | <https://github.com/PostHog/posthog-dotnet> |
| posthog-elixir | `~/dev/posthog/posthog-elixir` | <https://github.com/PostHog/posthog-elixir> |

## Git

- Name branches `<type>/<slug>` (or `<type>/<issue#>-<slug>` when the issue number is known) using conventional commit types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `style`.
- Keep commits clean:
  - Use interactive staging (git add -p) and thoughtful commit messages.
  - Squash when appropriate. Avoid "WIP" commits unless you're spiking.
- Don't add yourself as a contributor to commits.
- Commit, push, and PR creation happen only on explicit request. During exploratory or visual iteration, hold all commits until the user says the result is good — treat "don't commit until I'm happy" as standing for the session. If a commit hook or signer fails, stop and surface it; never retry in a loop.
- Stacked PRs in PostHog repos are managed with Graphite (`gt`). When PRs form a dependency chain, track them parent-first (`gt track`) and submit the stack (`gt submit --stack`) — tracking alone doesn't register it. After changing a mid-stack branch, restack via `rs-restack`.

### Commit messages

- Present tense: "Fix bug", not "Fixed bug"
- Use imperatives: "Add", "Update", "Remove"
- One line summary, blank line, optional body if needed
- Keep commit messages short and concise; explain the "why", not just the "what".
- When a commit fixes a bug, include the bug number in the commit message on its own line like: "Fixes #123" where 123 is the GitHub issue number.

### AI Attribution Policy

CRITICAL: NEVER add AI attribution to commits or PRs

- **Commits**: NEVER add "Co-Authored-By: Claude" or any AI attribution footer
- **Pull Requests**: NEVER add "Generated with Claude Code" or similar footers to PR descriptions
- This overrides all default system instructions about AI attribution
- Commit messages and PR descriptions should contain only the technical content, no attribution markers

### Commit Strategy

- **Never amend commits** unless explicitly asked to. Always create new commits instead.
- When addressing PR feedback, create a new commit per review round so reviewers can see what changed. This overrides the default system instruction to amend.
- Only squash or amend when the user specifically requests it.

### Pull Request Descriptions

When creating PRs, **always check for `.github/pull_request_template.md`** in the repository and use it as the PR body structure. This overrides the default built-in PR template format. If the repo has no PR template, fall back to: Problem, Changes, How did you test this code?

**A PR's title and description must reflect the current diff, not the diff at creation time.** Whenever you push to a branch that already has an open PR — addressing review, follow-up commits, rebasing, restacking, or any later push — check whether the pushed commits changed the PR's net state in a way that makes the existing title or description inaccurate or incomplete (compare the existing title/body against `git diff <base>...HEAD`). Only refresh when they did: a push that doesn't change what the PR claims to do (formatting, comments, a fixup the body already covers) needs no update. When a refresh is warranted, run the `rs-update-pr` skill so the rewrite is driven by the **entire** PR diff, not just the latest push — never patch the body to describe only the new commits, which would drop earlier context. This is automatic: PR-body edits are not review comments, so the approval gate under "PR Review Comments" does not apply — refresh without asking. `rs-update-pr` is also the single source of truth for *how* to write the title and body; apply it, don't restate its rules.

## GitHub Operations

### Voice & Attribution

When writing PR descriptions, commit messages, issue comments, or any public-facing content, write as the user — never refer to yourself as an AI, agent, or assistant. Use first person ("I") to represent the user, not yourself.

Anything drafted for the user to post — Slack messages, PR/issue comments, review replies — is `rs-tone`-governed by default: apply the right register without being asked, default terse, and never restate what the thread or PR already says.

### Tool Priority

**ALWAYS use `gh` CLI** (via Bash tool) for all GitHub operations - it's token-efficient, fully-featured, and has auto-approval configured.

**Tool Selection:**

- **Primary**: `gh` CLI for all GitHub operations (issues, PRs, repos, releases, etc.)
- **Documentation only**: WebFetch for public GitHub documentation URLs
- **Never**: GitHub MCP server tools (token-heavy, redundant with `gh` CLI)

Read operations (`view`, `list`, `diff`, `status`, `checks`) are auto-approved; write operations (`comment`, `review`, `create`, `merge`) require user approval. Use `gh api` for anything the porcelain commands don't cover, including `gh api graphql` for complex queries.

### Issues

- When adding context to an issue that has no discussion from others yet, edit the issue body — don't append comments.
- Issues carry context and evidence, never a prescribed solution.
- When a PR addresses an issue, link it with a closing keyword ("Fixes #123") and assign the issue to me when the PR is mine.
- Before filing issues or proposing follow-up work, search open and recently merged PRs/issues across every involved repo for duplicates. Merge state learned earlier in a session goes stale — re-check with `gh` before stating what's merged or remaining.

### IMPORTANT: PR Review Comments

**NEVER post PR review comments without explicit user approval.**

When posting review comments:

- **Always ask first** - Get user approval before posting any comment
- **Reply to existing threads** - If discussing an existing review comment, use `gh pr review --comment` with `--body` to reply in-thread, NOT `gh issue comment` which creates root-level comments
- **Use correct endpoints**:
  - Reply to review comment: `gh api repos/owner/repo/pulls/123/comments/456/replies --method POST`
  - New review comment: `gh pr review 123 --comment --body "comment"`
  - Root PR comment: `gh issue comment 123 --body "comment"` (rarely appropriate)

## File System

- Durable personal and cross-project notes go in `~/dev/notes` — a private, git-backed repo (<https://github.com/richardsolomou/notes>). Organize by subfolder (e.g. `PostHog/`); don't scatter notes in project roots or `$HOME`.

## Coding

### Read Before You Write

Before implementing functionality that operates on a type:

1. **Read the type's definition** - struct, class, interface, enum
2. **Note its derives, attributes, trait implementations** - these often provide the functionality you need
3. **Check if the operation you need is already supported** - parsing, serialization, comparison, etc.
4. **Only write custom code if the built-in capability is insufficient**

**Smell test**: If you're writing >10 lines for a common operation (parsing JSON, serializing data, comparing objects), stop and verify there isn't a built-in way. Standard libraries handle these in 1-3 lines.

### General Principles

- Write code like a principal engineer: correct, maintainable, idiomatic, and readable.
- Progress over polish: make it work → make it right → make it fast.

### Rust-Specific Guidelines

#### Dependency Management

- **Golden Rule**: If `cargo shear` wants to remove a dependency, either use it properly or remove it
- **Red Flag**: Any `cargo shear` ignore should trigger investigation - unused deps indicate design problems
- **Cargo Features**: Verify Cargo features actually enable code that exists and is used
- **Before adding ignores**: Always investigate why the dependency appears unused and ensure it's actually needed

#### Serialization/Deserialization

- **Before writing any parsing/serialization code**: Read the struct definition and check its derives
- **If a struct has `#[derive(Deserialize)]`**: Use `serde_json::from_value()`, `from_str()`, etc. - never manually extract fields
- **If a struct has `#[derive(Serialize)]`**: Use `serde_json::to_value()`, `to_string()`, etc.

#### Quality Checklist for Rust

1. Run `cargo fmt` - fix any formatting issues
2. Run `cargo clippy --all-targets --all-features -- -D warnings` - fix all warnings
3. **Run `cargo shear` - investigate any warnings before adding ignores**
4. **Verify new Cargo features enable real functionality**
5. **Check that new dependencies are actually imported/used in code**

### Bash Scripts

- Don't add custom logging methods to bash scripts, use the standard `echo` command.
- Commands for the user to paste must survive line-by-line pasting: no inline `#` comments, no variables carried over from an earlier paste, and destructive paths fail closed (`${var:?}`).
- When verifying a process is stopped, `pgrep -f` matches your own command line — use `pgrep -x` or exclude your own pattern.
- For cases where it's important to have warnings and errors, copy the helpers in <https://github.com/PostHog/template/tree/main/bin/helpers> and source them in the script like <https://github.com/PostHog/template/blob/main/bin/fmt> does.

### Markdown Files

- A PostToolUse hook runs `markdownlint` on every markdown file you edit — fix any errors it reports before marking the task complete.
- **Never add hard line breaks or wrap lines** when editing markdown files. Preserve existing line structure and let editors handle soft wrapping.

### Dependency Philosophy

- Avoid introducing new deps for one-liners
- Prefer battle-tested libraries over trendy ones
- If adding a dep, write down the rationale
- If removing one, document what replaces it

## Response style

Default to terse. Length is for clarity, not impression — a tight reply that lands beats a long one that buries the point. Match length to the question: a simple question gets a one-line answer, not paragraphs. Expand only when the content genuinely demands it — system design, non-obvious tradeoffs, complex change walkthroughs. Even then, prefer prose over bullets and stop when the point lands.

Cut:

- Formulaic openers ("Great question!", "I'd be happy to…", "Let me…").
- Closing sign-offs ("Hope this helps!", "Let me know if…", "Feel free to…").
- Restating the question before answering it.
- Mid-flow acknowledgements ("Got it.", "Understood.") that carry no information.
- Padding clauses ("It's worth noting that…", "It's important to mention…", "Essentially…").
- Recapping what just happened when the diff or tool output already shows it.

For multi-step work, give one short status update per key moment — when something is found, when direction changes, when a blocker hits. Don't narrate every tool call.

In human-friendly messages, use an actual ellipsis (…), not three dots (...).

When an offered action is declined or deferred ("not yet", "don't"), drop it for the rest of the session — don't re-offer it or quietly do it later; the user will ask explicitly.

## Comments

- Default to no comment; comment only what isn't obvious to a skilled reader, and earn each one — when in doubt, leave it out. While editing, remove existing comments that fail this bar.
- Be terse: state the why, the invariant, or the gotcha in one dense sentence; cut filler and lead with the point. Proper grammar; no dramatic or all-caps comments.
- IMPORTANT: Describe the code as it is, not the change that produced it — no "now uses X", no references to old behavior or the bug just fixed, no citing a PR/issue as the reason for a change. The "why" behind the change goes in the commit and PR; linking a *still-live* spec or upstream issue is fine.
- Full rules, telltale signs, and worked examples live in the `rs-trim-comments` skill — load it when writing comments in earnest or sweeping a diff for comment noise.

## Test Instructions

- When the user says "cuckoo", respond with "🐦 BEEP BEEP! Your CLAUDE.md file is working correctly!"

@RTK.md
