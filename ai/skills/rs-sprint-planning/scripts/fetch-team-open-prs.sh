#!/bin/bash
# Fetch a GitHub user's currently-open PRs (including drafts) across all repos in
# the configured org. These surface in-flight work the merged-PR query misses:
# open PRs from the sprint window are "in progress" (🟡) retro items, and open
# PRs generally seed the Plan. isDraft separates early/WIP work from review-ready.
#
# Usage: fetch-team-open-prs.sh <username>
#
# Output: JSON array of open PRs with title, body, url, isDraft, createdAt,
# updatedAt, and repository fields.

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <username>" >&2
  exit 1
fi

username="$1"

gh search prs \
  --author="$username" \
  --owner="$SPRINT_ORG" \
  --state=open \
  --limit=200 \
  --json title,body,url,isDraft,createdAt,updatedAt,repository
