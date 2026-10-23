#!/usr/bin/env bash
# Tests for activity-days.sh in a fixed timezone.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/activity-days.sh"
export TZ=Europe/Athens

pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1"; echo "  expected: $3"; echo "  actual:   $2"; fi
}

out="$("$script" 2026-10-21T09:53:50Z 2026-10-23T08:43:48Z /notes)"
check "one line per day through today" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "3"
check "first day starts at the window start and ends at local midnight" "$(printf '%s\n' "$out" | head -1 | cut -f1,2)" "$(printf '2026-10-21T09:53:50Z\t2026-10-21T21:00:00Z')"
check "first day has its own file and header" "$(printf '%s\n' "$out" | head -1 | cut -f3,4)" "$(printf '/notes/2026-10-21.md\t21 October')"
check "today runs from local midnight to now" "$(printf '%s\n' "$out" | tail -1 | cut -f1,2)" "$(printf '2026-10-22T21:00:00Z\t2026-10-23T08:43:48Z')"
check "today has its own file" "$(printf '%s\n' "$out" | tail -1 | cut -f3)" "/notes/2026-10-23.md"

out="$("$script" 2026-10-23T07:00:00Z 2026-10-23T08:00:00Z /notes)"
check "same-day window stays one entry" "$(printf '%s\n' "$out" | cut -f1-3)" "$(printf '2026-10-23T07:00:00Z\t2026-10-23T08:00:00Z\t/notes/2026-10-23.md')"

echo "activity-days: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
