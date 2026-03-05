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

- Use the repo's PR template if one exists
- Fill in sections based on the actual diff
- If no template, use: Problem, Changes, How did you test this code?

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
