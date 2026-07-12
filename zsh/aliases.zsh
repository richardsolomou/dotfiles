# Pytest
unalias pytest-changes 2>/dev/null
pytest-changes() {
  local changes=$(git bchanges)
  if [[ "$1" == "--test-only" ]]; then
    # Only run test files that have actually changed
    echo "$changes" | grep -E 'test.*\.py$' | xargs -r pytest "${@:2}"
  else
    snob $changes | xargs -r pytest "$@"
  fi
}
_pytest-changes() {
  if (( CURRENT == 2 )) && [[ "$words[2]" != --test-only ]]; then
    _arguments '1:option:(--test-only)' '*::pytest args:_pytest'
  else
    _pytest
  fi
}
compdef _pytest-changes pytest-changes

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
alias cc='claude --dangerously-skip-permissions'
alias cx='codex --yolo'

# File listing
alias ll='ls -lah'
