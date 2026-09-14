#!/bin/bash
# Detect the current and next calendar quarter and the key planning dates.
#
# Usage: detect-quarter.sh [YYYY-MM-DD]   (defaults to today)
#
# Output format (tab-separated, single line):
#   cur_label\tcur_start\tcur_end\tnext_label\tnext_start\tnext_end\tdays_until_cur_end

set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$dir/quarter.py" "$@"
