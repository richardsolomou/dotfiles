---
name: ship
description: "Commit staged/unstaged changes with a semantic commit message, push, and create a PR."
---

# Ship

Commit current changes, push, and create or refresh the pull request.

## Before committing

Check the working tree, the current branch, the remote's default branch, and any existing PR for the branch.

- No changes → stop and say there is nothing to ship.
- On the remote's default branch → stop before committing and ask the user to create a feature branch.
- The branch's PR is merged or closed → don't push to it. Branch fresh from `origin/<base>`, replay only the unmerged changes, and confirm the new branch has no PR.
- The user asks for one self-contained PR per repository → don't preserve a stacked base. Consolidate the prerequisite diff onto a trunk-based PR and close superseded PRs in that repository.

Read the full diff. Include untracked files only when they belong to the change; ask if unsure. If the changes are unrelated to each other, ask which to include.

## Commit

Stage explicit file paths, never `git add -A`. Write the message per Commit messages in the global instructions, using a quoted heredoc:

```sh
git commit -m "$(cat <<'EOF'
type(scope): description

Optional body explaining why.
EOF
)"
```

## Push

If the branch belongs to a GitHub Stack (`gh stack view --json` includes it), run `gh stack submit --auto --open` instead of a plain push and PR creation; it pushes every layer, creates or updates the PRs, and syncs the Stack object. Then apply `update-pr` to each created or changed PR.

Otherwise run `git push -u origin HEAD`, using the default branch recorded before the commit as the PR base.

## Create or refresh the PR

If a PR already exists, apply `update-pr` to refresh its title and body against the full diff; no approval needed.

Otherwise write the title and body with `update-pr`, which owns the title rules, structure, and voice. Other sessions ship concurrently, so draft in a private directory (`mktemp -d "${TMPDIR:-/tmp}/ship.XXXXXX"`). Write `title.txt` and `body.md` there with the file-writing tool, following the shell-safety rules in `update-pr`, then:

```sh
gh pr create --title "$(cat <draft>/title.txt)" --body-file <draft>/body.md
rm -rf <draft>
```

Report the commit hash and message, and the PR URL.
