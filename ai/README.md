# AI Settings

One set of instructions, skills, and MCP servers, shared by every agent harness: Claude Code, Codex, and opencode.

- `AGENTS.md` — global instructions for all harnesses
- `AGENTS.posthog.md` — extra rules loaded only under `~/dev/posthog`
- `RTK.md` — rtk usage notes, imported by Claude Code only
- `skills/` — local skills shared by the installed agent harnesses

## Installation

```sh
./install.sh                    # everything
./install.sh context skills     # only these components
./install.sh --uninstall        # remove the symlinks
./install.sh --help             # list components
```

Everything is symlinked, so edits here take effect without reinstalling. Adding a skill or renaming one needs a re-run; the script also prunes symlinks left behind by skills it no longer manages. Skills reference their own scripts through `~/.agents/skills/<skill>/scripts/`, the cross-harness directory every install populates.

## PostHog skills store

`bin/sync-skills` publishes every local `skills/<name>/` directory to the PostHog skills store as `rs-<name>`. Local names stay unchanged; references to sibling skills in the published bodies use the store prefix. It updates changed skills, archives `rs-` skills that no longer have a local directory, and leaves other store skills alone. Run `bin/sync-skills --dry-run` to inspect changes. The script reads `POSTHOG_PERSONAL_API_KEY` from the environment or the repo root `.env`; `POSTHOG_PROJECT_ID` and `POSTHOG_HOST` are optional. Pushes to `main` that change skills run the same sync through GitHub Actions.

## Vendored skills

`skills/typesafe-ai/` is a verbatim copy of [typesafe-ai/skills](https://github.com/typesafe-ai/skills) (MIT, `skills/typesafe-ai/`), vendored rather than installed as a Claude Code plugin so Codex and opencode get it too. Update it by re-copying upstream's `SKILL.md`, not by editing in place.

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

The Slack MCP uses `slack-mcp-server@1.3.0` and reads credentials from the gitignored root `.env`. This keeps tokens out of Claude and Codex configuration while the shared installer registers the same launcher for both harnesses. It exposes channel listing, message history, thread replies, message search, and `saved_list` for reading Slack Later items.

The existing `SLACK_MCP_XOXP_TOKEN` OAuth token supports message access. Reading Later items requires both `SLACK_MCP_XOXC_TOKEN` (browser token) and `SLACK_MCP_XOXD_TOKEN` (the browser's `d` cookie). Add both to `.env`; the launcher uses the browser credentials instead of OAuth when they are present. A partial pair stops startup. Keep the OAuth token for the installer's registration check. Restart the Slack MCP connection after changing credentials or enabled tools.

Create a replacement Slack user token with the scopes required by `slack-mcp-server`, add it to `.env`, restrict the file, then register or refresh the MCP configuration:

```sh
chmod 600 .env
ai/install.sh mcp
```

Revoke the old token after the new launcher has been verified with both clients.
