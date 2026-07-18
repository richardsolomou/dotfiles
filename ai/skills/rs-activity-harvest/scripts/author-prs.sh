#!/bin/bash
# Gather authored GitHub PR activity since a given moment.
#
# Usage: author-prs.sh <since> <open-key> <untouched: skip|include>
#
#   since      ISO 8601 instant, e.g. 2026-06-16T18:30:00Z (a bare YYYY-MM-DD
#              also works — treated as that day's start).
#   open-key   JSON key for the open-PR list ("active" for rs-standup,
#              "open" for rs-ai-gateway-weekly-sync).
#   untouched  skip    -> drop open PRs with no commits in the window
#              include -> keep them all (the in-flight backlog)
#
# Emits a single JSON object:
#   {
#     "merged":     [ {number, title, repo, merged_at}, ... ],   # merged at/after since
#     "<open-key>": [ {number, title, repo, isDraft, commits: [headline, ...]}, ... ]
#   }
#
# The GitHub `merged:`/`updated:` qualifiers and commit-date compares all accept
# a full timestamp, and ISO 8601 sorts lexicographically, so sub-day precision
# Just Works — the window starts at the previous entry, not the start of its day.
#
# Why this script exists (do not regress):
#   - `gh pr view --json commits` shells out to git and fails with
#     "not a git repository" unless run from inside a clone. We are usually not.
#     Everything here uses `gh api`, which has no working-directory dependency.
#   - `gh search prs --merged` returns stale date filtering; the search/issues
#     API with the `merged:` qualifier is accurate.
#   - The per-PR commits endpoint pages oldest-first, so recent commits land on
#     the last page — must paginate.

set -euo pipefail

since="${1:?usage: author-prs.sh <since ISO-8601 instant> <open-key> <skip|include>}"
open_key="${2:?open-key required, e.g. active or open}"
untouched="${3:?untouched mode required: skip|include}"
user="richardsolomou"

merged=$(gh api search/issues --method GET \
    -f q="author:${user} is:pr is:merged merged:>=${since} org:PostHog" \
    --jq '[.items[] | {number, title, repo: (.repository_url | sub("https://api.github.com/repos/"; "")), merged_at: .pull_request.merged_at}]')

open_prs=$(gh api search/issues --method GET \
    -f q="author:${user} is:pr is:open org:PostHog" \
    --jq '.items[] | "\(.number)\t\(.repository_url | sub("https://api.github.com/repos/"; ""))\t\(.title)"')

open="[]"
while IFS=$'\t' read -r number repo title; do
    [ -z "${number:-}" ] && continue
    # Commits come oldest-first, so recent ones land on the last page — must
    # paginate. --paginate --jq emits one array per page (not valid as a single
    # document); --slurp wraps the pages into an array-of-arrays, so `add`
    # flattens them before filtering.
    commits=$(gh api "repos/${repo}/pulls/${number}/commits?per_page=100" --paginate --slurp \
        | jq "[(add // []) | .[] | select(.commit.committer.date >= \"${since}\") | .commit.message | split(\"\n\")[0]]")
    if [[ "$untouched" == "skip" && "$(echo "$commits" | jq 'length')" -eq 0 ]]; then
        continue
    fi
    isdraft=$(gh api "repos/${repo}/pulls/${number}" --jq '.draft')
    open=$(jq -n \
        --argjson open "$open" \
        --argjson number "$number" \
        --arg title "$title" \
        --arg repo "$repo" \
        --argjson isDraft "$isdraft" \
        --argjson commits "$commits" \
        '$open + [{number: $number, title: $title, repo: $repo, isDraft: $isDraft, commits: $commits}]')
done <<< "$open_prs"

jq -n --argjson merged "$merged" --argjson open "$open" --arg key "$open_key" \
    '{merged: $merged} + {($key): $open}'
