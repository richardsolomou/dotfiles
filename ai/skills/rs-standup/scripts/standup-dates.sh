#!/bin/bash
# Compute the standup window: [previous standup moment, now].
#
# A standup covers everything done since the previous standup was generated, up
# to the moment this one is generated. The previous moment is read from the
# `generated-at:` marker in the most recent archived entry, so consecutive
# standups never overlap (no duplicates) and never leave a gap. Anything done
# after a standup is generated falls into the next one.
#
# Usage: standup-dates.sh
#
# Output (tab-separated):
#   <window_start>\t<now>\t<new_file_path>\t<date_header>\t<prev_file_path>
#
#   window_start    ISO 8601 UTC. Pass to standup-prs.sh and use to filter Slack.
#   now             ISO 8601 UTC. Stamp into the new entry's `generated-at:` marker.
#   new_file_path   Where to write this entry (YYYY-MM-DD.md).
#   date_header     Human header for the entry, e.g. "17 June".
#   prev_file_path  Most recent existing entry (read it for in-flight items), or "".

set -euo pipefail

STANDUP_DIR="$HOME/dev/rs/notes/PostHog/standup"
mkdir -p "$STANDUP_DIR"

today=$(date +%Y-%m-%d)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
date_header=$(date "+%-d %B")
new_file="${STANDUP_DIR}/${today}.md"

prev_file=$(find "$STANDUP_DIR" -maxdepth 1 -name "????-??-??.md" -type f 2>/dev/null | sort -r | head -1)

if [[ -n "$prev_file" ]]; then
    window_start=$( { grep -oE 'generated-at: [^ ]+Z' "$prev_file" 2>/dev/null || true; } | head -1 | sed 's/generated-at: //')
    if [[ -z "$window_start" ]]; then
        # Legacy entry with no marker: fall back to when the file was last written.
        window_start=$(date -u -r "$prev_file" +%Y-%m-%dT%H:%M:%SZ)
    fi
else
    # No prior standup: default to a week back so nothing is missed.
    if [[ "$OSTYPE" == "darwin"* ]]; then
        window_start=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
    else
        window_start=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)
    fi
fi

echo -e "${window_start}\t${now}\t${new_file}\t${date_header}\t${prev_file}"
