#!/bin/bash
# Gather authored GitHub PR activity since a given moment.
#
# Usage: author-prs.sh <since> <until> <open-key> <untouched: skip|include>
#
#   since      ISO 8601 instant, e.g. 2026-06-16T18:30:00Z (a bare YYYY-MM-DD
#              also works — treated as that day's start).
#   until      Exclusive ISO 8601 end instant for the activity window.
#   open-key   JSON key for the open-PR list ("active" for standup,
#              "open" for standup weekly mode).
#   untouched  skip    -> drop open PRs with no commits in the window
#              include -> keep them all (the in-flight backlog)
#
# Emits a single JSON object:
#   {
#     "merged":     [ {number, title, repo, merged_at}, ... ],   # merged in [since, until)
#     "<open-key>": [ {number, title, repo, isDraft, commits: [headline, ...]}, ... ]
#   }
#
# The GitHub `merged:`/`updated:` qualifiers and commit-date compares all accept
# a full timestamp, and ISO 8601 sorts lexicographically, so sub-day precision
# Just Works — the window is the immutable half-open interval [since, until).
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

since="${1:?usage: author-prs.sh <since> <until> <open-key> <skip|include>}"
until="${2:?until ISO-8601 instant required}"
open_key="${3:?open-key required, e.g. active or open}"
untouched="${4:?untouched mode required: skip|include}"
user="richardsolomou"

require_complete_search() {
    local label="$1" payload="$2" total captured
    total=$(jq '.[0].total_count // 0' <<< "$payload")
    captured=$(jq '[.[].items[]] | length' <<< "$payload")
    if ((captured < total)); then
        echo "${label} search truncated: captured ${captured} of ${total}" >&2
        return 1
    fi
}

merged_pages=$(gh api search/issues --method GET -f per_page=100 \
    -f q="author:${user} is:pr is:merged merged:${since}..${until} org:PostHog" \
    --paginate --slurp)
require_complete_search "merged PR" "$merged_pages"
merged=$(jq --arg since "$since" --arg until "$until" \
        '[.[].items[] | select(.pull_request.merged_at >= $since and .pull_request.merged_at < $until)
          | {number, title, repo: (.repository_url | sub("https://api.github.com/repos/"; "")), merged_at: .pull_request.merged_at}]' \
        <<< "$merged_pages")

open_pages=$(gh api search/issues --method GET -f per_page=100 \
    -f q="author:${user} is:pr is:open org:PostHog" \
    --paginate --slurp)
require_complete_search "open PR" "$open_pages"
open_prs=$(jq -r '.[] | .items[] | "\(.number)\t\(.repository_url | sub("https://api.github.com/repos/"; ""))\t\(.title)"' <<< "$open_pages")

open="[]"
while IFS=$'\t' read -r number repo title; do
    [ -z "${number:-}" ] && continue
    # Commits come oldest-first, so recent ones land on the last page — must
    # paginate. --paginate --jq emits one array per page (not valid as a single
    # document); --slurp wraps the pages into an array-of-arrays, so `add`
    # flattens them before filtering.
    commits=$(gh api "repos/${repo}/pulls/${number}/commits?per_page=100" --paginate --slurp \
        | jq --arg since "$since" --arg until "$until" \
            '[(add // []) | .[] | select(.commit.committer.date >= $since and .commit.committer.date < $until) | .commit.message | split("\n")[0]]')
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
