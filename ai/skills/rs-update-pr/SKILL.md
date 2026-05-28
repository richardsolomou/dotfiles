---
name: rs-update-pr
description: "Update a pull request's title and description based on the actual changes in the PR. Uses the repo's PR template and conventional commit style titles."
---

# Update PR

Update the current branch's PR title and description to reflect the actual changes.

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
- Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`
- Scope is optional but encouraged

**Description rules:**

What good looks like. Match this density and length, do not exceed it without a real reason:

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
- **Hard ceiling: 3 lines per section.** Including bullet points. Exceed only when there is a specific non-obvious decision a reader cannot infer from the diff (e.g. why this approach over an obvious alternative), and even then keep it tight.
- **Don't recap the diff.** The diff is on the PR. Describe only what the diff cannot show: the why, the constraint, the alternative considered, the deferred follow-up.
- **If you can't say something in under 15 words, you don't have a clear thought.** Cut it or rewrite it.
- Bullets over prose when listing more than one thing. Single sentences when listing one.
- Problem: the constraint, bug, or motivation. One or two sentences.
- Changes: the intent and any non-obvious decision. Skip if the title already says it.
- How did you test: tests added/modified, plus manual testing if any. One line each.

After drafting, re-read and delete anything that is restating the diff, padding, or scene-setting. Shorter is always better.

**Voice and tone (mandatory):**

Load the `rs-tone` skill with `register: pr-description` before drafting anything. Apply that register and the common rules at the top of the doc.

Overrides on top of the register:

- No em-dashes. Use commas, periods, or parentheses. The `pr-description` register allows em-dashes; this skill does not.
- No AI smell: no formulaic openers ("This PR…", "In this change…"), no marketing words ("seamlessly", "robust", "comprehensive"), no closing sign-offs, no padding.

6. Update the PR:

```sh
gh pr edit <number> --title "<title>" --body "<body>"
```

Use a heredoc for the body to preserve formatting.
