#!/usr/bin/env bash
# t3code-activity.sh <window_start> <window_end>
# Threads in T3 Code's local state that received a prompt inside the window.
# Instants are ISO 8601 UTC. One tab-separated line per thread:
#   first_in_window_prompt_ts  project  branch  title  pr_urls  in-window prompts
# The database is read in place, read-only; the desktop app can stay open.
# T3_STATE_DB overrides the database path (tests point it at a fixture).
# Exits 3 when the database looks abandoned or lacks the expected tables, since
# T3 Code has moved its state before and an empty result would hide that.
set -euo pipefail

WINDOW_START="${1:?usage: t3code-activity.sh <window_start> <window_end>}"
WINDOW_END="${2:?window_end required}"
DB="${T3_STATE_DB:-$HOME/.t3/userdata/statev2.sqlite}"

# The instants are spliced into SQL below, so only accept ISO 8601 shapes.
for instant in "$WINDOW_START" "$WINDOW_END"; do
  [[ "$instant" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$ ]] \
    || { echo "not an ISO 8601 instant: $instant" >&2; exit 2; }
done

command -v sqlite3 > /dev/null 2>&1 || { echo "(sqlite3 not installed - T3 Code pass skipped)"; exit 0; }
[ -r "$DB" ] || { echo "(no T3 Code state at $DB - T3 Code pass skipped)"; exit 0; }

for table in projection_projects orchestration_v2_projection_threads orchestration_v2_projection_messages; do
  [ -n "$(sqlite3 -readonly "$DB" "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$table'")" ] \
    || { echo "T3 Code state at $DB has no $table table; its schema changed" >&2; exit 3; }
done

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
last_write=$(mtime "$DB")
[ -e "$DB-wal" ] && [ "$(mtime "$DB-wal")" -gt "$last_write" ] && last_write=$(mtime "$DB-wal")
if [ "$last_write" -lt "$(sqlite3 :memory: "SELECT strftime('%s', '$WINDOW_START')")" ]; then
  echo "T3 Code state at $DB has not been written since the window started; T3 Code may have moved its database" >&2
  exit 3
fi

# Compare as epochs so a fractional-second or +00:00 instant still lands.
sqlite3 -readonly -separator $'\t' "$DB" "
WITH window AS (
  SELECT strftime('%s', '$WINDOW_START') AS s, strftime('%s', '$WINDOW_END') AS e
),
prompts AS (
  SELECT m.thread_id, m.created_at, json_extract(m.payload_json, '$.text') AS text
  FROM orchestration_v2_projection_messages m, window w
  WHERE m.role = 'user'
    AND strftime('%s', m.created_at) >= w.s
    AND strftime('%s', m.created_at) < w.e
  ORDER BY m.created_at
),
prs AS (
  SELECT t.thread_id, group_concat(json_extract(pr.value, '$.url'), ' ') AS urls
  FROM orchestration_v2_projection_threads t, json_each(t.payload_json, '$.pullRequests') pr
  GROUP BY t.thread_id
)
SELECT min(p.created_at),
       replace(replace(proj.workspace_root, '$HOME/dev/', ''), '$HOME/', '~/'),
       coalesce(json_extract(t.payload_json, '$.branch'), ''),
       replace(t.title, char(9), ' '),
       coalesce(prs.urls, ''),
       substr(replace(replace(group_concat(p.text, ' | '), char(10), ' '), char(9), ' '), 1, 240)
FROM prompts p
JOIN orchestration_v2_projection_threads t ON t.thread_id = p.thread_id AND t.deleted_at IS NULL
JOIN projection_projects proj ON proj.project_id = t.project_id
LEFT JOIN prs ON prs.thread_id = t.thread_id
GROUP BY t.thread_id
ORDER BY 1;
"
