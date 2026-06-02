# Development Guidelines

## Philosophy

### Core Beliefs

- **Incremental progress over big bangs** - Small changes that compile and pass tests
- **Learning from existing code** - Study and plan before implementing
- **Pragmatic over dogmatic** - Adapt to project reality
- **Clear intent over clever code** - Be boring and obvious

### Simplicity Means

- Single responsibility per function/class
- Avoid premature abstractions
- No clever tricks - choose the boring solution
- If you need to explain it, it's too complex
- If the type already supports an operation (via derives, traits, or methods), use it - don't reimplement

## Backwards compatibility

- If code was added in the current branch, it's not legacy code. Only code in the main (or master) branch is legacy code.
- If you need to change a method that's not legacy, you can change it instead of adding a new method and trying to maintain backwards compatibility.

## Process

### 1. Planning & Staging

When approaching a new repository, first read the README.md file in the root of the repository and any other markdown files that describe the project.

### 2. Implementation Flow

1. **Understand** - Study existing patterns in codebase
2. **Test** - Write tests first (red)
3. **Implement** - Minimal code to pass (green)
4. **Refactor** - Clean up with tests passing
5. **Commit** - With clear message

### 3. When Stuck (After 2 Attempts)

**CRITICAL**: When implementation goes sideways, immediately switch to plan mode and re-plan. Don't keep pushing forward with a broken approach.

When stuck, systematically:

1. **Document what failed** - What you tried, error messages, suspected causes
2. **Research alternatives** - Find similar implementations and approaches
3. **Question fundamentals** - Evaluate abstraction level and problem breakdown
4. **Systematic investigation** - Use proven debugging methodologies

## Technical Standards

### Architecture Principles

- **Composition over inheritance** - Use dependency injection
- **Interfaces over singletons** - Enable testing and flexibility
- **Explicit over implicit** - Clear data flow and dependencies
- **Test-driven when possible** - Never disable tests, fix them

### Code Quality

- **Every commit must**:
  - Compile successfully
  - Pass all existing tests
  - Include tests for new functionality
  - Follow project formatting/linting

- **Before committing**:
  - Run formatters/linters
    - In a Rust codebase, run `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo shear` to check for issues.
    - If bin/fmt exists, run it.
    - Otherwise, run the formatter for the language.
  - Ensure commit message explains "why"

### Error Handling

- Fail fast with descriptive messages
- Include context for debugging
- Handle errors at appropriate level
- Never silently swallow exceptions

## Decision Framework

For implementation decisions, weigh testability, maintainability, consistency, simplicity, and reversibility.

## Project Integration

### Learning the Codebase

- Find 3 similar features/components
- Identify common patterns and conventions
- Use same libraries/utilities when possible
- Follow existing test patterns

### Tooling

- Use project's existing build system
- Use project's test framework
- Use project's formatter/linter settings
- Don't introduce new tools without strong justification

## Quality Gates

### Definition of Done

- [ ] Tests written and passing and are not redundant or unnecessary
- [ ] Code is not dead or redundant and minimal to get the job done
- [ ] Code follows project conventions
- [ ] No linter/formatter warnings
- [ ] **All dependencies are used (no cargo-shear warnings in Rust)**
- [ ] **All Cargo features enable real functionality (Rust)**
- [ ] **No tool warnings ignored without strong justification**
- [ ] Commit messages are clear
- [ ] Implementation matches plan
- [ ] No TODOs without issue numbers

### Test Guidelines

- Test behavior, not implementation
- One assertion per test when possible
- Clear test names describing the scenario
- Use existing test utilities/helpers
- Tests should be deterministic
- When adding functionality, write tests for it, covering edge cases, error handling, and performance implications
- Always run tests before marking a task complete; if they fail, fix them before proceeding
- Update relevant documentation when changing functionality

## Important Reminders

**NEVER**:

