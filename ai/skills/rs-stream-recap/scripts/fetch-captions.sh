#!/bin/bash
# Pull a YouTube VOD's spoken-word transcript and live chat for writing a stream recap.
#
# Usage: fetch-captions.sh <youtube-url> [output-dir]
#   output-dir defaults to a per-video temp dir; the resolved path is printed at the end.
#
# Writes into output-dir:
#   transcript.txt              cleaned spoken-word transcript (auto-captions, dedup'd, one line) — cheap full-context read
#   transcript-timestamped.txt  the same lines, one per line, each prefixed [HH:MM:SS] (cue start) — to locate a moment in the VOD
#   chat.txt         live chat as "author: message", in order (past livestreams only)
#   <id>.en*.vtt     raw caption track(s), kept for reference
#   <id>.live_chat.json
#
# Ends with a "=== summary ===" block the caller parses: whether the transcript and
# chat are present, and rough sizes.
#
# Why this script exists (do not regress):
#   - yt-dlp is run via `uvx yt-dlp` so nothing is installed permanently; uvx caches it.
#   - YouTube auto-captions are NOT generated immediately for long, freshly-uploaded
#     VODs — they can take a day+. The script handles "not ready yet" gracefully:
#     it still fetches live chat and the summary reports transcript=absent so the
#     caller can tell the user to retry later, rather than failing.
#   - The default `android_vr` client often hides auto-captions; `player_client=web,default`
#     surfaces them. The PO-token / JS-runtime warnings yt-dlp prints are non-fatal —
#     the en track still downloads.
#   - VTT auto-captions repeat each line across rolling cue windows and carry inline
#     <timestamp>/<c> tags; the Python pass strips tags and de-duplicates so the
#     transcript reads as prose, not a wall of repeated fragments.
set -euo pipefail

url="${1:?usage: fetch-captions.sh <youtube-url> [output-dir]}"
outdir="${2:-${TMPDIR:-/tmp}/stream-captions}"

id="$(uvx yt-dlp --no-warnings --print id "$url" 2>/dev/null | head -1)"
if [ -z "$id" ]; then
  echo "error: could not resolve a video id from: $url" >&2
  exit 1
fi
outdir="$outdir/$id"
mkdir -p "$outdir"

echo "fetching captions + chat for $id into $outdir …"

# One pass: English auto-captions (en, en-orig) AND the live_chat subtitle track.
# web,default surfaces auto-captions the android_vr client hides. Non-fatal warnings expected.
uvx yt-dlp \
  --extractor-args "youtube:player_client=web,default" \
  --skip-download \
  --write-auto-subs --write-subs \
  --sub-langs "en,en-orig,live_chat" \
  --sub-format vtt \
  -o "$outdir/%(id)s.%(ext)s" \
  "$url" 2>&1 | grep -Ei "subtitle|caption|live_chat|writing|error" || true

# Prefer en.vtt; fall back to en-orig.vtt.
vtt=""
for cand in "$outdir/$id.en.vtt" "$outdir/$id.en-orig.vtt"; do
  if [ -f "$cand" ]; then vtt="$cand"; break; fi
done

transcript="$outdir/transcript.txt"
transcript_ts="$outdir/transcript-timestamped.txt"
if [ -n "$vtt" ]; then
  python3 - "$vtt" "$transcript" "$transcript_ts" <<'PY'
import re, html, sys
src, dst, dst_ts = sys.argv[1], sys.argv[2], sys.argv[3]
prose, stamped, seen = [], [], set()
cur = None                                       # start time of the current cue, "HH:MM:SS"
for line in open(src, encoding="utf-8").read().splitlines():
    m = re.match(r"(\d{2}:\d{2}:\d{2})\.\d{3}\s+-->", line)
    if m:
        cur = m.group(1)
        continue
    if "-->" in line or line.startswith(("WEBVTT", "Kind:", "Language:")):
        continue
    line = re.sub(r"<[^>]+>", "", line)          # strip <00:00:00.000>, <c> tags
    line = html.unescape(line).strip()
    if not line or line in seen:                 # drop blanks + rolling-window repeats
        continue
    seen.add(line)
    prose.append(line)
    stamped.append(f"[{cur}] {line}" if cur else line)
open(dst, "w", encoding="utf-8").write(re.sub(r"\s+", " ", " ".join(prose)).strip())
open(dst_ts, "w", encoding="utf-8").write("\n".join(stamped) + ("\n" if stamped else ""))
PY
else
  : > "$transcript"
  : > "$transcript_ts"
fi

chatjson="$outdir/$id.live_chat.json"
chat="$outdir/chat.txt"
if [ -f "$chatjson" ]; then
  python3 - "$chatjson" "$chat" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
rows = []
for line in open(src, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    for a in obj.get("replayChatItemAction", {}).get("actions", []):
        r = a.get("addChatItemAction", {}).get("item", {}).get("liveChatTextMessageRenderer")
        if not r:
            continue
        author = r.get("authorName", {}).get("simpleText", "?")
        runs = r.get("message", {}).get("runs", [])
        parts = []
        for run in runs:
            if run.get("text"):
                parts.append(run["text"])
            elif run.get("emoji"):
                sc = run["emoji"].get("shortcuts", [""])
                parts.append("[" + sc[0].strip(":") + "]")
        rows.append(f"{author}: {''.join(parts)}")
open(dst, "w", encoding="utf-8").write("\n".join(rows) + ("\n" if rows else ""))
PY
else
  : > "$chat"
fi

words=$(wc -w < "$transcript" | tr -d ' ')
msgs=$(grep -c '' "$chat" 2>/dev/null || echo 0)
[ -s "$chat" ] || msgs=0

echo "=== summary ==="
echo "video_id:   $id"
echo "outdir:     $outdir"
if [ -s "$transcript" ]; then
  ts_lines=$(grep -c '' "$transcript_ts" 2>/dev/null || echo 0)
  echo "transcript: present ($words words) -> $transcript"
  echo "timestamped: present ($ts_lines lines) -> $transcript_ts"
else
  echo "transcript: ABSENT — auto-captions not generated yet (normal for a fresh long VOD; retry in a day)"
fi
if [ "$msgs" -gt 0 ]; then
  echo "chat:       present ($msgs messages) -> $chat"
else
  echo "chat:       none (not a past livestream, or chat replay unavailable)"
fi
