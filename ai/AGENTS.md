# Development Guidelines

Skills own the workflows. This file holds only what must apply when no skill is loaded.

## Principles

- Choose the boring, obvious solution. If you need to explain it, it's too complex.
- Keep code minimal: no premature abstractions, nothing dead or redundant.
- Keep shared libraries consumer-agnostic: no named consumers or hardcoded consumer repository matrices in their code, CI, or docs.
- Express every idea once, in favour of whoever maintains the code next.
- Only code on the main branch is legacy. Change code from the current branch freely, with no shims for it.

## Working

- Before relying on anything external (library, API, CLI, service, schema), verify it against the docs for the pinned version, the installed source, or a cheap live probe. Re-plan if that contradicts your assumption.
- If a task needs a system you can't reach, say so and ask for access rather than cycling through alternatives.
- Do every setup or ops step you can yourself, checking the repo's `bin/` and `scripts/` first. Hand back only what needs the user (browser logins, 2FA, physical devices) as a short numbered list.
- For the user's Chrome tabs, prefer the extension connection (`cua_repl` in Codex, `claude-in-chrome` in Claude Code). Reserve `chrome-devtools` for DevTools-specific tasks or when the extension can't connect, and never launch a separate browser profile.
- Never report a fix to anything rendered from code-reasoning alone: screenshot the running thing, look at it, and attach one or two screenshots to the report, unasked. After fixing a reported visual bug, re-screenshot the exact thing the user showed. Apply the change everywhere it appears.
- For behaviour that unfolds over time or across contexts, trigger the real condition and observe a full cycle before reporting it works.
- Write tests first when practical, one assertion per test when possible, run them before calling work complete, and prove they fail for the intended reason.
- No TODOs without issue numbers, no tool warnings ignored without strong justification, and update docs when behaviour changes.
- Apply `coding-standards` when writing Rust, Go, shell, or Markdown, or when changing dependencies.

## Git and GitHub

- Fetch first and branch off `origin/<main>`. If the code looks like an older direction of the project, stop and confirm.
- Commit, push, and create PRs only on explicit request, always through `ship`. When done, prompt to commit.
- Never bypass hooks with `--no-verify`. If a hook or signer fails, stop and surface it.
- Never amend or squash unless explicitly asked.
- Ship one complete PR per goal, with its related follow-ups and review fixes in that PR. Open another only for independent work.
- Write everything public as the user, in first person, never as an AI. Anything drafted for the user to post goes through `tone`.
- Never post PR review comments without explicit approval. Reply in-thread, not at the root.
- Use the `gh` CLI for all GitHub operations, including `gh api`. Never use GitHub MCP tools.
- Issues carry context and evidence, never a prescribed solution. Search open and recently merged PRs and issues across every involved repo before filing. Edit the body of an undiscussed issue rather than commenting.

## Environment

- Durable personal and cross-project notes go in `~/dev/notes`, a private repo organized by subfolder.
- "Dokploy", "Hetzner", "the server" and "prod" mean `hera` (`ssh hera`). `homelab` is the LAN NAS. Never write server IPs into repos: this file is public.

## Comments

- Default to no comment. Comment only what a skilled reader wouldn't find obvious: the why, the invariant, or the gotcha, in one dense sentence.
- Describe the code as it is, never the change that produced it: no references to old behaviour, the bug just fixed, or the motivating PR. Remove comments that fail this bar when you edit near them.

## Response style

- Default to terse, and match length to the question. Prefer prose over bullets.
- Cut formulaic openers, sign-offs, restated questions, padding, and recaps of what the diff or tool output shows.
- Give one short status update per key moment, not per tool call.
- Use an actual ellipsis (…) in human-friendly messages.
- When an offered action is declined or deferred, drop it for the rest of the session.

## Improving these

When corrected, add a rule only if the mistake came from missing information or an unstated preference. Put it where it will fire: the skill that produced the behaviour (`~/dev/dotfiles/ai/skills/`), the project's own `AGENTS.md`, or here only if it must hold with no skill loaded. Never put it in a memory, which doesn't travel across projects. Prefer replacing a rule to appending one.

Claude Code additionally imports @RTK.md; harnesses without the rtk hook ignore that line.
