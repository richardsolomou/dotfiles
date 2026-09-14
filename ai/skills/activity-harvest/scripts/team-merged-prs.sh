#!/bin/bash
# Fetch a team member's merged PRs in a date range.
#
# Usage: team-merged-prs.sh <username> <org> <start_date> [end_date] [limit] [extra_fields]
#
#   username      GitHub handle.
#   org           GitHub org to search within.
#   start_date    YYYY-MM-DD (inclusive).
#   end_date      YYYY-MM-DD (inclusive; defaults to today).
#   limit         Max results (defaults to 200).
#   extra_fields  Comma-prefixed --json extras, e.g. "body" to include PR
#                 descriptions (omit at quarter scale — hundreds of bodies
#                 swamp the context; fetch selectively instead).
#
# Output: JSON array of merged PRs with title, url, closedAt, repository
# (plus any extra fields).

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <username> <org> <start_date> [end_date] [limit] [extra_fields]" >&2
  exit 1
fi

username="$1"
org="$2"
start_date="$3"
end_date="${4:-$(date +%Y-%m-%d)}"
limit="${5:-200}"
extra_fields="${6:-}"

date_regex='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
for d in "$start_date" "$end_date"; do
  if ! [[ "$d" =~ $date_regex ]]; then
    echo "Error: dates must be YYYY-MM-DD, got: $d" >&2
    exit 1
  fi
done

fields="title,url,closedAt,repository"
[[ -n "$extra_fields" ]] && fields="${fields},${extra_fields}"

gh search prs \
  --author="$username" \
  --owner="$org" \
  --merged \
  --merged-at="${start_date}..${end_date}" \
  --limit="$limit" \
  --json "$fields"
