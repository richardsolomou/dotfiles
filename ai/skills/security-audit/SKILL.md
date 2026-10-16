---
name: security-audit
description: >
  Focused security audit of code, calibrated to surface real exploitable bugs and suppress
  theoretical findings. Use when the user asks to "audit", "security-audit",
  "find vulnerabilities", "check for IDOR/SSRF/XSS/injection", or wants a security
  review of a file, directory, branch diff, or PR. Covers access control, injection,
  auth/secrets, sensitive data, business logic, web boundary, and AI agent/LLM trifecta
  risks. Produces calibrated findings with data flow, exploit request, fix, and
  confidence — no theoretical or defense-in-depth nits.
---

# Security Audit

Find real, demonstrable vulnerabilities — not theoretical concerns, best-practice nudges, or style nits.

## Input

Audit target: $ARGUMENTS

Resolve the target once and pin branch or PR reviews to immutable base and head SHAs, printed in the report:

- Empty: the complete local working state against its real parent. Use `adversarial-review`'s local working-tree packet so staged, unstaged, and untracked changes share one fingerprint.
- A branch name: its remote tip and merge base, audited as a commit range without dirty working-tree files.
- A PR number or URL: `git diff <merge-base-sha> <head-sha>` plus commit-addressed file contents.
- A file or directory path: its contents.
- A free-form description: locate the relevant files, then audit those.

Establish how the caller authenticates and how the tenant is derived, which inputs are user-controlled, and whether the code is reachable from a public, authenticated, or internal route. For agent code, also establish the exposed tools and their credentials, the untrusted content reaching the model, and how output is rendered. Ask only when two plausible answers would materially change the findings; otherwise state your interpretation and proceed. If authoritative reachability or input-control evidence is unavailable, report that coverage as blocked rather than filing assumption-dependent findings.

## Calibration

- Report a finding only if you can trace user-controlled input from a concrete source (request body/query/header, queue payload, upload, retrieved document, tool output) to a concrete sink (DB query, shell, response, filesystem, outbound HTTP, agent tool call) with the missing control identified.
- If you cannot construct a specific exploit request, it is not a finding.
- Framework protections (typed DRF serializer fields, ORM parameterization, template auto-escaping, parameterized cursors) count unless this code bypasses them.
- Rate limiting, WAFs, monitoring, and defense-in-depth suggestions are not findings — except brute-forceable OTP/TOTP verification, where missing rate limiting is the bug.
- Dead code, code behind disabled flags, and code unreachable from any route or task are out of scope.
- Two real findings beat twelve speculative ones.

## Where real bugs hide

Cover the standard vulnerability classes. These are the patterns audits of this codebase repeatedly miss.

### Access control — usually the highest impact

- **Auto-generated `PrimaryKeyRelatedField` from undeclared serializer fields — the single most common real bug.** A FK in `Meta.fields` that isn't declared explicitly gets `queryset=Model.objects.all()` with no tenant filter, and it doesn't appear in the file. Grep `Meta.fields` for FKs (`owner`, `created_by`, `linked_insight_id`, `saved_query_id`, `feature_flag`, `dashboard`, `cohort`) not redeclared and not in `read_only_fields`.
- **Mass assignment via an enumerated `fields` list that missed one.** Every FK or status/state field in `Meta.fields` must be in `read_only_fields` or have a `validate_<field>` that re-scopes by `self.context["get_team"]()`. Watch `is_staff`, `team`, `organization`, `owner`, `created_by`, `executed_at`, `status`, `import_config`.
- **Permission asymmetry across viewset methods.** A check in `create()` doesn't propagate to `update`, `partial_update`, or `@action` methods; `@action` methods can also bypass `get_queryset()`. Audit each method as its own endpoint (e.g. `CanEditFeatureFlag` enforced in `create`, missing on `update`).
- **`scope_object` / RBAC asking about the wrong resource.** When a viewset edits resource A but the protected thing is B (a survey's linked feature flag), RBAC approves writes to B. Trace `scope_object` to the protected resource.
- **IDOR / tenant crossover.** Every user-scoped queryset filters by a tenant ID from the session, never request input — including slugs, UUIDs, share codes, and signed tokens. Bulk endpoints must re-check every ID; exports must apply per-row filtering. Status-code differences (201 vs 500, 200 vs 404) across tenants are an enumeration oracle with sequential PKs — no data egress needed.
- **Default-allow custom permission classes** that return `True` when no rule matches a new resource type.
- **Exposed internal surfaces:** internal/admin/debug/test endpoints on the public vhost, `DEBUG`- or env-guarded routes reachable in prod, deprecated `v1` endpoints missing controls added to `v2`, and verb gaps (`HEAD`/`OPTIONS`, `X-HTTP-Method-Override`).
- **Cross-language exfil via writable JSON config.** When a serializer writes a blob consumed by a Rust, Node, or Temporal worker, follow the field into the consumer. User-writable URLs or headers paired with server-decrypted credentials in the same config let the consumer send the secret to an attacker's URL; the Django side looks fine in isolation.

### Injection

- **SQL identifiers.** Parameter binding doesn't protect table/column/schema names. Common in warehouse and batch-export destinations, with partial coverage the failure mode (one destination sanitises identifiers, the new one doesn't). `psycopg.sql.SQL(f"…{name}")` is the "trust this string" constructor — the opposite of `sql.Identifier()`.
- **HogQL or ClickHouse SQL** built by concatenating user values.
- **SSRF — identify the load-bearing control.** Where an egress proxy (Smokescreen) is on the path, it is the defense and app-layer `is_url_allowed`/`should_block_url` checks are defense-in-depth; don't flag a missing app-layer check without establishing the proxy is absent. Do flag self-hosted paths and workers that bypass it.

