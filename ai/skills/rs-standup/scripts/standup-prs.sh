#!/bin/bash
# Gather GitHub PR activity for a standup entry, since a given date.
#
# Usage: standup-prs.sh <since_date>   # since_date as YYYY-MM-DD (the last standup date)
#
# Emits a single JSON object:
#   {
#     "merged": [ {number, title, repo, merged_at}, ... ],   # merged on/after since_date
#     "active": [ {number, title, repo, isDraft, commits: [headline, ...]}, ... ]
#   }
# Only open PRs with at least one commit on/after since_date appear in "active".
#
# Why this script exists (do not regress):
#   - `gh pr view --json commits` shells out to git and fails with
#     "not a git repository" unless run from inside a clone. We are usually not.
#     Everything here uses `gh api`, which has no working-directory dependency.
#   - `gh search prs --merged` returns stale date filtering; the search/issues
#     API with the `merged:` qualifier is accurate.
#   - Hand-rolling the per-PR commit loop in the agent's shell is error-prone
#     (zsh does not word-split unquoted vars, so naive `set -- $pair` breaks).
#     Keeping it in this bash script sidesteps that entirely.

set -euo pipefail

since="${1:?usage: standup-prs.sh <since_date YYYY-MM-DD>}"
user="richardsolomou"

merged=$(gh api search/issues --method GET \
    -f q="author:${user} is:pr is:merged merged:>=${since} org:PostHog" \
    --jq '[.items[] | {number, title, repo: (.repository_url | sub("https://api.github.com/repos/"; "")), merged_at: .pull_request.merged_at}]')

open_prs=$(gh api search/issues --method GET \
    -f q="author:${user} is:pr is:open org:PostHog" \
    --jq '.items[] | "\(.number)\t\(.repository_url | sub("https://api.github.com/repos/"; ""))\t\(.title)"')

active="[]"
while IFS=$'\t' read -r number repo title; do
    [ -z "${number:-}" ] && continue
    # Commits come oldest-first, so recent ones land on the last page — must
    # paginate. --paginate --jq emits one array per page (not valid as a single
    # document); --slurp wraps the pages into an array-of-arrays, so `add`
    # flattens them before filtering.
    commits=$(gh api "repos/${repo}/pulls/${number}/commits?per_page=100" --paginate --slurp \
        | jq "[(add // []) | .[] | select(.commit.committer.date >= \"${since}\") | .commit.message | split(\"\n\")[0]]")
    # Skip PRs with no commits in the window — no work done on them this period.
    if [ "$(echo "$commits" | jq 'length')" -eq 0 ]; then
        continue
    fi
    isdraft=$(gh api "repos/${repo}/pulls/${number}" --jq '.draft')
    active=$(jq -n \
        --argjson active "$active" \
        --argjson number "$number" \
        --arg title "$title" \
        --arg repo "$repo" \
        --argjson isDraft "$isdraft" \
        --argjson commits "$commits" \
        '$active + [{number: $number, title: $title, repo: $repo, isDraft: $isDraft, commits: $commits}]')
done <<< "$open_prs"

jq -n --argjson merged "$merged" --argjson active "$active" '{merged: $merged, active: $active}'
