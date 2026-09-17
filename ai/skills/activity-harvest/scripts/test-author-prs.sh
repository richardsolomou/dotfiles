#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/author-prs.sh"

gh() {
    case "$*" in
        *"is:merged"*)
            if [[ "${MOCK_TRUNCATED:-false}" == "true" ]]; then
                printf '%s\n' '[{"total_count":2,"items":[{"number":1,"title":"captured","repository_url":"https://api.github.com/repos/PostHog/repo","pull_request":{"merged_at":"2026-09-17T10:00:00Z"}}]}]'
            else
                printf '%s\n' '[{"total_count":2,"items":[{"number":1,"title":"inside","repository_url":"https://api.github.com/repos/PostHog/repo","pull_request":{"merged_at":"2026-09-17T10:00:00Z"}},{"number":2,"title":"at end","repository_url":"https://api.github.com/repos/PostHog/repo","pull_request":{"merged_at":"2026-09-18T00:00:00Z"}}]}]'
            fi
            ;;
        *"is:open"*)
            printf '%s\n' '[{"total_count":0,"items":[]}]'
            ;;
        *)
            return 1
            ;;
    esac
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

out=$("$script" 2026-09-17T00:00:00Z 2026-09-18T00:00:00Z active skip)
check "half-open merge window" "$(jq -r '.merged | map(.title) | join(",")' <<< "$out")" "inside"
check "requested open key is present" "$(jq -r '.active | length' <<< "$out")" "0"

status=0
MOCK_TRUNCATED=true "$script" 2026-09-17T00:00:00Z 2026-09-18T00:00:00Z active skip >/dev/null 2>&1 || status=$?
check "truncated search fails the pass" "$status" "1"

echo
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
