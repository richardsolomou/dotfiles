#!/bin/bash
# Calculate standup-related dates.
# Standups are daily on weekdays, written into the team's shared Slack canvas.
#
# Usage: standup-dates.sh
#
# Output format (tab-separated):
#   <today>\t<last_standup_date>\t<new_file_path>\t<canvas_date_header>
#
# Example: 2026-06-05\t2026-06-04\t/path/to/standup/2026-06-05.md\t5 June

set -euo pipefail

STANDUP_DIR="$HOME/dev/richardsolomou/notes/PostHog/standup"

# Ensure directory exists
mkdir -p "$STANDUP_DIR"

today=$(date +%Y-%m-%d)
day_of_week=$(date +%u)  # 1=Monday, 7=Sunday

# Last standup is the previous weekday
case $day_of_week in
    1)  days_back=3 ;;  # Monday - last standup was Friday
    7)  days_back=2 ;;  # Sunday - last standup was Friday
    *)  days_back=1 ;;  # Any other day - previous day
esac

if [[ "$OSTYPE" == "darwin"* ]]; then
    last_standup=$(date -v-${days_back}d +%Y-%m-%d)
    canvas_header=$(date "+%-d %B")
else
    last_standup=$(date -d "${days_back} days ago" +%Y-%m-%d)
    canvas_header=$(date "+%-d %B")
fi

new_file="${STANDUP_DIR}/${today}.md"

echo -e "${today}\t${last_standup}\t${new_file}\t${canvas_header}"
