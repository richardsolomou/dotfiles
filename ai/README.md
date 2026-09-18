# AI Settings

One set of instructions, skills, and MCP servers, shared by every agent harness: Claude Code, Codex, and opencode.

- `AGENTS.md` — global instructions for all harnesses
- `AGENTS.posthog.md` — extra rules loaded only under `~/dev/posthog`
- `RTK.md` — rtk usage notes, imported by Claude Code only
- `skills/` — local skills shared by the installed agent harnesses
- `t3code/` — T3 Code provider instances that route to the gateway
- `opencode/` — opencode config: the gateway's open-weight models

## Installation

```sh
./install.sh                    # everything
./install.sh context skills     # only these components
./install.sh --uninstall        # remove the symlinks
./install.sh --help             # list components
```

Everything is symlinked, so edits here take effect without reinstalling. Adding a skill or renaming one needs a re-run; the script also prunes symlinks left behind by skills it no longer manages. Skills reference their own scripts through `~/.agents/skills/<skill>/scripts/`, the cross-harness directory every install populates.

## Telegram MCP

The Telegram MCP runs locally from a pinned commit of [chigwell/telegram-mcp](https://github.com/chigwell/telegram-mcp). Its launcher forces the MCP tool surface to read-only and disables voice transcription, while Telegram credentials stay in the gitignored root `.env` instead of the Claude or Codex configuration.

Create an application at [my.telegram.org/apps](https://my.telegram.org/apps), put `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` in `.env`, and authorize a session from an existing Telegram device:

```sh
ai/mcp/telegram-mcp.sh login
```

Put the resulting `TELEGRAM_SESSION_STRING` in `.env`, restrict the file, and register the MCP for each installed harness:

```sh
chmod 600 .env
ai/install.sh mcp
```

The session string still has the authority of the Telegram account even though the exposed MCP tools are read-only. Revoke the `Telegram MCP` session under Telegram's **Settings → Devices** if the credential is ever exposed. The server does not restrict reads to particular chats.

## Slack MCP

The Slack MCP uses `slack-mcp-server@1.3.0` and reads `SLACK_MCP_XOXP_TOKEN` from the gitignored root `.env`. This keeps the token out of Claude and Codex configuration while the shared installer registers the same launcher for both harnesses. It exposes only channel listing, message history, thread replies, and message search.

Create a replacement Slack user token with the scopes required by `slack-mcp-server`, add it to `.env`, restrict the file, then register or refresh the MCP configuration:

```sh
chmod 600 .env
ai/install.sh mcp
```

Revoke the old token after the new launcher has been verified with both clients.

## T3 Code

T3 Code locks a thread to the provider driver and CLI home it started on, so the only way to keep working past a usage limit without losing the conversation is a second instance of the *same* driver and home with different credentials. `t3code/provider-instances.json` declares those twins — `phaig_claude`, `phaig_codex` and `phaig_opencode` — and `install.sh t3code` writes them into `~/.t3/userdata/settings.json`, merging per instance id so anything configured by hand on the host survives.

Neither the settings nor the credentials can be symlinked. T3 Code saves settings through a temp file plus rename, which would replace a symlink with a regular file, and sensitive environment values live in `~/.t3/userdata/secrets` as `provider-env-<base64url instance>-<base64url variable>.bin`, mode 0600. Every environment entry marked `valueRedacted` is filled from `POSTHOG_GATEWAY_KEY`, read from the environment, then from `$ZSH/.env`, then from the copy already in that secret store.

Paths in that file may start with `~/`; the installer expands them, because the opencode driver takes `binaryPath` literally and the T3 Code server does not inherit a login shell's PATH.

Codex reaches the gateway through a `[model_providers.posthog]` block appended to `~/.codex/config.toml` and selected per instance with `-c model_provider=posthog`; `-c` is used rather than `--profile` because only `-c`, `--config`, `--enable` and `--disable` reach the `codex exec` path. Claude needs no config file: `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` on the instance take precedence over the subscription login in the shared config directory, at the cost of claude.ai connectors in that instance.

Both twins are named `PH·Claude` and `PH·Codex` so the rail badge reads `PH`. The badge takes the first two characters of a single-word label, or the first character of each of the first two words, splitting on whitespace as well as `_` and `-` — so `PH-Codex` would badge as `PC`, and the middle dot is what keeps it one word. The accent color is PostHog orange, which also forces the badge to render on every instance rather than only when a driver has several. Ids prefixed `phaig_` are owned by this repo: the installer replaces them and drops ones the file no longer declares, along with their now-unused key files.

Subscription logins stay per host: run `claude auth login` and `codex login` on the machine. A headless host that only ever uses the gateway needs neither.

## opencode

`opencode/opencode.json` registers the gateway as an OpenAI-compatible provider and names the open-weight models it serves: GLM-5.2, GLM-5.3, GLM-5.3-Flash and Kimi K3. They reach no Claude or Codex instance — those enumerate models from their own CLIs, and the gateway returns `400 invalid request body` for Codex's freeform (`type: "custom"`) shell tool on every open-weight model while accepting it for OpenAI's. opencode sends plain function tools, which they accept, so `phaig_opencode` is where they are usable.

The key comes from `POSTHOG_GATEWAY_KEY` through opencode's own `{env:…}` substitution: inside T3 Code the instance supplies it, and from a shell `zshrc` exports it out of `$ZSH/.env`. `install.sh opencode` runs opencode's installer when the binary is missing, rather than taking the Homebrew formula: it keeps `~/.opencode/bin` as the path on every host, which is what `phaig_opencode` is configured with, and core trails the current release.
