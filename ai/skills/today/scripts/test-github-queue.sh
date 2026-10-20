#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/github-queue.sh"

gh() {
    if [[ "${MOCK_FAIL:-false}" == "true" ]]; then
        return 1
    fi
    local total=1
    [[ "${MOCK_TRUNCATED:-false}" == "true" ]] && total=2
    cat <<JSON
{"data": {
  "review_requests": {"issueCount": 1, "nodes": [{"number": 10, "title": "review me", "url": "u10", "repository": {"nameWithOwner": "PostHog/posthog"}, "author": {"login": "someone"}, "isDraft": false, "createdAt": "2026-10-01T00:00:00Z", "updatedAt": "2026-10-19T00:00:00Z"}]},
  "team_review_requests": {"issueCount": 0, "nodes": []},
  "authored": {"issueCount": ${total}, "nodes": [{"number": 20, "title": "mine", "url": "u20", "repository": {"nameWithOwner": "PostHog/posthog"}, "isDraft": false, "updatedAt": "2026-10-19T00:00:00Z", "reviewDecision": "CHANGES_REQUESTED", "mergeable": "CONFLICTING", "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]}}]},
  "assigned": {"issueCount": 0, "nodes": []},
  "mentions": {"issueCount": 0, "nodes": []}
}}
JSON
}
export -f gh

pass=0
fail=0
check() {
    if [[ "$2" == "$3" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL $1"
        echo "  expected: $3"
        echo "  actual:   $2"
    fi
}

out=$("$script" 2026-10-19T00:00:00Z)
check "review request keeps its author" "$(jq -r '.review_requests[0].author' <<< "$out")" "someone"
check "authored PR carries its check state" "$(jq -r '.authored[0].checks' <<< "$out")" "FAILURE"
check "authored PR carries its review decision" "$(jq -r '.authored[0].reviewDecision' <<< "$out")" "CHANGES_REQUESTED"
check "complete results report no errors" "$(jq -r '.errors | length' <<< "$out")" "0"

out=$(MOCK_TRUNCATED=true "$script" 2026-10-19T00:00:00Z)
check "truncated search is reported" "$(jq -r '.errors[0]' <<< "$out")" "authored truncated: 1 of 2"

status=0
MOCK_FAIL=true "$script" 2026-10-19T00:00:00Z > /dev/null 2>&1 || status=$?
check "failed query fails the pass" "$status" "1"

echo
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
