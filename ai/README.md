# AI Settings

One set of instructions, skills, and MCP servers, shared by every agent harness: Claude Code, Codex, and pi.

- `AGENTS.md` — global instructions for all harnesses
- `AGENTS.posthog.md` — extra rules loaded only under `~/dev/posthog`
- `RTK.md` — rtk usage notes, imported by Claude Code only
- `skills/` — local skills shared by the installed agent harnesses
- `agents/` — Claude Code subagents
- `pi/` — pi-only configuration: gateway providers, the subscription fallback extension, and MCP

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
