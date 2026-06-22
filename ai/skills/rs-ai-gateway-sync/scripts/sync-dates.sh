#!/bin/bash
# Compute the AI Gateway weekly-sync window: [previous sync moment, now].
#
# The sync runs every Monday. An entry covers everything done since the previous
# sync was generated, up to the moment this one is generated — read from the
# `generated-at:` marker in the most recent archived entry, so consecutive syncs
# never overlap (no duplicates) and never leave a gap. Anything done after a sync
# is generated falls into the next one.
#
# Usage: sync-dates.sh
#
# Output (tab-separated):
#   <window_start>\t<now>\t<new_file_path>\t<week_header>\t<prev_file_path>
#
#   window_start    ISO 8601 UTC. Pass to sync-github.sh and use to filter Slack.
#   now             ISO 8601 UTC. Stamp into the new entry's `generated-at:` marker.
#   new_file_path   Where to write this entry (YYYY-MM-DD.md).
#   week_header     Human header for the entry, e.g. "Week of 22 June".
#   prev_file_path  Most recent existing entry (read it for in-flight items), or "".

set -euo pipefail

SYNC_DIR="$HOME/dev/rs/notes/PostHog/ai-gateway-sync"
mkdir -p "$SYNC_DIR"

today=$(date +%Y-%m-%d)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
week_header="Week of $(date "+%-d %B")"
new_file="${SYNC_DIR}/${today}.md"

prev_file=$(find "$SYNC_DIR" -maxdepth 1 -name "????-??-??.md" -type f 2>/dev/null | sort -r | head -1)
# On a same-day re-run the newest file is today's own entry; ignore it so the
# window stretches back to the actual previous sync, not this morning's run.
if [[ -n "$prev_file" && "$prev_file" == "$new_file" ]]; then
    prev_file=$(find "$SYNC_DIR" -maxdepth 1 -name "????-??-??.md" -type f 2>/dev/null | sort -r | sed -n '2p')
fi

if [[ -n "$prev_file" ]]; then
    window_start=$( { grep -oE 'generated-at: [^ ]+Z' "$prev_file" 2>/dev/null || true; } | head -1 | sed 's/generated-at: //')
    if [[ -z "$window_start" ]]; then
        window_start=$(date -u -r "$prev_file" +%Y-%m-%dT%H:%M:%SZ)
    fi
else
    # No prior sync: default to a week back so nothing is missed.
    if [[ "$OSTYPE" == "darwin"* ]]; then
        window_start=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
    else
        window_start=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)
    fi
fi

echo -e "${window_start}\t${now}\t${new_file}\t${week_header}\t${prev_file}"
