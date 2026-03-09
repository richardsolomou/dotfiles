---
name: restack
description: "Restack dependent branches on top of the current branch using Graphite CLI and push them."
disable-model-invocation: true
---

# Restack

Restack all branches stacked on top of the current branch using Graphite CLI, then push them.

Use this after making changes to a base branch (e.g., merging master, fixing conflicts, adding commits) to propagate those changes up through the stack.

## Prerequisites

- You must be on the branch whose dependents need restacking
- Graphite CLI (`gt`) must be available

## Workflow

### Step 1: Assess the Stack

```sh
gt log short
```

Confirm the current branch and identify dependent branches stacked on top.

If there are no dependent branches, stop and tell the user there is nothing to restack.

### Step 2: Restack

```sh
gt restack
```

If restack reports conflicts, resolve them:

1. Read each conflicted file and resolve
2. Stage resolved files with `git add`
3. Continue the rebase: `git rebase --continue`

### Step 3: Push Restacked Branches

For each branch that was restacked, force-push:

```sh
git push --force-with-lease origin <branch>
```

### Step 4: Report

Display which branches were restacked and pushed.
