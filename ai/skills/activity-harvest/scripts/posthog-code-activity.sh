#!/usr/bin/env bash
# posthog-code-activity.sh <window_start> [window_end]
# PostHog Code activity in the window, both halves: cloud tasks (PostHog API)
# and local sessions (~/.posthog-code/sessions). Instants are ISO 8601 UTC.
# Cloud needs a personal API key (tasks:read, project 2) in
# $POSTHOG_PERSONAL_API_KEY or keychain item 'posthog-personal-api-key'.
set -euo pipefail

WINDOW_START="${1:?usage: posthog-code-activity.sh <window_start> [window_end]}"
WINDOW_END="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

USER_ID=345145
PROJECT=2
HOST="https://us.posthog.com"
SESSIONS_DIR="$HOME/.posthog-code/sessions"

# jq helper: ISO instant (fractional seconds / +00:00 offset tolerated) -> epoch
JQ_EPOCH='def epoch: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;'

start_epoch=$(jq -rn --arg t "$WINDOW_START" "$JQ_EPOCH \$t | epoch")
end_epoch=$(jq -rn --arg t "$WINDOW_END" "$JQ_EPOCH \$t | epoch")

echo "== cloud tasks (created_at, repo, title/description)"
api_key="${POSTHOG_PERSONAL_API_KEY:-$(security find-generic-password -s posthog-personal-api-key -w 2>/dev/null || true)}"
if [ -z "$api_key" ]; then
  echo "(no API key — set POSTHOG_PERSONAL_API_KEY or keychain 'posthog-personal-api-key'; fall back to the MCP tasks-list call)"
else
  offset=0
  while :; do
    page=$(curl -sf -H "Authorization: Bearer $api_key" \
      "$HOST/api/projects/$PROJECT/tasks/?created_by=$USER_ID&internal=all&limit=100&offset=$offset") || {
      echo "(cloud fetch failed — fall back to the MCP tasks-list call)"; break; }
    # The endpoint has no date filter; it returns newest-first, so page until past the window.
    jq -r --argjson s "$start_epoch" --argjson e "$end_epoch" "$JQ_EPOCH"'
      .results[]
      | select((.created_at | epoch) >= $s and (.created_at | epoch) < $e)
      | select((.title // "") != "" or (.description // "") != "")
      | select(.repository // "" | ascii_downcase | startswith("posthog/"))
      | [.created_at, .repository, (if .title != "" then .title else .description end | gsub("\\s+"; " ") | .[0:160])]
      | @tsv' <<<"$page"
    oldest=$(jq -r "$JQ_EPOCH"'.results | if length == 0 then empty else last.created_at | epoch end' <<<"$page")
    next=$(jq -r '.next // empty' <<<"$page")
    [ -n "$next" ] && [ -n "$oldest" ] && [ "$oldest" -ge "$start_epoch" ] || break
    offset=$((offset + 100))
  done
fi

echo
echo "== local sessions (first_in_window_prompt_ts, cwd, in-window prompts) — cloud mirrors (/tmp/workspace cwd) excluded"
[ -d "$SESSIONS_DIR" ] || { echo "(no local sessions dir)"; exit 0; }
for f in "$SESSIONS_DIR"/*/logs.ndjson; do
  [ -f "$f" ] || continue
  # mtime is a cheap pre-filter; the real gate is a prompt timestamped inside the window.
  [ "$(stat -f %m "$f")" -ge "$start_epoch" ] || continue
  cwd=$(jq -r 'select(.notification.method == "session/new") | .notification.params.cwd' "$f" 2>/dev/null | head -1)
  case "$cwd" in "" | /tmp/workspace*) continue ;; esac
  jq -rs --argjson s "$start_epoch" --argjson e "$end_epoch" --arg cwd "$cwd" "$JQ_EPOCH"'
    [ .[]
      | select(.notification.method == "session/prompt")
      | select((.timestamp | epoch) >= $s and (.timestamp | epoch) < $e)
      | {ts: .timestamp, text: [.notification.params.prompt[]? | select(.type == "text") | .text] | join(" ")}
      | select(.text != "")
    ]
    | select(length > 0)
    | [ first.ts, $cwd, ([.[].text] | join(" | ") | gsub("\\s+"; " ") | .[0:240]) ]
    | @tsv' "$f" 2>/dev/null
done | sort
