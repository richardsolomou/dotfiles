---
name: update-pr
description: "Update a pull request's title and description based on the actual changes in the PR. Uses the repo's PR template and conventional commit style titles."
disable-model-invocation: true
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
- Use the repo's PR template if one exists
- Fill in each section based on the actual diff, not assumptions
- Problem: explain why this change is being made
- Changes: summarize what changed, include file-level detail for non-obvious changes
- How did you test: list tests that were added/modified, note if manual testing was done
- Be concise, skip sections that don't apply (e.g. changelog for non-features)

6. Update the PR:

```sh
gh pr edit <number> --title "<title>" --body "<body>"
```

Use a heredoc for the body to preserve formatting.
