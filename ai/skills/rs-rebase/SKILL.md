---
name: rs-rebase
description: "Merge the parent branch into the current branch, resolve conflicts, and push."
disable-model-invocation: true
---

# Rebase

Merge the parent branch into the current branch, resolve any conflicts, and push.

Use this to bring the current branch up to date with its parent (e.g., after the parent merged master or had new commits pushed).

## Workflow

### Step 1: Identify the Parent Branch

```sh
gt log short
```

The parent is the branch directly below the current one in the stack. If using plain git branches (no Graphite), determine the parent from the PR's base branch:

```sh
gh pr view --json baseRefName
```

### Step 2: Fetch and Merge

```sh
git fetch origin <parent-branch>
git merge origin/<parent-branch>
```

If the merge completes cleanly, skip to Step 4.

### Step 3: Resolve Conflicts

If there are conflicts:

1. Check mergiraf output — it may auto-resolve some files. Always verify its resolutions are correct. Mergiraf can remove imports but leave call sites that reference them.
2. Check which files still have conflict markers: `git diff --check`
3. For each conflicted file, read it, understand both sides, and resolve.
4. Stage resolved files and complete the merge: `git merge --continue`

### Step 4: Push

```sh
git push origin HEAD
```

### Step 5: Refresh the PR if the merge changed its scope

If the current branch has an open PR and pulling the parent in changed what this PR actually does (conflict resolutions that altered behaviour, now-redundant commits, a shifted diff), apply the `rs-update-pr` skill to re-check the title and description against the new diff and update them if stale. A clean merge that doesn't change the branch's own diff needs no refresh. Refresh without asking (per CLAUDE.md → Pull Request Descriptions).

### Step 6: Report

Display what was merged, whether any conflicts were resolved, and how.
