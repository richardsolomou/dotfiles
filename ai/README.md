# AI Settings

One set of instructions, skills, and MCP servers, shared by every agent harness: Claude Code, Codex, and opencode.

- `AGENTS.md` — global instructions for all harnesses
- `AGENTS.posthog.md` — extra rules loaded only under `~/dev/posthog`
- `RTK.md` — rtk usage notes, imported by Claude Code only
- `skills/` — local skills shared by the installed agent harnesses
- `t3code/` — T3 Code provider instances that route to the gateway or the homelab CLIProxyAPI
- `opencode/` — opencode config: the gateway's open-weight models

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

## PostHog issue discovery

Run `$posthog-issue-discovery` from any directory with access to a PostHog project. It sweeps every live product in the project, verifies up to 10 defects, traces each to its owning code where it can, and reports them as a ranked list with evidence and a coverage log. Discovery is read-only and writes nothing to disk; it ends by asking which defects to fix, and fixes them in the same conversation.

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

## T3 Code

T3 Code locks a thread to the provider driver and CLI home it started on, so the only way to keep working past a usage limit without losing the conversation is a second instance of the *same* driver and home with different credentials. `t3code/provider-instances.json` declares those twins — `phaig_claude`, `phaig_codex` and `phaig_opencode` for the PostHog gateway, `cpa_claude` and `cpa_codex` for CLIProxyAPI — and `install.sh t3code` writes them into `~/.t3/userdata/settings.json`, merging per instance id so anything configured by hand on the host survives.

Neither the settings nor the credentials can be symlinked. T3 Code saves settings through a temp file plus rename, which would replace a symlink with a regular file, and sensitive environment values live in `~/.t3/userdata/secrets` as `provider-env-<base64url instance>-<base64url variable>.bin`, mode 0600. Every environment entry marked `valueRedacted` is filled from the key for its instance prefix — `POSTHOG_GATEWAY_KEY` for `phaig_`, `CLIPROXY_API_KEY` for `cpa_` — read from the environment, then from `$ZSH/.env`; a host with neither keeps the copy already in that secret store.

Paths in that file may start with `~/`; the installer expands them, because the opencode driver takes `binaryPath` literally and the T3 Code server does not inherit a login shell's PATH.

Codex reaches each server through a `[model_providers.*]` block from `t3code/codex-*.toml`, appended to `~/.codex/config.toml` when missing and selected per instance with `-c model_provider=<name>`; `-c` is used rather than `--profile` because only `-c`, `--config`, `--enable` and `--disable` reach the `codex exec` path. Claude needs no config file: `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` on the instance take precedence over the subscription login in the shared config directory, at the cost of claude.ai connectors in that instance.

Both twins are named `PH·Claude` and `PH·Codex` so the rail badge reads `PH`. The badge takes the first two characters of a single-word label, or the first character of each of the first two words, splitting on whitespace as well as `_` and `-` — so `PH-Codex` would badge as `PC`, and the middle dot is what keeps it one word. The accent color is PostHog orange, which also forces the badge to render on every instance rather than only when a driver has several. The CPA twins use the same scheme in teal, badging as `CP`. Ids prefixed `phaig_` or `cpa_` are owned by this repo: the installer replaces them and drops ones the file no longer declares, along with their now-unused key files.

Subscription logins stay per host: run `claude auth login` and `codex login` on the machine. A headless host that only ever uses the gateway or CLIProxyAPI needs neither.

### CLIProxyAPI

CLIProxyAPI runs on the homelab NAS as a TrueNAS custom app (`cliproxyapi`, data in `/mnt/HDDs/Applications/cliproxyapi`) and holds the Claude and ChatGPT subscription logins centrally, so every machine shares one set of accounts and quotas. `routing.strategy: fill-first` drains the highest-`priority` account before moving to the next.

Clients reach it at `https://ai.ras.sh` through the NAS's existing Cloudflare tunnel, from home or abroad. The tunnel only forwards `/v1/` paths, and the Cloudflare Access application `CLIProxyAPI` admits only the `cliproxy` service token, so every request needs that token's headers plus a client key from the proxy's `access.api-keys`. The management UI, CPAMC, stays LAN-only at `http://homelab.local:8317/management.html`; sign in with the management key, then add or reorder accounts under OAuth Login, Auth Files, and Quota Management.

Three values in `$ZSH/.env` connect a host:

```sh
CLIPROXY_API_KEY=<client key>
CF_ACCESS_CLIENT_ID=<service token client id>
CF_ACCESS_CLIENT_SECRET=<service token client secret>
```

`install.sh t3code` writes them into the `cpa_` twins: Claude gets the client key as `ANTHROPIC_AUTH_TOKEN` and the Access headers through `ANTHROPIC_CUSTOM_HEADERS`; Codex sends them through the `[model_providers.cliproxy]` block's `env_key` and `env_http_headers`. With the key present, `zshrc` also wraps `claude` and `codex` so a terminal session goes through the proxy, passing the values per call instead of exporting them, so other Anthropic and OpenAI SDKs in the shell keep their own endpoints. `command claude` and `command codex` bypass the proxy and use the machine's own login, which is the fallback when the NAS is down, alongside the plain Claude and Codex instances in T3 Code.

## opencode

`opencode/opencode.json` registers the gateway as an OpenAI-compatible provider and names the open-weight models it serves: GLM-5.2, GLM-5.3, GLM-5.3-Flash and Kimi K3. They reach no Claude or Codex instance — those enumerate models from their own CLIs, and the gateway returns `400 invalid request body` for Codex's freeform (`type: "custom"`) shell tool on every open-weight model while accepting it for OpenAI's. opencode sends plain function tools, which they accept, so `phaig_opencode` is where they are usable.

The config also registers PostHog's remote MCP server at `https://mcp.posthog.com/mcp` for access to project analytics. Connection authentication is separate from the gateway key.

The key comes from `POSTHOG_GATEWAY_KEY` through opencode's own `{env:…}` substitution: inside T3 Code the instance supplies it, and from a shell `zshrc` exports it out of `$ZSH/.env`. `install.sh opencode` runs opencode's installer when the binary is missing, rather than taking the Homebrew formula: it keeps `~/.opencode/bin` as the path on every host, which is what `phaig_opencode` is configured with, and core trails the current release.