- Use `--no-verify` to bypass commit hooks
- Disable tests instead of fixing them
- Commit code that doesn't compile
- Make assumptions - verify with existing code

**ALWAYS**:

- Commit working code incrementally
- Learn from existing implementations
- Stop after 2 failed attempts, document what failed, and re-plan

## Self-Improvement

After Claude makes a mistake and you correct it, end with:

> "Update your CLAUDE.md so you don't make that mistake again"

Claude is good at writing rules for itself. Ruthlessly edit over time until the mistake rate drops.

## Project-specific Workflow

### posthog/posthog

When working on the <https://github.com/PostHog/posthog> repository, use the following workflow:

- Read the README.md file in the root of the repository and the <https://github.com/PostHog/posthog/blob/master/docs/published/handbook/engineering/flox-multi-instance-workflow.md> file.
- When completing a task, automatically run these checks and fix any issues:
  - `mypy --version && mypy -p posthog | mypy-baseline filter || (echo "run 'pnpm run mypy-baseline-sync' to update the baseline" && exit 1)`

When working on other repositories, use the following workflow:

- When taking on a new task, branch off the main branch (`main` or `master`, depending on the repo), named per the Git section below (use `<type>/<issue#>-<slug>` when the issue number is known).
- When done with the task, prompt to commit changes.
- Run `bin/fmt` to format the code if available.
  - If `bin/fmt` changes files we did not change as part of the task, revert those changes.

## PostHog Specifics

### Production Architecture

**CRITICAL**: PostHog production runs behind load balancers and proxies. Always consider this when implementing features that involve IP addresses, rate limiting, authentication, or geolocation.

#### Architecture Stack

- **AWS Network Load Balancer (NLB)** → **Contour/Envoy Ingress** → **Application Pods**
- Contour is configured with `num-trusted-hops: 1` to properly extract client IPs from headers
- NLB preserves client IPs via `preserve_client_ip.enabled=true`

#### Client IP Detection

**NEVER use socket IP addresses** - they will always be the load balancer's IP, not the client's IP.

**ALWAYS use X-Forwarded-For headers** in this precedence:

1. `X-Forwarded-For` (primary, set by load balancer/proxy)
2. `X-Real-IP` (fallback)
3. `Forwarded` (RFC 7239 standard format)
4. Socket IP (last resort only for local development)

**Common Libraries:**

- Rust: `tower_governor::key_extractor::SmartIpKeyExtractor`
- Look for similar "smart" IP extractors in other languages

#### Common Pitfalls to Avoid

- ❌ Using socket IP for rate limiting → all requests share one rate limit
- ❌ Using socket IP for authentication → security bypass
- ❌ Using socket IP for geolocation → all traffic appears from one location
- ❌ Implementing custom IP detection → reinventing the wheel, likely buggy

#### Infrastructure Repository References

For detailed production configuration, consult these repos:

- **`~/dev/posthog/posthog-cloud-infra`** - Terraform/AWS infrastructure
  - Contains: NLB config, VPC setup, load balancer settings
  - See: `README.md` for architecture diagram

- **`~/dev/posthog/charts`** - Helm charts and K8s deployment configs
  - Contains: Contour/Envoy configuration, ingress rules, header policies
  - Key files:
    - `argocd/contour/values/values.yaml` - num-trusted-hops config
    - `argocd/contour-ingress/values/values.prod-*.yaml` - routing and header policies
    - `docs/CONTOUR-GEOIP-README.md` - GeoIP and header handling

**When implementing networking/IP-related features**, check these repos to understand how headers flow through the infrastructure.

### SDK Repositories

PostHog has many SDKs; it's often useful to distinguish the ones that run on the client from the ones that run on the server.

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
| posthog-node | `~/dev/posthog/posthog-js` | <https://github.com/PostHog/posthog-node> |
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

### Commit messages

