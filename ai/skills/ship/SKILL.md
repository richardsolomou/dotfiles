---
name: ship
description: "Commit staged/unstaged changes with a semantic commit message, push, and create a PR."
disable-model-invocation: true
---

# Ship

Commit current changes, push, and create a pull request.

## Workflow

### Step 1: Assess the Current State

```sh
git status
git diff --stat
git diff --staged --stat
git log --oneline -5
git branch --show-current
```

If there are no changes (staged or unstaged), stop and tell the user there's nothing to ship.

### Step 2: Review the Changes

Read the full diff to understand what changed:

```sh
git diff
git diff --staged
```

If there are untracked files, check if they should be included. Ask the user if unsure.

### Step 3: Stage Changes

Stage relevant files individually. Prefer explicit file paths over `git add -A` to avoid accidentally including sensitive files (.env, credentials, etc.).

If all changes are clearly related to one logical change, stage everything. If there are unrelated changes, ask the user which to include.

### Step 4: Commit

Write a commit message following conventional commit format:

**Title rules:**

- Format: `<type>(<scope>): <description>`
- Keep under 72 characters
- Use lowercase description, no period at the end
- Present tense imperative: "Add", "Fix", "Update", not "Added", "Fixed"
- Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`
- Scope is optional but encouraged

**Body rules (if needed):**

- Blank line after title
- Explain why, not what (the diff shows what)
- Keep it concise

```sh
git commit -m "$(cat <<'EOF'
type(scope): description

Optional body explaining why.
EOF
)"
```

### Step 5: Determine the Base Branch

Figure out the base branch for the PR:

```sh
git remote show origin | grep 'HEAD branch'
```

If the current branch IS the main branch, stop and ask the user to create a feature branch first. Do not create PRs from main to main.

### Step 6: Push

Push the current branch, setting upstream if needed:

```sh
git push -u origin HEAD
```

### Step 7: Create the PR

Check for a PR template in the repo:

```sh
cat .github/pull_request_template.md 2>/dev/null
```

Check if a PR already exists for this branch:

```sh
gh pr view --json number,url 2>/dev/null
```

If a PR already exists, tell the user the changes have been pushed to the existing PR and show the URL. Skip PR creation.

If no PR exists, create one:

**Title:** Use the commit message title (or a summary if multiple commits).

**Description:**

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

After drafting, re-read and delete anything that is restating the diff, padding, or scene-setting. Shorter is always better.

**Voice and tone (mandatory):**

Load the `tone` skill with `register: pr-description` before drafting anything. Apply that register and the common rules at the top of the doc.

Overrides on top of the register:

- No em-dashes. Use commas, periods, or parentheses. The `pr-description` register allows em-dashes; this skill does not.
- No AI smell: no formulaic openers ("This PR…", "In this change…"), no marketing words ("seamlessly", "robust", "comprehensive"), no closing sign-offs, no padding.

```sh
gh pr create --title "<title>" --body "$(cat <<'EOF'
PR description here
EOF
)"
```

### Step 8: Report

Display:

1. The commit hash and message
2. The PR URL
