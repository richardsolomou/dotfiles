---
name: resolve-conflicts
description: Resolve git conflicts with AI-powered analysis, including mergiraf structural merging, lock file handling, and stacked PR duplicate detection.
argument-hint: [--abort|--continue]
---

# Resolve Git Conflicts

Resolve conflicts from any git operation (rebase, merge, cherry-pick, revert), then continue it. `--abort` aborts the operation in progress; `--continue` skips resolution and runs the continue step.

## Environment

- **mergiraf** is configured as a git merge driver, so supported files have already had one structural merge attempt.
- **rerere** is enabled globally and replays recorded resolutions automatically.
- Conflict markers use diff3 style when `merge.conflictStyle = diff3` is set; otherwise the base section is absent.

## Detect

`~/.agents/skills/resolve-conflicts/scripts/conflict-status.sh` prints `context\tprogress\tbranch`, where `context` is `rebase`, `merge`, `cherry-pick`, `revert`, or `none`, and `progress` is `current/total` during a rebase. If nothing is in progress, say so and stop.

## Resolve

`~/.agents/skills/resolve-conflicts/scripts/categorize-conflicts.sh` prints `category\tfile_path` for each unmerged file. Report the categories briefly, then handle them:

- **`lockfile`** — take `--theirs` to clear the markers, then regenerate it from the resolved manifest with the project's package manager before continuing.
- **`migration`** — never auto-resolve. Show the commit behind each side and ask which migrations and schema effects must exist afterwards, and whether either is already upstream. Remember that `--ours`/`--theirs` swap meaning during a rebase.
- **`mergiraf`** — run `mergiraf solve -- <file> --compact` as a second pass. If markers remain, resolve the rest as `other`.
- **`other`** — read each hunk and resolve it.

**Stacked PR duplicates.** When the base section is empty or much smaller than both sides, a merged sub-PR may have duplicated code that also exists on this branch. Auto-resolve to HEAD only when stack or commit history proves both sides are the same patch and their normalised results are identical, and report that proof. Similar-but-not-identical hunks, true divergence, and ordinary both-modified conflicts go to the user with your analysis and a recommendation.

Stage each file once it has no markers.

## Continue

Run the operation's continue command (`git commit --no-edit` for a merge), loop back if a rebase stops on further conflicts, and finish with a summary: what was auto-resolved versus user-resolved, lock files regenerated, and any rerere replays.
