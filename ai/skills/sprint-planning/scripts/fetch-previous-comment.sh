#!/bin/bash
# Fetch the LLM Analytics team's sprint planning comment from a given
# sprint issue.
#
# Searches issue comments for one containing "# Team LLM Analytics".
# Returns the comment body, or "NOT_FOUND" if no matching comment exists.
#
# Usage: fetch-previous-comment.sh <issue_number>
#
# Output: The full comment body text, or the literal string "NOT_FOUND".

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <issue_number>" >&2
  exit 1
fi

issue_number="$1"

if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
  echo "Error: issue_number must be numeric, got: $issue_number" >&2
  exit 1
fi

# Match "LLM Analytics" to find our team's comment.
comment=$(gh api "repos/PostHog/posthog/issues/${issue_number}/comments?per_page=100" \
  --paginate \
  --jq '[.[] | select(.body | test("# Team LLM Analytics"))] | first | .body // empty' \
  2>/dev/null) || comment=""

if [[ -z "$comment" ]]; then
  echo "NOT_FOUND"
else
  echo "$comment"
fi