### Authentication and secrets

- **Default crypto keys with no production guard**, e.g. a placeholder `ENCRYPTION_SALT_KEYS` in `posthog/settings/access.py` with a comment-only "override in prod". The finding is the missing `if not DEBUG and value == DEFAULT: raise` that mirrors the existing `SECRET_KEY` guard.
- Webhook secrets that are per-integration and the integration itself user-writable, so the attacker controls the verification key.
- The usual JWT, OAuth/OIDC (`redirect_uri` matching, `state`, PKCE, code reuse, scope expansion, pre-creation account-link hijack), reset-token, MFA, and session-lifecycle classes.

### Web boundary

- **Path-prefix denylists vs router slash policy.** `startswith` denylists such as `IMPERSONATION_BLOCKED_PATHS` with trailing slashes are bypassed when the DRF router accepts both forms (`trailing_slash = r"/?"`).
- Host-header-derived absolute URLs in reset or verification emails, and `postMessage` origin checks on embedded surfaces (toolbar, embedded dashboards, OAuth popups).

### Business logic

Race conditions on quota, balance, or uniqueness (read-then-write without `select_for_update` or a constraint), including account merge, invite accept, MFA enrollment, and OAuth linking; replayable payments or invites; workflow step skipping; unbounded `limit`/`offset`; decompression bombs; and expensive pre-auth work.

### AI agents and LLM sandboxes

An agent with private-data access, exposure to attacker-controlled content, and the ability to act externally is one indirect injection away from exfiltration. Enumerate every untrusted source reaching the context: tool and MCP outputs, retrieved documents, model-written memory, MCP tool descriptions, filenames, commit messages, and PR titles.

- **Tool-call authorization is the most frequent real bug.** Tools must enforce the end user's authorization, not a service credential; ID arguments must be re-checked server-side; destructive or externally visible tools need fresh per-call confirmation in the UI.
- **Only these injection impact paths count:** a side-effecting tool call, exfiltration through rendered output (markdown images, link unfurls, auto-loaded resources), or exfiltration through an outbound tool. Injection that only changes tone or refusals is not a finding.
- **Sandboxes** need process, network (block link-local metadata, loopback, internal ranges), filesystem, resource, secret, and per-tenant isolation; inspect the image, not just the runtime.

## Methodology

For each candidate:

1. **Trace the data flow** from source to sink with `file:line` per hop, following it across process and language boundaries.
2. **Name the missing control.**
3. **Write the exploit request** — method, URL, headers, body — and state the impact in one sentence.
4. **Confirm reachability** — the route is registered, the flag is on for some tenant, a real entrypoint calls it.

If any step fails, drop the finding.

## Reproducer tests (approved fix rounds)

The initial audit is read-only: verify with existing tests or non-persistent probes and leave no files behind. Once the user approves a fix, write a test per approved finding first, beside the existing tests for that code. It exercises the real entrypoint, asserts the secure behavior, and must fail against the current code for the expected reason before the fix — for IDOR, two tenants with user A receiving 403/404 on B's resource; for injection, the payload with no dangerous side effect. If a finding can't be expressed as an automated test, say why.

## After reporting

For local audits, ask which findings to fix ("all", "#1 and #3", "skip"). Don't fix without approval. Apply the minimal fix per approved finding, confirm its reproducer passes, run adjacent tests, and report what was fixed and verified.

## Output format

Start with `N findings: X critical, Y high, Z medium, W low.` (say so plainly if zero), then for each:

```text
## Finding N — <title>
- Severity: Critical | High | Medium | Low
- Category: <e.g., IDOR, SQL injection, SSRF>
- Location: path/to/file.py:LINE (additional refs as needed)
- Description: 1–3 sentences on what is wrong.
- Data flow:
  1. Source — path/to/file.py:LINE (what comes in)
  2. ...
  3. Sink — path/to/file.py:LINE (what happens with it)
- Exploit:
    POST /api/projects/123/foo/
    {"target_id": 999}    # 999 belongs to tenant B; attacker is in tenant A
  Impact: <one sentence>
- Fix: minimal framework-idiomatic change (e.g., "filter the queryset by self.context['get_team']().id").
- Confidence: High | Medium | Low — and what assumption would have to break for this to be wrong.
```

## Severity rubric

- **Critical** — Unauthenticated RCE; cross-tenant read or write; full account takeover; mass PII exfiltration; sandbox escape to host; indirect injection driving a destructive cross-tenant tool call without confirmation.
- **High** — Authenticated RCE; IDOR on sensitive resources; SQLi; privilege escalation to admin; auth bypass; agent tool callable with another tenant's IDs; injection exfiltrating conversation contents via auto-fetched output.
- **Medium** — Stored XSS; SSRF reaching the internal network (including from a sandbox); sensitive disclosure to authenticated peers; CSRF on important state changes; auth tokens in logs; over-scoped agent service token.
- **Low** — Reflected XSS needing crafted interaction; verbose errors; missing hardening with no demonstrated impact; a non-load-bearing sandbox limit.

If unsure between two levels, choose the lower and explain in `Confidence`.

## Not findings

- Generic "add input validation", "add rate limiting", "add security headers", or "add human-in-the-loop" without a specific bypass or a reachable destructive action.
- Dangerous-looking primitives called with hardcoded constants.
- Library upgrades without a CVE affecting how the library is used here.
- Prompt injection with no downstream sink, unhelpful or off-brand model output, and hallucinations framed as security issues.
- Anything you would not stake your reputation on.
