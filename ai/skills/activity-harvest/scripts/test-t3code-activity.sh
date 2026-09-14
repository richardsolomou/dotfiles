#!/usr/bin/env bash
# Tests for t3code-activity.sh against a fixture database.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/t3code-activity.sh"
db="$(mktemp -t t3code-activity.XXXXXX)"
trap 'rm -f "$db"' EXIT

sqlite3 "$db" "
CREATE TABLE projection_projects (project_id TEXT PRIMARY KEY, workspace_root TEXT NOT NULL);
CREATE TABLE projection_threads (thread_id TEXT PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL, branch TEXT, deleted_at TEXT);
CREATE TABLE projection_thread_messages (message_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, role TEXT NOT NULL, text TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE projection_thread_pull_requests (thread_id TEXT NOT NULL, url TEXT NOT NULL);
INSERT INTO projection_projects VALUES ('p1', '$HOME/dev/posthog/ai-gateway'), ('p2', '$HOME/dev/tro.gg');
INSERT INTO projection_threads VALUES
  ('in',      'p1', 'Fix failover',     'fix/failover', NULL),
  ('before',  'p1', 'Old work',         NULL,           NULL),
  ('deleted', 'p1', 'Gone',             NULL,           '2026-09-13T00:00:00Z'),
  ('personal','p2', 'Side project',     'main',         NULL);
INSERT INTO projection_thread_messages VALUES
  ('m1', 'in',       'user',      'first prompt',            '2026-09-13T10:00:00.500Z'),
  ('m2', 'in',       'assistant', 'assistant reply',         '2026-09-13T10:01:00Z'),
  ('m3', 'in',       'user',      'second' || char(10) || 'prompt', '2026-09-13T11:00:00Z'),
  ('m4', 'before',   'user',      'too early',               '2026-09-12T09:00:00Z'),
  ('m5', 'deleted',  'user',      'deleted thread prompt',   '2026-09-13T10:30:00Z'),
  ('m6', 'personal', 'user',      'personal prompt',         '2026-09-13T12:00:00Z'),
  ('m7', 'in',       'user',      'after the window',        '2026-09-14T09:00:00Z');
INSERT INTO projection_thread_pull_requests VALUES ('in', 'https://github.com/PostHog/ai-gateway/pull/1');
"

pass=0; fail=0
check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1"; echo "  expected: $3"; echo "  actual:   $2"; fi
}

out="$(T3_STATE_DB="$db" "$script" 2026-09-13T00:00:00Z 2026-09-14T00:00:00Z)"

check "one line per thread with an in-window prompt" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
check "first column is the first in-window prompt instant" "$(printf '%s\n' "$out" | head -1 | cut -f1)" "2026-09-13T10:00:00.500Z"
check "project is relative to ~/dev" "$(printf '%s\n' "$out" | head -1 | cut -f2)" "posthog/ai-gateway"
check "branch, title, and PR url are carried" "$(printf '%s\n' "$out" | head -1 | cut -f3-5)" "$(printf 'fix/failover\tFix failover\thttps://github.com/PostHog/ai-gateway/pull/1')"
check "prompts are joined, newlines flattened, out-of-window prompt excluded" "$(printf '%s\n' "$out" | head -1 | cut -f6)" "first prompt | second prompt"
check "personal project still listed so the caller can drop it" "$(printf '%s\n' "$out" | tail -1 | cut -f2)" "tro.gg"
check "threads with no in-window prompt or deleted are absent" "$(printf '%s\n' "$out" | grep -c 'Old work\|Gone' || true)" "0"

out_empty="$(T3_STATE_DB="$db" "$script" 2026-10-01T00:00:00Z 2026-10-02T00:00:00Z)"
check "empty window prints nothing" "$out_empty" ""

out_missing="$(T3_STATE_DB=/nonexistent/state.sqlite "$script" 2026-09-13T00:00:00Z)"
check "missing database is reported, not fatal" "$out_missing" "(no t3code state at /nonexistent/state.sqlite - t3code pass skipped)"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
