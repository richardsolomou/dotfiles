# AI Settings

One set of instructions, skills, and MCP servers, shared by every agent harness: Claude Code, Codex, and pi.

- `AGENTS.md` — global instructions for all harnesses
- `AGENTS.posthog.md` — extra rules loaded only under `~/dev/posthog`
- `RTK.md` — rtk usage notes, imported by Claude Code only
- `skills/` — local skills shared by the installed agent harnesses
- `agents/` — Claude Code subagents
- `pi/` — pi-only configuration: gateway providers, the subscription fallback extension, and MCP
- `t3code/` — t3code provider instances that route to the gateway
- `opencode/` — opencode config: the gateway's open-weight models

## Installation

```sh
./install.sh                    # everything
./install.sh context skills     # only these components
./install.sh --uninstall        # remove the symlinks
./install.sh --help             # list components
```

Everything is symlinked, so edits here take effect without reinstalling. Adding a skill or renaming one needs a re-run; the script also prunes symlinks left behind by skills it no longer manages.

## pi

pi ships five tools and, by design, no MCP, subagents, browser control, or web search. `pi/` closes that gap and points pi at PostHog's AI gateway:

- `pi/extensions/gateway-models.ts` registers the gateway as two providers, reading its `/v1/models` catalog at startup rather than a checked-in list, and falls back to a twelve-hour cache when the gateway is unreachable. Traits the catalog omits (reasoning, image input, output ceilings, per-model quirks) come from the catalogs pi ships, so a machine with no Claude or Codex login still describes models correctly.
- `pi/extensions/gateway-fallback.ts` reacts to a subscription failing: it switches to the same model on the gateway, resends the pending turn, and cools that provider down (5 minutes doubling to an hour) before retrying it. Every switch is reported to stderr and the session as well as the UI, since a run driven by an orchestrator has no UI to notify.
- `pi/mcp.json` gives pi MCP. `imports` reads the host configs already on the machine, so the servers registered for Claude and Codex work in pi without copying definitions or credentials.

The gateway key goes in `~/.pi/agent/auth.json` under each provider id, not in this repo, so it resolves however pi is launched.

## Checks

```sh
./bin/check
```

Shell syntax, shellcheck, JSON, markdownlint, and a check that every skill referencing a sibling skill references one that exists. CI runs the same script on every push and pull request.

## t3code

t3code locks a thread to the provider driver and CLI home it started on, so the only way to keep working past a usage limit without losing the conversation is a second instance of the *same* driver and home with different credentials. `t3code/provider-instances.json` declares those twins — `phaig_claude`, `phaig_codex` and `phaig_opencode` — and `install.sh t3code` writes them into `~/.t3/userdata/settings.json`, merging per instance id so anything configured by hand on the host survives.

Neither the settings nor the credentials can be symlinked. t3code saves settings through a temp file plus rename, which would replace a symlink with a regular file, and sensitive environment values live in `~/.t3/userdata/secrets` as `provider-env-<base64url instance>-<base64url variable>.bin`, mode 0600. Every environment entry marked `valueRedacted` is filled from `POSTHOG_GATEWAY_KEY`, falling back to the key pi already stores in `~/.pi/agent/auth.json`, so a host that runs pi needs no extra secret handling.

Paths in that file may start with `~/`; the installer expands them, because the opencode driver takes `binaryPath` literally and the t3code server does not inherit a login shell's PATH.

Codex reaches the gateway through a `[model_providers.posthog]` block appended to `~/.codex/config.toml` and selected per instance with `-c model_provider=posthog`; `-c` is used rather than `--profile` because only `-c`, `--config`, `--enable` and `--disable` reach the `codex exec` path. Claude needs no config file: `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` on the instance take precedence over the subscription login in the shared config directory, at the cost of claude.ai connectors in that instance.

Both twins are named `PH·Claude` and `PH·Codex` so the rail badge reads `PH`. The badge takes the first two characters of a single-word label, or the first character of each of the first two words, splitting on whitespace as well as `_` and `-` — so `PH-Codex` would badge as `PC`, and the middle dot is what keeps it one word. The accent color is PostHog orange, which also forces the badge to render on every instance rather than only when a driver has several. Ids prefixed `phaig_` are owned by this repo: the installer replaces them and drops ones the file no longer declares, along with their now-unused key files.

Subscription logins stay per host: run `claude auth login` and `codex login` on the machine. A headless host that only ever uses the gateway needs neither.

## opencode

`opencode/opencode.json` registers the gateway as an OpenAI-compatible provider and names the open-weight models it serves: GLM-5.2, GLM-5.3, GLM-5.3-Flash and Kimi K3. They reach no Claude or Codex instance — those enumerate models from their own CLIs, and the gateway returns `400 invalid request body` for Codex's freeform (`type: "custom"`) shell tool on every open-weight model while accepting it for OpenAI's. opencode sends plain function tools, which they accept, so `phaig_opencode` is where they are usable.

The key comes from `POSTHOG_GATEWAY_KEY` through opencode's own `{env:…}` substitution, so the CLI and the t3code instance read the same one.
