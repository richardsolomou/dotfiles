---
name: clean-worktrees
description: Reclaim macOS disk space from inactive T3 and Claude Git worktrees, disposable worktree dependencies, and explicitly requested T3 recovery backups. Use for recurring agent-worktree cleanup, not general system cache removal.
---

# Clean Worktrees

Use [scripts/clean_worktrees.py](scripts/clean_worktrees.py) with Python 3.12+. It inventories the known agent roots and Git registrations once, shares OS activity scans for five seconds, and processes work continuously with eight workers. It avoids recursive size scans and creates a small private report instead of recovery copies.

## Run

Resolve the script relative to this skill's real directory; it may be installed through a symlink.

```bash
python3 <skill-directory>/scripts/clean_worktrees.py
```

This is read-only. When the user requests cleanup, use `--apply` directly; another approval is unnecessary. A request to diagnose storage or create this skill alone does not authorize deletion.

```bash
python3 <skill-directory>/scripts/clean_worktrees.py --apply
python3 <skill-directory>/scripts/clean_worktrees.py --apply --only all
python3 <skill-directory>/scripts/clean_worktrees.py --apply --only recovery
```

The default covers T3 and Claude worktrees. Include recovery only when requested: those backups may be the only copy of old local changes. `--repo /absolute/primary/repository` narrows worktree cleanup and locates repositories outside `~/dev`. Repeat it for multiple repositories. Recovery selection is independent of `--repo`.

## Retention and exceptions

- Keep active, open unsettled, pinned, or snoozed T3 threads; running Claude sessions; paths referenced by processes, launch agents, or cron; and recent unreferenced workspaces. Never stop applications to make them eligible.
- Keep primary repositories, locked worktrees, broken or ambiguous Git metadata, local source changes, unknown ignored data, and commits without a retaining branch. Branches are never deleted. A retained inactive worktree can still have its ignored disposable dependencies trimmed.
- The helper recognizes conventional dependency/build directories such as `node_modules`, `.venv`, `.next`, and `.flox/cache`. Do not hand-edit files in disposable dependency directories. Unknown ignored files such as `.env` retain the worktree. It does not delete Claude history, settings, or credentials.
- If activity inspection or the T3 schema fails, stop and report the error. Enabled T3 schedules deliberately stop automation until their workspace requirements are inspected. Do not bypass this by dropping activity checks, deleting broken worktrees directly, or using `git worktree remove --force`.

For additional generated directories, verify the repository's build/configuration first, then use `--repo /absolute/repo --generated relative/directory`. This is an explicit declaration that all ignored contents of that directory are disposable. Never classify application databases, downloads, or arbitrary `data` directories by name alone. Keep repository-specific choices out of the shared helper.

`--min-age-hours` defaults to one hour for unreferenced workspaces and recovery backups. Use zero only when the user's scope justifies deleting newly created items. `--workers` accepts 1–16; increasing it cannot avoid the cost of unlinking millions of files.

## Report

The command prints its private temporary `clean-worktrees-*/report.json` path and saves each completed result. On Ctrl-C it stops starting mutations and waits for in-flight work. Report removed worktrees, trimmed dependency directories, retained/error reasons, and the measured net change in available bytes. On APFS, concurrent writes and shared blocks mean this is not an exact sum attributable to deleted folders. Do not add overlapping `du` totals.

Discovery covers `~/.t3/worktrees`, repositories up to two levels below `~/dev`, their registered Claude worktrees, and explicit `--repo` roots. State this scope when reporting completion; use explicit repositories to extend it. A recurring cleanup does not need a whole-home scan.
