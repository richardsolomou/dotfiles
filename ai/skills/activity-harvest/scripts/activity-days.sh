#!/bin/bash
# Split a cadence window into one sub-window per local calendar day.
#
# Days run from the local date of <window_start> through the local date of
# <now>. Each day ends at the next local midnight, except the last, which ends
# at <now>.
#
# Usage: activity-days.sh <window_start> <now> <notes_dir>
#
# Output, one line per day (tab-separated):
#   <day_start>\t<day_end>\t<file_path>\t<header>

set -euo pipefail

window_start="${1:?usage: activity-days.sh <window_start> <now> <notes_dir>}"
now="${2:?now required}"
dir="${3:?notes_dir required}"

if [[ "$OSTYPE" == "darwin"* ]]; then
    local_date() { date -r "$(date -j -u -f %Y-%m-%dT%H:%M:%SZ "$1" +%s)" +%Y-%m-%d; }
    next_day() { date -j -v+1d -f %Y-%m-%d "$1" +%Y-%m-%d; }
    midnight_utc() { date -u -r "$(date -j -f '%Y-%m-%d %H:%M:%S' "$1 00:00:00" +%s)" +%Y-%m-%dT%H:%M:%SZ; }
    header() { date -j -f %Y-%m-%d "$1" '+%-d %B'; }
else
    local_date() { date -d "$1" +%Y-%m-%d; }
    next_day() { date -d "$1 +1 day" +%Y-%m-%d; }
    midnight_utc() { date -u -d "@$(date -d "$1 00:00:00" +%s)" +%Y-%m-%dT%H:%M:%SZ; }
    header() { date -d "$1" '+%-d %B'; }
fi

day=$(local_date "$window_start")
today=$(local_date "$now")
start="$window_start"
while [[ "$day" < "$today" ]]; do
    next=$(next_day "$day")
    end=$(midnight_utc "$next")
    echo -e "${start}\t${end}\t${dir}/${day}.md\t$(header "$day")"
    start="$end"
    day="$next"
done
echo -e "${start}\t${now}\t${dir}/${today}.md\t$(header "$today")"
