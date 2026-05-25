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

Every skill under `ai/skills/richard-*/` is mirrored in the PostHog skills store under the same name. The dotfiles copy is the source of truth — when editing a skill here, also publish the change to the store via the PostHog MCP (`llma-skill-update` with the matching `base_version`, or the per-file primitives for bundled scripts). When adding a new `richard-`-prefixed skill, follow the same pattern.