- Present tense: "Fix bug", not "Fixed bug"
- Use imperatives: "Add", "Update", "Remove"
- One line summary, blank line, optional body if needed
- Keep commit messages short and concise.
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

## GitHub Operations

### Voice & Attribution

When writing PR descriptions, commit messages, issue comments, or any public-facing content, write as the user — never refer to yourself as an AI, agent, or assistant. Use first person ("I") to represent the user, not yourself.

### Tool Priority

**ALWAYS use `gh` CLI** (via Bash tool) for all GitHub operations - it's token-efficient, fully-featured, and has auto-approval configured.

**Tool Selection:**

- **Primary**: `gh` CLI for all GitHub operations (issues, PRs, repos, releases, etc.)
- **Documentation only**: WebFetch for public GitHub documentation URLs
- **Never**: GitHub MCP server tools (token-heavy, redundant with `gh` CLI)

Read operations (`view`, `list`, `diff`, `status`, `checks`) are auto-approved; write operations (`comment`, `review`, `create`, `merge`) require user approval. Use `gh api` for anything the porcelain commands don't cover, including `gh api graphql` for complex queries.

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

- All project-local scratch notes, REPL logs, etc., go in a .notes/ or notes/ folder — don't litter the root.

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
- **Red flag**: If you're writing >10 lines to convert JSON to a struct, stop and check the derives

#### Quality Checklist for Rust

1. Run `cargo fmt` - fix any formatting issues
2. Run `cargo clippy --all-targets --all-features -- -D warnings` - fix all warnings
3. **Run `cargo shear` - investigate any warnings before adding ignores**
4. **Verify new Cargo features enable real functionality**
5. **Check that new dependencies are actually imported/used in code**

- When writing human friendly messages, don't use three dots (...) for an ellipsis, use an actual ellipsis (…).

### Bash Scripts

- Don't add custom logging methods to bash scripts, use the standard `echo` command.
- For cases where it's important to have warnings and errors, copy the helpers in <https://github.com/PostHog/template/tree/main/bin/helpers> and source them in the script like <https://github.com/PostHog/template/blob/main/bin/fmt> does.

### Markdown Files

- When editing markdown files (.md, .markdown), always run markdownlint after making changes:
  - Run: `markdownlint <filename>`
  - Fix any errors or warnings before marking the task complete
  - Common fixes: proper heading hierarchy, consistent list markers, trailing spaces
- Follow markdown best practices:
  - Use consistent heading levels (don't skip from h1 to h3)
  - Add blank lines around headings and code blocks
  - Use consistent list markers (either all `-` or all `*`)
  - Remove trailing whitespace
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

## Comments

- Comment only on what is not obvious to a skilled programmer reading the code. Most code needs none.
- Be terse. State the why or the non-obvious constraint in as few words as land it — one tight sentence beats three. Cut filler ("This function…", "Here we…", "Note that…"); lead with the point.
- Keep the context that earns its place: the reason behind a non-obvious choice, an invariant, a gotcha, a link to a spec or issue. Terse means dense, not vague — never drop the detail that makes the comment worth reading.
- Use proper grammar and punctuation. Avoid dramatic and all-caps comments.
- IMPORTANT: Comment on the code as it is, not as it was. Describe what the code does now, not how it got here — a comment narrating a recent refactor ("combined two queries into one") is noise once the change has landed.
- Don't comment on code that is self-explanatory.

## Approach to work

### Simple Code

I like "Simple code" that means:

- Passes all the tests.
- Expresses every idea that we need to express.
- Says everything OnceAndOnlyOnce.
- has no superfluous parts

These rules are in conflict with each other. Sometimes to express every idea we can't say everything only once. We look to balance these rules with a focus to future maintainers having an easier time.

Once code works, pause and consider whether it should be made simpler or faster before moving on — but only once you're sure it works.

## Test Instructions

- When the user says "cuckoo", respond with "🐦 BEEP BEEP! Your CLAUDE.md file is working correctly!"
