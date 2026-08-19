# Dotfiles Project

This repository manages shell configuration, aliases, completions, and utility scripts.

## Shell Configuration

`~/.zshrc` is a symlink to `zsh/zshrc.symlink` (created by `script/bootstrap`). All interactive shell configuration lives in this file.

Key files:

- `zsh/zshrc.symlink` — interactive shell: tool managers, PATH, env vars, functions
- `zsh/zshenv.symlink` — all contexts: Homebrew, `~/.local/bin`, Cargo
- `zsh/zprofile.symlink` — login shells: OrbStack
- `zsh/aliases.zsh` — shell aliases
- `zsh/*-completion.zsh` — tab completion scripts
- `~/.secrets` — credentials (not tracked; sourced by `zshrc.symlink`)

## Agent configuration

`ai/` holds one set of instructions and skills shared by every harness (Claude Code, Codex, pi). `ai/install.sh` links them into place — nothing is copied, so repo edits apply immediately:

| Source | Claude Code | Codex | pi |
| --- | --- | --- | --- |
| `ai/AGENTS.md` | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.pi/agent/AGENTS.md` |
| `ai/AGENTS.posthog.md` | `~/dev/posthog/CLAUDE.md` | `~/dev/posthog/AGENTS.md` | either of those |
| `ai/skills/*` | `~/.claude/skills/` | `~/.codex/skills/` | `~/.agents/skills/` |
| `ai/agents/*` | `~/.claude/agents/` | — | — |

`ai/RTK.md` is Claude Code only; it is imported from `ai/AGENTS.md` with `@RTK.md`, which other harnesses ignore.

`ai/install.sh` takes component names (`context skills agents mcp hooks permissions preferences`) and installs everything when given none. MCP servers are registered with both `claude mcp` and `codex mcp`; hooks, permissions, and preferences are Claude Code settings. `--uninstall` removes the symlinks it created.

Keep `ai/AGENTS.md` harness-neutral: it is loaded verbatim by all three, so name a harness only when a rule is genuinely specific to it.

## Skills sync

Every skill under `ai/skills/rs-*/` is mirrored in the PostHog skills store under the same name. The dotfiles copy is the source of truth.

A GitHub Action (`.github/workflows/sync-skills.yml`) syncs the store on every push to `main` that touches `ai/skills/**` or the script itself. The same logic lives in `bin/sync-skills` for ad-hoc local runs (and `bin/sync-skills --dry-run` to preview). Both are push-only, idempotent, and authenticate with `POSTHOG_PERSONAL_API_KEY` scoped to `llm_skill:read` + `llm_skill:write`. Locally the script reads `.env` at the repo root (gitignored); in CI the env vars come from the repo's GitHub Actions secrets.

Adding a new skill: drop it under `ai/skills/rs-<slug>/` and push — the sync creates it on first run. Editing an existing skill: change the local files; the next push publishes a new version against the latest `base_version`. Bundled files under `scripts/`, `references/`, or `assets/` are picked up automatically (files named `test-*` are excluded from the published bundle).

The same skills can be pushed to more than one project (e.g. a second account with its own key) by adding numbered targets. Target 1 is the unsuffixed `POSTHOG_PERSONAL_API_KEY` / `POSTHOG_PROJECT_ID` / `POSTHOG_HOST`; target 2 is `…_2`, target 3 `…_3`, and so on. A numbered target is synced only when both its `POSTHOG_PERSONAL_API_KEY_N` and `POSTHOG_PROJECT_ID_N` are set (host defaults to US cloud), so the extra targets are opt-in and the workflow is unchanged until the `_2` secret/var are added.
