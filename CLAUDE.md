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

## Skills sync

Every skill under `ai/skills/rs-*/` is mirrored in the PostHog skills store under the same name. The dotfiles copy is the source of truth.

A GitHub Action (`.github/workflows/sync-skills.yml`) syncs the store on every push to `main` that touches `ai/skills/**` or the script itself. The same logic lives in `bin/sync-skills` for ad-hoc local runs (and `bin/sync-skills --dry-run` to preview). Both are push-only, idempotent, and authenticate with `POSTHOG_PERSONAL_API_KEY` scoped to `llm_skill:read` + `llm_skill:write`. Locally the script reads `.env` at the repo root (gitignored); in CI the env vars come from the repo's GitHub Actions secrets.

Adding a new skill: drop it under `ai/skills/rs-<slug>/` and push — the sync creates it on first run. Editing an existing skill: change the local files; the next push publishes a new version against the latest `base_version`. Bundled files under `scripts/`, `references/`, or `assets/` are picked up automatically (files named `test-*` are excluded from the published bundle).
