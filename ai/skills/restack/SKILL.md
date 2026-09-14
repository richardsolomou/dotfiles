---
name: restack
description: "Rebase and sync a GitHub Stacked PR stack after a parent branch changes."
---

# Restack

Cascade a changed parent through its GitHub Stacked PR stack, then sync every branch and PR.

Use this after making changes to a base branch (e.g., merging master, fixing conflicts, adding commits) to propagate those changes up through the stack.

You must be on a branch tracked by the official `gh stack` extension.

## Workflow

### Step 1: Assess the Stack

Run `gh stack view --json` and confirm the current branch, trunk, branch order, PRs, and `needsRebase` state.

If there are no dependent branches, stop and tell the user there is nothing to restack.

### Step 2: Rebase the stack

Run `gh stack rebase`. If it reports conflicts, apply `resolve-conflicts`, stage the resolutions, then run `gh stack rebase --continue`. Use `gh stack rebase --abort` to restore the stack if the conflict cannot be resolved safely.

### Step 3: Push Restacked Branches

Sync the rebased branches, PR bases, and GitHub Stack object:

```sh
gh stack sync
```

### Step 4: Refresh PRs whose scope changed

For each restacked branch whose own diff changed (conflict resolutions that altered behaviour, dropped commits), apply `update-pr` — automatic, no ask (per Pull Request Descriptions in the global instructions). A pure restack that only rewrites parent commits needs no refresh.

### Step 5: Report

Display which branches were restacked and pushed.
