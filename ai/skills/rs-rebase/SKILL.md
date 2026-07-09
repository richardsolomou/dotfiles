---
name: rs-rebase
description: "Merge the parent branch into the current branch, resolve conflicts, and push."
disable-model-invocation: true
---

# Rebase

Merge the parent branch into the current branch, resolve any conflicts, and push.

Use this to bring the current branch up to date with its parent (e.g., after the parent merged master or had new commits pushed). Despite the name, this **merges** the parent in — it does not rewrite history; rebasing the stack is `rs-restack`.

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

If there are conflicts, apply the `rs-resolve-conflicts` skill — it owns the full flow (mergiraf verification, lock files, migrations, stacked-PR duplicates) and finishes with `git merge --continue`.

### Step 4: Push

```sh
git push origin HEAD
```

### Step 5: Refresh the PR if the merge changed its scope

If the branch's own diff changed (conflict resolutions that altered behaviour, now-redundant commits), apply `rs-update-pr` — automatic, no ask (per CLAUDE.md → Pull Request Descriptions). A clean merge that leaves the branch's own diff unchanged needs no refresh.

### Step 6: Report

Display what was merged, whether any conflicts were resolved, and how.
