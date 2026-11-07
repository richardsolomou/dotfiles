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

`ai/` holds one set of instructions and skills shared by every harness (Claude Code, Codex, opencode). `ai/install.sh` links them into place — nothing is copied, so repo edits apply immediately:

| Source | Claude Code | Codex | opencode |
| --- | --- | --- | --- |
| `ai/AGENTS.md` | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | — |
| `ai/AGENTS.posthog.md` | `~/dev/posthog/CLAUDE.md` | `~/dev/posthog/AGENTS.md` | either of those |
| `ai/skills/*` | `~/.claude/skills/` | `~/.codex/skills/` | `~/.agents/skills/` |

`ai/RTK.md` is Claude Code only; it is imported from `ai/AGENTS.md` with `@RTK.md`, which other harnesses ignore.

`ai/install.sh` takes component names (`context skills mcp plugins hooks permissions preferences`) and installs everything when given none. MCP servers are registered with both `claude mcp` and `codex mcp`; plugins, hooks, permissions, and preferences are Claude Code settings. `--uninstall` removes the symlinks it created.

`bin/check` validates the repo: shell syntax, shellcheck, JSON, markdownlint, each skill's frontmatter name against its directory, that every skill a SKILL.md names exists, and the `test-*` scripts under `ai/skills/`. CI runs the same script.

Keep `ai/AGENTS.md` harness-neutral: it is loaded verbatim by all three, so name a harness only when a rule is genuinely specific to it.
