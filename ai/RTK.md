# RTK

A Claude Code hook transparently rewrites Bash commands through `rtk` (e.g. `git status` → `rtk git status`) to compact their output. Use `rtk proxy <cmd>` when you need the raw, unfiltered output.
