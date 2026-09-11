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
| `ai/agents/*` | `~/.claude/agents/` | — | — |
| `ai/opencode/opencode.json` | — | — | `~/.config/opencode/opencode.json` |
| `ai/t3code/provider-instances.json` | merged into `~/.t3/userdata/settings.json` | | |

`ai/RTK.md` is Claude Code only; it is imported from `ai/AGENTS.md` with `@RTK.md`, which other harnesses ignore.

`ai/install.sh` takes component names (`context skills agents mcp hooks permissions preferences opencode t3code`) and installs everything when given none. MCP servers are registered with both `claude mcp` and `codex mcp`; hooks, permissions, and preferences are Claude Code settings. `--uninstall` removes the symlinks it created.

The `t3code` component declares gateway twins of the Claude and Codex subscriptions: t3code pins a thread to the driver and CLI home it started on, so a twin sharing both — with the gateway's credentials instead of the subscription's — is what the model picker will offer inside a running thread once a usage limit hits. Its settings cannot be symlinked (t3code saves through a temp file plus rename), so the component merges per instance id and writes the key into t3code's own secret store.

The `opencode` component installs opencode when a host is missing it and links the config that registers the gateway's open-weight models, which no Claude or Codex instance can reach.

The gateway credential comes from `POSTHOG_GATEWAY_KEY`, never from this repo. A machine that is already configured re-uses the key from t3code's secret store, so only the first run needs it set.

`bin/check` validates the repo: shell syntax, shellcheck, JSON, markdownlint, and whether every skill that names a sibling skill names one that exists. CI runs the same script.

Keep `ai/AGENTS.md` harness-neutral: it is loaded verbatim by all three, so name a harness only when a rule is genuinely specific to it.
