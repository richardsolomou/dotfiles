# Disk Space
alias disk-free='df -h /System/Volumes/Data | tail -1 | awk "{print \$4}"'
alias disk-usage='df -h / /System/Volumes/Data | grep -v "^Filesystem"'
alias disk-usage-all='df -h'

# Markdownlint
alias markdownlint='markdownlint-cli2'

# Navigation
alias ..='cd ..'

# Editor
alias c='code'

# Agent harnesses, permission prompts bypassed
alias cc='claude --dangerously-skip-permissions'
alias cx='codex --yolo'

# File listing
alias ll='ls -lah'
