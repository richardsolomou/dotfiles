#!/bin/bash
# List open GitHub work waiting on Richard, in one GraphQL round trip.
#
# Usage: github-queue.sh <since>
#
#   since  ISO 8601 instant; bounds the mentions search only. The other lists
#          are current state, not activity.
#
# Emits a single JSON object:
#   {
#     "review_requests":            [ {number, title, url, repo, author, isDraft, createdAt, updatedAt} ],
#     "team_review_requests":       [ same shape, oldest first, capped at 50 ],
#     "team_review_requests_total": <n>,
#     "authored":                   [ {number, title, url, repo, isDraft, updatedAt, reviewDecision, mergeable, checks} ],
#     "assigned":                   [ {number, title, url, repo, updatedAt} ],
#     "mentions":                   [ {number, title, url, repo, author, updatedAt} ],
#     "errors":                     [ "<list> truncated: <captured> of <total>" ]
#   }
#
# `user-review-requested:` is direct requests only; `review-requested:` would
# also match every team request, which is what the team list is for.

set -euo pipefail

since="${1:?usage: github-queue.sh <since>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../sprint-planning/scripts/config.sh"
user="richardsolomou"

read -r -d '' query <<'GRAPHQL' || true
fragment pr on PullRequest { number title url repository { nameWithOwner } author { login } isDraft createdAt updatedAt }
query($reviews: String!, $team: String!, $authored: String!, $assigned: String!, $mentions: String!) {
  review_requests: search(type: ISSUE, query: $reviews, first: 50) { issueCount nodes { ...pr } }
  team_review_requests: search(type: ISSUE, query: $team, first: 50) { issueCount nodes { ...pr } }
  authored: search(type: ISSUE, query: $authored, first: 50) { issueCount nodes { ... on PullRequest {
    number title url repository { nameWithOwner } isDraft updatedAt reviewDecision mergeable
    commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } }
  assigned: search(type: ISSUE, query: $assigned, first: 50) { issueCount nodes { ... on Issue { number title url repository { nameWithOwner } updatedAt } } }
  mentions: search(type: ISSUE, query: $mentions, first: 50) { issueCount nodes {
    ... on Issue { number title url repository { nameWithOwner } author { login } updatedAt }
    ... on PullRequest { number title url repository { nameWithOwner } author { login } updatedAt } } }
}
GRAPHQL

gh api graphql -f query="$query" \
    -f reviews="is:open is:pr archived:false user-review-requested:${user}" \
    -f team="is:open is:pr draft:false archived:false team-review-requested:${SPRINT_ORG}/${SPRINT_TEAM_SLUG} sort:created-asc" \
    -f authored="is:open is:pr archived:false author:${user} org:${SPRINT_ORG}" \
    -f assigned="is:open is:issue archived:false assignee:${user} org:${SPRINT_ORG}" \
    -f mentions="is:open archived:false mentions:${user} -author:${user} updated:>=${since} org:${SPRINT_ORG}" \
    | jq '.data
        | def flat: .nodes | map(. + {repo: .repository.nameWithOwner} | del(.repository) | if .author then .author = .author.login else . end);
          def truncated($k): select((.[$k].nodes | length) < .[$k].issueCount) | "\($k) truncated: \(.[$k].nodes | length) of \(.[$k].issueCount)";
        {
          review_requests: (.review_requests | flat),
          team_review_requests: (.team_review_requests | flat),
          team_review_requests_total: .team_review_requests.issueCount,
          authored: (.authored | flat | map(.checks = .commits.nodes[0].commit.statusCheckRollup.state | del(.commits))),
          assigned: (.assigned | flat),
          mentions: (.mentions | flat),
          errors: [truncated("review_requests", "authored", "assigned", "mentions")]
        }'
