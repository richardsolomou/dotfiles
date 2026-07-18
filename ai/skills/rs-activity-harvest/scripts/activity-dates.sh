#!/bin/bash
# Compute a cadence-entry window: [previous entry moment, now].
#
# An entry covers everything done since the previous entry was generated, up to
# the moment this one is generated. The previous moment is read from the
# `generated-at:` marker in the most recent archived entry, so consecutive
# entries never overlap (no duplicates) and never leave a gap.
#
# Usage: activity-dates.sh <notes-subdir> <header-style: day|week> <same-day: reuse|previous>
#
#   notes-subdir   Directory under ~/dev/notes, e.g. "PostHog/standup".
#   header-style   day  -> "17 June", dated the business day the entry is for:
#                          noon or later means today (a worked weekend keeps its
#                          own date); before noon means the previous business
#                          day (Tuesday 9am -> Monday, Monday 9am -> Friday).
#                  week -> "Week of 17 June", dated the generation day.
#   same-day       reuse    -> on a re-run for the same entry date, that entry is
#                              the previous one (window = delta since the earlier
#                              run; callers that append, e.g. rs-standup).
#                  previous -> skip the same-date file so the window stretches
#                              back to the real previous entry (callers that
#                              regenerate, e.g. rs-ai-gateway-sync).
#
# Output (tab-separated):
#   <window_start>\t<now>\t<new_file_path>\t<header>\t<prev_file_path>

set -euo pipefail

subdir="${1:?usage: activity-dates.sh <notes-subdir> <day|week> <reuse|previous>}"
header_style="${2:?header-style required: day|week}"
same_day="${3:?same-day mode required: reuse|previous}"

DIR="$HOME/dev/notes/$subdir"
mkdir -p "$DIR"

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ "$OSTYPE" == "darwin"* ]]; then
    ago() { date -v-"$1"d +"$2"; }
else
    ago() { date -d "$1 days ago" +"$2"; }
fi

case "$header_style" in
    day)
        # Entry date = the business day the entry covers, not the generation
        # day. `generated-at:` still records the real instant, so windows stay
        # gapless either way.
        back=0
        if [ "$(date +%H)" -lt 12 ]; then
            back=1
            while [ "$(ago "$back" %u)" -gt 5 ]; do back=$((back + 1)); done
        fi
        entry_date=$(ago "$back" %Y-%m-%d)
        header=$(ago "$back" "%-d %B")
        ;;
    week)
        entry_date=$(date +%Y-%m-%d)
        header="Week of $(date "+%-d %B")"
        ;;
    *) echo "unknown header-style: $header_style" >&2; exit 1 ;;
esac
new_file="${DIR}/${entry_date}.md"

prev_file=$(find "$DIR" -maxdepth 1 -name "????-??-??.md" -type f 2>/dev/null | sort -r | head -1)
if [[ "$same_day" == "previous" && -n "$prev_file" && "$prev_file" == "$new_file" ]]; then
    prev_file=$(find "$DIR" -maxdepth 1 -name "????-??-??.md" -type f 2>/dev/null | sort -r | sed -n '2p')
fi

if [[ -n "$prev_file" ]]; then
    window_start=$( { grep -oE 'generated-at: [^ ]+Z' "$prev_file" 2>/dev/null || true; } | head -1 | sed 's/generated-at: //')
    if [[ -z "$window_start" ]]; then
        # Legacy entry with no marker: fall back to when the file was last written.
        window_start=$(date -u -r "$prev_file" +%Y-%m-%dT%H:%M:%SZ)
    fi
else
    # No prior entry: default to a week back so nothing is missed.
    if [[ "$OSTYPE" == "darwin"* ]]; then
        window_start=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
    else
        window_start=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)
    fi
fi

echo -e "${window_start}\t${now}\t${new_file}\t${header}\t${prev_file}"
