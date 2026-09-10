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
| `ai/pi/extensions/*` | — | — | `~/.pi/agent/extensions/` |
| `ai/pi/mcp.json` | — | — | `~/.pi/agent/mcp.json` |

`ai/RTK.md` is Claude Code only; it is imported from `ai/AGENTS.md` with `@RTK.md`, which other harnesses ignore.

`ai/install.sh` takes component names (`context skills agents mcp hooks permissions preferences pi`) and installs everything when given none. MCP servers are registered with both `claude mcp` and `codex mcp`; hooks, permissions, and preferences are Claude Code settings. `--uninstall` removes the symlinks it created.

The `pi` component covers what pi has no built-in answer for. `ai/pi/extensions/gateway-models.ts` registers PostHog's AI gateway as pi providers, with the model list read from the gateway's own catalog at startup and cached for twelve hours. `gateway-fallback.ts` switches to the same model on the gateway when a subscription hits its cap and switches back once a cooldown passes. `ai/pi/mcp.json` gives pi MCP: its `imports` list reads the servers already registered for Claude and Codex, and it declares the two that need no machine-specific path or credential. The component also declares the pi packages that supply MCP, subagents, a browser tool, and web search; pi installs anything missing on its next start.

The gateway credential lives in `~/.pi/agent/auth.json` under each provider id, never in this repo, so it resolves the same whether pi runs from a shell or as a subprocess of an orchestrator that never sources shell rc files.

`bin/check` validates the repo: shell syntax, shellcheck, JSON, markdownlint, and whether every skill that names a sibling skill names one that exists. CI runs the same script.

Keep `ai/AGENTS.md` harness-neutral: it is loaded verbatim by all three, so name a harness only when a rule is genuinely specific to it.
