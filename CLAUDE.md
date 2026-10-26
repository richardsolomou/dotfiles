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
| `ai/t3code/provider-instances.json` | merged into `~/.t3/userdata/settings.json` | | |

`ai/RTK.md` is Claude Code only; it is imported from `ai/AGENTS.md` with `@RTK.md`, which other harnesses ignore.

`ai/install.sh` takes component names (`context skills mcp plugins hooks permissions preferences t3code`) and installs everything when given none. MCP servers are registered with both `claude mcp` and `codex mcp`; plugins, hooks, permissions, and preferences are Claude Code settings. `--uninstall` removes the symlinks it created.

The `t3code` component declares twins of the Claude and Codex subscriptions that route to the homelab CLIProxyAPI (`cpa_`): T3 Code pins a thread to the driver and CLI home it started on, so a twin sharing both — with other credentials instead of the subscription's — is what the model picker will offer inside a running thread once a usage limit hits. Its settings cannot be symlinked (T3 Code saves through a temp file plus rename), so the component merges per instance id and writes the keys into T3 Code's own secret store.

`CLIPROXY_API_KEY`, `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` live in `$ZSH/.env`, which is gitignored and copied to each host by hand. They connect a host to the homelab CLIProxyAPI at `https://ai.ras.sh`; `ai/install.sh` writes them into the `cpa_` twins, and `zshrc` and `fish/cliproxy.fish` wrap `claude` and `codex` with them without exporting them.

`bin/check` validates the repo: shell syntax, shellcheck, JSON, markdownlint, each skill's frontmatter name against its directory, that every skill a SKILL.md names exists, and the `test-*` scripts under `ai/skills/`. CI runs the same script.

Keep `ai/AGENTS.md` harness-neutral: it is loaded verbatim by all three, so name a harness only when a rule is genuinely specific to it.
