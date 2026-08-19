# PostHog Workflow

Loaded for any session under `~/dev/posthog`. Universal guidance lives in `~/dev/dotfiles/ai/AGENTS.md`.

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
