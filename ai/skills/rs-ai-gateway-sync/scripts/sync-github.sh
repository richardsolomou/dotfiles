#!/bin/bash
# Gather GitHub PR activity for an AI Gateway weekly sync, since a given moment.
#
# Usage: sync-github.sh <since>   # since as an ISO 8601 instant, e.g. 2026-06-16T18:30:00Z
#                                 # (the previous sync's window_start). A bare
#                                 # YYYY-MM-DD also works (treated as that day's start).
#
# Emits a single JSON object:
#   {
#     "merged": [ {number, title, repo, merged_at}, ... ],
#     "open":   [ {number, title, repo, isDraft, recentCommits: [headline, ...]}, ... ]
#   }
#
# Both serve the two halves of the sync:
#   - Last week = "merged" + every "open" PR whose recentCommits is non-empty
#     (in-flight work touched in the window).
#   - This week focus = every "open" PR (the in-flight backlog), regardless of
#     recent commits — a PR untouched this week may still be the focus next week.
#
# The GitHub `merged:` qualifier and commit-date compares accept a full
# timestamp, and ISO 8601 sorts lexicographically, so sub-day precision Just
# Works — the window starts at the previous sync, not the start of its day.
#
# Why a script (do not regress, mirrors rs-standup/scripts/standup-prs.sh):
#   - `gh pr view --json commits` shells out to git and fails outside a clone;
#     everything here uses `gh api`, which has no working-directory dependency.
#   - `gh search prs --merged` returns stale date filtering; the search/issues
#     API with the `merged:` qualifier is accurate.
#   - The per-PR commits endpoint pages oldest-first, so recent commits land on
#     the last page — must paginate.

set -euo pipefail

since="${1:?usage: sync-github.sh <since ISO-8601 instant, e.g. 2026-06-16T18:30:00Z>}"
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
    commits=$(gh api "repos/${repo}/pulls/${number}/commits?per_page=100" --paginate --slurp \
        | jq "[(add // []) | .[] | select(.commit.committer.date >= \"${since}\") | .commit.message | split(\"\n\")[0]]")
    isdraft=$(gh api "repos/${repo}/pulls/${number}" --jq '.draft')
    open=$(jq -n \
        --argjson open "$open" \
        --argjson number "$number" \
        --arg title "$title" \
        --arg repo "$repo" \
        --argjson isDraft "$isdraft" \
        --argjson commits "$commits" \
        '$open + [{number: $number, title: $title, repo: $repo, isDraft: $isDraft, recentCommits: $commits}]')
done <<< "$open_prs"

jq -n --argjson merged "$merged" --argjson open "$open" '{merged: $merged, open: $open}'
