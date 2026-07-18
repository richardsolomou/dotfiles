#!/bin/bash
# One-call GitHub harvest for a cadence window: the authored-PR pass plus the
# wider searches and the per-repo comment sweeps, run concurrently, emitted as
# a single JSON object. Wraps author-prs.sh — see its header for the hard-won
# query lore (gh api over gh pr, pagination direction, stale search filters).
#
# Usage: github-harvest.sh <since> <open-key> <untouched: skip|include>
#   Arguments pass through to author-prs.sh; see its header.
#
# Output JSON:
#   {
#     "merged": [...], "<open-key>": [...],                # author-prs.sh passthrough
#     "involved": [{number,title,state,url,repo,is_pr}],   # authored/commented/mentioned/assigned, updated in window
#     "reviewed": [{number,title,state,url,repo}],         # `involves:` does not cover reviews
#     "issue_comments":  [{repo,issue,created_at,body}],   # your comments, every surfaced repo
#     "review_comments": [{repo,pr,created_at,body}],      # your inline review comments
#     "reviews": [{repo,pr,submitted_at,state,body}],      # reviews on reviewed PRs that left no inline comments
#     "errors": [...]                                      # partial failures — surface these, never ignore
#   }
#
# Comment/review bodies are truncated to 500 chars — enough to identify the
# thread; fetch the full text with gh when a digest needs more.
#
# Concurrency: the search API throttles concurrent queries (secondary rate
# limits), so the two extra searches run serially in one lane alongside
# author-prs.sh; the per-repo REST sweeps fan out freely.

set -euo pipefail
shopt -s nullglob

since="${1:?usage: github-harvest.sh <since ISO-8601 instant> <open-key> <skip|include>}"
open_key="${2:?open-key required, e.g. active or open}"
untouched="${3:?untouched mode required: skip|include}"
user="richardsolomou"

here=$(cd "$(dirname "$0")" && pwd)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

: > "$dir/errors.txt"
note() { echo "$1" >> "$dir/errors.txt"; echo "warning: $1" >&2; }

strip='sub("https://api.github.com/repos/"; "")'

"$here/author-prs.sh" "$since" "$open_key" "$untouched" > "$dir/author.json" &
author_pid=$!

{
    gh api search/issues --method GET -f per_page=100 \
        -f q="involves:${user} updated:>=${since} org:PostHog" \
        --jq "[.items[] | {number, title, state, url: .html_url, repo: (.repository_url | ${strip}), is_pr: (.pull_request != null)}]" \
        > "$dir/involved.json" || { echo '[]' > "$dir/involved.json"; note "involves search failed"; }
    gh api search/issues --method GET -f per_page=100 \
        -f q="reviewed-by:${user} is:pr updated:>=${since} org:PostHog" \
        --jq "[.items[] | {number, title, state, url: .html_url, repo: (.repository_url | ${strip})}]" \
        > "$dir/reviewed.json" || { echo '[]' > "$dir/reviewed.json"; note "reviewed-by search failed"; }
} &
search_pid=$!

wait "$author_pid" || { echo "{\"merged\": [], \"${open_key}\": []}" > "$dir/author.json"; note "author-prs.sh failed"; }
wait "$search_pid"

repos=$(jq -r '.. | objects | .repo? // empty' "$dir/author.json" "$dir/involved.json" "$dir/reviewed.json" | sort -u)

# The comment endpoints return ALL users' comments; --paginate is load-bearing —
# on a busy repo more than a page arrives within even a one-day window, silently
# dropping yours. --slurp wraps the per-page arrays; `add` flattens them.
i=0
for repo in $repos; do
    i=$((i + 1))
    gh api "repos/${repo}/issues/comments?since=${since}&per_page=100" --paginate --slurp \
        | jq --arg repo "$repo" --arg user "$user" \
            '[(add // []) | .[] | select(.user.login == $user)
              | {repo: $repo, issue: (.issue_url | split("/") | last), created_at, body: ((.body // "")[0:500])}]' \
        > "$dir/ic_${i}.json" || { echo '[]' > "$dir/ic_${i}.json"; note "issue comments failed: $repo"; } &
    gh api "repos/${repo}/pulls/comments?since=${since}&per_page=100" --paginate --slurp \
        | jq --arg repo "$repo" --arg user "$user" \
            '[(add // []) | .[] | select(.user.login == $user)
              | {repo: $repo, pr: (.pull_request_url | split("/") | last), created_at, body: ((.body // "")[0:500])}]' \
        > "$dir/rc_${i}.json" || { echo '[]' > "$dir/rc_${i}.json"; note "review comments failed: $repo"; } &
done
wait

collect() {
    local out="$1"; shift
    if (($#)); then jq -s 'add' "$@" > "$out"; else echo '[]' > "$out"; fi
}
collect "$dir/issue_comments.json" "$dir"/ic_*.json
collect "$dir/review_comments.json" "$dir"/rc_*.json

# Reviews with only a summary (or only resolved threads) leave no trace on the
# comments endpoints — check the reviews endpoint for every reviewed PR that
# surfaced no inline comments above.
have=$(jq -r '.[] | "\(.repo)#\(.pr)"' "$dir/review_comments.json")
j=0
while IFS=$'\t' read -r repo number; do
    [ -z "$repo" ] && continue
    grep -qxF "${repo}#${number}" <<< "$have" && continue
    j=$((j + 1))
    gh api "repos/${repo}/pulls/${number}/reviews?per_page=100" --paginate --slurp \
        | jq --arg repo "$repo" --arg n "$number" --arg user "$user" --arg since "$since" \
            '[(add // []) | .[] | select(.user.login == $user and .submitted_at != null and .submitted_at >= $since)
              | {repo: $repo, pr: $n, submitted_at, state, body: ((.body // "")[0:500])}]' \
        > "$dir/rv_${j}.json" || { echo '[]' > "$dir/rv_${j}.json"; note "reviews failed: ${repo}#${number}"; } &
done < <(jq -r '.[] | "\(.repo)\t\(.number)"' "$dir/reviewed.json")
wait
collect "$dir/reviews.json" "$dir"/rv_*.json

jq -n \
    --slurpfile author "$dir/author.json" \
    --slurpfile involved "$dir/involved.json" \
    --slurpfile reviewed "$dir/reviewed.json" \
    --slurpfile ic "$dir/issue_comments.json" \
    --slurpfile rc "$dir/review_comments.json" \
    --slurpfile rv "$dir/reviews.json" \
    --rawfile errs "$dir/errors.txt" \
    '$author[0] + {
        involved: $involved[0], reviewed: $reviewed[0],
        issue_comments: $ic[0], review_comments: $rc[0], reviews: $rv[0],
        errors: ($errs | split("\n") | map(select(length > 0)))
    }'
