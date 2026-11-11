---
name: ship
description: "Commit staged/unstaged changes with a semantic commit message, push, and create a PR."
---

# Ship

Commit current changes, push, and create or refresh the pull request.

## Before committing

Check the working tree, the current branch, the remote's default branch, and any existing PR for the branch.

- No changes → stop and say there is nothing to ship.
- On the remote's default branch, unless the user asked to push to it → create a `<type>/<slug>` branch, or `<type>/<issue#>-<slug>` when the issue is known.
- The branch's PR is merged or closed → don't push to it. Branch fresh from `origin/<base>`, replay only the unmerged changes, and confirm the new branch has no PR.
- The user asks for one self-contained PR per repository → don't preserve a stacked base. Consolidate the prerequisite diff onto a trunk-based PR and close superseded PRs in that repository.

Read the full diff. Include untracked files only when they belong to the change; ask if unsure. If the changes are unrelated to each other, ask which to include.

Before marking non-trivial work ready for review:

- Trace the whole changed flow rather than each hunk: failure, retry, concurrency, limits, and trust boundaries. Fix a class of issue everywhere it occurs.
- Apply `coding-standards` for the languages touched. Run `bin/fmt` if it exists, otherwise the language's formatter, and revert what it changes in files you didn't touch. Every commit compiles and passes its tests.
- For a request to fix all audit findings, check each one against the final diff and name any that remain.

## Commit

Stage explicit file paths, never `git add -A`. No "WIP" commits unless spiking. Address each PR review round as a new commit so reviewers can see what changed.

Use conventional commits, `<type>(<scope>): <description>`, with types `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`, `style`. Write the description in the imperative, lowercase, with no trailing period, and keep the whole line under 72 characters. Add a short body after a blank line when the why isn't obvious. When fixing a bug, include `Fixes #123` on its own line.

Use a quoted heredoc:

```sh
git commit -m "$(cat <<'EOF'
type(scope): description

Optional body explaining why.
EOF
)"
```

## Push

Stacked PRs use the official `gh stack` extension, not Graphite or base-linked PRs alone (`gh stack init` and `add` to build one). After changing a mid-stack branch, propagate it with `gh stack rebase` and `gh stack sync`.

If the branch belongs to a GitHub Stack (`gh stack view --json` includes it), run `gh stack submit --auto --open` instead of a plain push and PR creation; it pushes every layer, creates or updates the PRs, and syncs the Stack object. Then apply `update-pr` to each created or changed PR.

Otherwise run `git push -u origin HEAD`, using the default branch recorded before the commit as the PR base.

## Create or refresh the PR

If a PR already exists, apply `update-pr` to refresh its title and body against the full diff; no approval needed.

Otherwise write the title and body with `update-pr`, which owns the title rules, structure, and voice. Other sessions ship concurrently, so draft in a private directory (`mktemp -d "${TMPDIR:-/tmp}/ship.XXXXXX"`). Write `title.txt` and `body.md` there with the file-writing tool, following the shell-safety rules in `update-pr`, then:

```sh
gh pr create --title "$(cat <draft>/title.txt)" --body-file <draft>/body.md
rm -rf <draft>
```

## Merge (only when asked)

GitHub's `mergeStateStatus` (`gh pr view <n> --json mergeStateStatus`) decides, not a count of green checks:

- `CLEAN`, `UNSTABLE` or `HAS_HOOKS`: merge now with the method the repository uses. Never use `--admin` or another bypass.
- `BEHIND`: update the branch from its base. `DIRTY`: resolve the conflict.
- `BLOCKED`: find the blocker before acting. Read the base's required contexts from `gh api repos/<repo>/rules/branches/<base>` and branch protection, and compare them with the head commit's check runs. A required check whose job `needs:` other jobs has no run until they finish, so `gh pr checks --required` and watchers that count reported checks both miss it. Treat it as pending.

A run with status `waiting` needs an environment approval (`gh api repos/<repo>/actions/runs/<id>/pending_deployments`): name it, and when it does not gate merging, don't wait on it.

While a gating check is pending, wait as `babysit` describes and merge on the wake that finds the PR mergeable. Don't enable auto-merge: the merge would happen without you, nothing wakes you afterwards, and post-merge verification and the report never happen.

Report the commit hash and message, the merge commit, and the PR URL.
