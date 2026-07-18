---
name: rs-update-pr
description: "Update a pull request's title and description based on the actual changes in the PR. Uses the repo's PR template and conventional commit style titles."
---

# Update PR

Update the current branch's PR title and description to reflect the actual changes.

This skill is also the **single source of truth for how to write a PR title and body** — the title rules, the description structure, the length guidance, and the voice. Other skills that push code (`rs-ship`, `rs-address-pr-review`, `rs-autopilot`, `rs-rebase`, `rs-restack`) apply this skill as a sub-step instead of restating its rules. Per CLAUDE.md, a PR's title and body must always reflect the current diff, so any push to a branch with an open PR ends with a refresh through this skill — automatically, without asking.

## Workflow

1. Get the current branch name and find its PR:

   ```sh
   gh pr view --json number,title,body,baseRefName
   ```

2. Get the full diff against the base branch:

   ```sh
   git diff $(gh pr view --json baseRefName -q '.baseRefName')...HEAD
   ```

3. Get the commit log for context on intent:

   ```sh
   git log --oneline $(gh pr view --json baseRefName -q '.baseRefName')..HEAD
   ```

4. Check for a PR template in the repo:

   ```sh
   cat .github/pull_request_template.md 2>/dev/null
   ```

5. Write the PR title and description:

**Title rules:**

- Use conventional commit format: `<type>(<scope>): <description>`
- Keep under 72 characters
- Use lowercase description, no period at the end
- Types: the conventional commit types from CLAUDE.md → Git (`feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `style`)
- Scope is optional but encouraged

**Description rules:**

What good looks like for a straightforward PR. Use this density as a baseline, and expand when more context helps reviewers understand or validate the change:

```markdown
## Problem

`pytest` collection failed on master. `tools/traffic-sim/tests/__init__.py` made the directory a top-level `tests` package, shadowing the real one.

## Changes

Added `--ignore=tools/traffic-sim` to `pytest.ini`, matching the existing pattern for `tools/hogli`.

## How did you test this code?

Ran `pytest` from the repo root. Async migrations job passes locally.
```

Rules:

- Use the PR template if one exists. Fill every section. Write "N/A" for sections that don't apply. Don't add, omit, rename, or reorder sections. If no template, fall back to: Problem, Changes, How did you test this code?
- **Aim for roughly 3 lines per section.** Treat this as a concision target, not a limit. Use the space needed to explain important context, decisions, risks, rollout details, or testing clearly, while removing anything that does not help a reviewer.
- **Don't recap the diff.** The diff is on the PR. Describe only what the diff cannot show: the why, the constraint, the alternative considered, the deferred follow-up.
- **Describe the state the PR leaves things in and the decisions made — never the journey.** No "old approach", "we pivoted", or draft-history narrative; that lives in the commits.
- **Tight vertical spacing.** One blank line between sections, none inside a bullet list, no trailing blanks or empty template sections left as gaps.
- Prefer short, direct sentences. Rewrite long sentences when that improves clarity, but do not omit useful detail to meet an arbitrary word count.
- Bullets over prose when listing more than one thing. Single sentences when listing one.
- Problem: the constraint, bug, or motivation. One or two sentences.
- Changes: the intent and any non-obvious decision. Skip if the title already says it.
- How did you test: tests added/modified, plus manual testing if any. One line each.

After drafting, re-read and delete anything that is restating the diff, padding, or scene-setting. Prefer the shortest description that gives reviewers the context they need.

**Voice and tone (mandatory):**

Load the `rs-tone` skill with `register: pr-description` before drafting anything. Apply that register and the common rules at the top of the doc.

Overrides on top of the register:

- No em-dashes. Use commas, periods, or parentheses. The `pr-description` register allows em-dashes; this skill does not.
- No AI smell: no formulaic openers ("This PR…", "In this change…"), no marketing words ("seamlessly", "robust", "comprehensive"), no closing sign-offs, no padding.

Finally, update the PR:

```sh
gh pr edit <number> --title "<title>" --body "<body>"
```

Use a heredoc for the body to preserve formatting.
