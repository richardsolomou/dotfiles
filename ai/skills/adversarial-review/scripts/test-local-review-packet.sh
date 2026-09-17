#!/usr/bin/env bash

set -euo pipefail

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT

git init -q -b main "$fixture_root/repo"
cd "$fixture_root/repo"
git config user.email test@example.com
git config user.name Test

printf 'base\n' > staged.txt
printf 'base\n' > unstaged.txt
printf 'base\n' > replace.txt
printf 'base\n' > deleted.txt
printf 'tracked before branch deletion\n' > resurrect.probe
printf 'tracked before staged deletion\n' > staged-resurrect.probe
printf 'unchanged filtered file\n' > unchanged.probe
touch -t 202001010000 unchanged.probe
printf 'ignored-marker\n' > ignored.txt
printf 'ignored.txt\nresurrect.probe\nstaged-resurrect.probe\n' > .gitignore
printf 'resurrect.probe filter=probe\nstaged-resurrect.probe filter=probe\nunchanged.probe filter=probe\n' > .gitattributes
git add staged.txt unstaged.txt replace.txt deleted.txt .gitignore .gitattributes
git add -f resurrect.probe staged-resurrect.probe unchanged.probe
git commit -qm base
base_commit=$(git rev-parse HEAD)

printf 'committed change\n' > committed.txt
git rm -q resurrect.probe
git add committed.txt
git commit -qm committed
printf 'ignored resurrection\n' > resurrect.probe
git rm -q staged-resurrect.probe
printf 'ignored staged resurrection\n' > staged-resurrect.probe
printf 'staged change\n' > staged.txt
git add staged.txt
printf 'unstaged change\n' > unstaged.txt
printf 'untracked change\n' > 'new file.txt'
git rm -q replace.txt
printf 'replacement change\n' > replace.txt
rm deleted.txt
ln -s missing-target dangling-link

status_before=$(git status --short)
hashes_before=$(git hash-object -- staged.txt unstaged.txt 'new file.txt' replace.txt)
objects_before=$(find .git/objects -type f | wc -l)
printf '#!/usr/bin/env bash\ntouch %q\n' "$fixture_root/external-diff-ran" > "$fixture_root/external-diff"
chmod +x "$fixture_root/external-diff"
git config diff.external "$fixture_root/external-diff"
git config filter.probe.clean "touch '$fixture_root/filter-ran'; cat"
git config filter.probe.process "touch '$fixture_root/process-filter-ran'; exit 1"
packet=$("$script_dir/local-review-packet.sh" "$base_commit")
packet_fingerprint=$("$script_dir/local-review-packet.sh" "$base_commit" --fingerprint)
[ ! -e "$fixture_root/filter-ran" ]
[ ! -e "$fixture_root/process-filter-ran" ]
[ ! -e "$fixture_root/external-diff-ran" ]
git config --unset filter.probe.clean
git config --unset filter.probe.process
status_after=$(git status --short)
hashes_after=$(git hash-object -- staged.txt unstaged.txt 'new file.txt' replace.txt)
objects_after=$(find .git/objects -type f | wc -l)

grep -F 'committed change' <<< "$packet" >/dev/null
grep -F 'staged change' <<< "$packet" >/dev/null
grep -F 'unstaged change' <<< "$packet" >/dev/null
grep -F 'untracked change' <<< "$packet" >/dev/null
grep -F 'replacement change' <<< "$packet" >/dev/null
grep -F 'diff --git a/deleted.txt b/deleted.txt' <<< "$packet" >/dev/null
grep -F 'dangling-link' <<< "$packet" >/dev/null
[ "${packet%%$'\n'*}" = "LOCAL_REVIEW_FINGERPRINT $packet_fingerprint" ]
if grep -F 'ignored-marker' <<< "$packet" >/dev/null; then
    exit 1
fi
if grep -F 'ignored resurrection' <<< "$packet" >/dev/null; then
    exit 1
fi
if grep -F 'ignored staged resurrection' <<< "$packet" >/dev/null; then
    exit 1
fi
grep -F 'resurrect.probe' <<< "$packet" >/dev/null
grep -F 'staged-resurrect.probe' <<< "$packet" >/dev/null
[ "$(grep -c '^diff --git a/replace.txt b/replace.txt$' <<< "$packet")" -eq 1 ]
[ "$status_before" = "$status_after" ]
[ "$hashes_before" = "$hashes_after" ]
[ "$objects_before" = "$objects_after" ]

fingerprint_before=$("$script_dir/local-review-packet.sh" "$base_commit" --fingerprint)
fingerprint_repeat=$("$script_dir/local-review-packet.sh" "$base_commit" --fingerprint)
[ "$fingerprint_before" = "$fingerprint_repeat" ]
previous_head=$(git rev-parse HEAD)
previous_tree=$(git rev-parse 'HEAD^{tree}')
moved_head=$(printf 'head moved\n' | git commit-tree "$previous_tree" -p "$previous_head")
git update-ref HEAD "$moved_head" "$previous_head"
fingerprint_after_head_move=$("$script_dir/local-review-packet.sh" "$base_commit" --fingerprint)
[ "$fingerprint_before" != "$fingerprint_after_head_move" ]
fingerprint_other_base=$("$script_dir/local-review-packet.sh" HEAD --fingerprint)
[ "$fingerprint_after_head_move" != "$fingerprint_other_base" ]
printf 'mutated\n' >> 'new file.txt'
fingerprint_after=$("$script_dir/local-review-packet.sh" "$base_commit" --fingerprint)
[ "$fingerprint_after_head_move" != "$fingerprint_after" ]

printf '\0binary\n' > binary.dat
binary_packet=$("$script_dir/local-review-packet.sh" "$base_commit")
grep -F 'binary.dat' <<< "$binary_packet" >/dev/null

packet_bytes=$(printf '%s\n' "$binary_packet" | tail -n +2 | wc -c | tr -d ' ')
LOCAL_REVIEW_MAX_PACKET_BYTES=$packet_bytes "$script_dir/local-review-packet.sh" "$base_commit" >/dev/null
set +e
LOCAL_REVIEW_MAX_PACKET_BYTES=$((packet_bytes - 1)) "$script_dir/local-review-packet.sh" "$base_commit" > "$fixture_root/oversized.out" 2> "$fixture_root/oversized.err"
large_status=$?
set -e
[ "$large_status" -eq 3 ]
[ ! -s "$fixture_root/oversized.out" ]
grep -F 'local review packet exceeds' "$fixture_root/oversized.err" >/dev/null

set +e
LOCAL_REVIEW_MAX_INPUT_BYTES=1 "$script_dir/local-review-packet.sh" "$base_commit" > "$fixture_root/input.out" 2> "$fixture_root/input.err"
input_status=$?
LOCAL_REVIEW_MAX_INPUT_FILES=1 "$script_dir/local-review-packet.sh" "$base_commit" >/dev/null 2>&1
count_status=$?
LOCAL_REVIEW_MAX_PACKET_BYTES=invalid "$script_dir/local-review-packet.sh" "$base_commit" >/dev/null 2>&1
limit_status=$?
"$script_dir/local-review-packet.sh" "$base_commit" invalid >/dev/null 2>&1
mode_status=$?
"$script_dir/local-review-packet.sh" >/dev/null 2>&1
arity_status=$?
set -e
[ "$input_status" -eq 6 ]
[ ! -s "$fixture_root/input.out" ]
grep -F 'local review input exceeds' "$fixture_root/input.err" >/dev/null
[ "$count_status" -eq 6 ]
[ "$limit_status" -eq 2 ]
[ "$mode_status" -eq 2 ]
[ "$arity_status" -eq 2 ]

printf '*.probe filter=probe\n' > .gitattributes
printf 'filtered\n' > side-effect.probe
git config filter.probe.clean "touch '$fixture_root/filter-ran'; cat"
git config filter.probe.process "touch '$fixture_root/process-filter-ran'; exit 1"
set +e
"$script_dir/local-review-packet.sh" "$base_commit" >/dev/null 2>&1
filter_status=$?
set -e
[ "$filter_status" -eq 4 ]
[ ! -e "$fixture_root/filter-ran" ]
[ ! -e "$fixture_root/process-filter-ran" ]

git init -q -b main "$fixture_root/corrupt"
cd "$fixture_root/corrupt"
git config user.email test@example.com
git config user.name Test
printf '*.probe filter=probe\n' > .gitattributes
printf 'base\n' > tracked.probe
git add .gitattributes tracked.probe
git commit -qm base
git config filter.probe.clean "touch '$fixture_root/corrupt-filter-ran'; cat"
printf 'bad index\n' > .git/index
set +e
"$script_dir/local-review-packet.sh" HEAD >/dev/null 2>&1
corrupt_status=$?
set -e
[ "$corrupt_status" -ne 0 ]
[ ! -e "$fixture_root/corrupt-filter-ran" ]

git init -q -b main "$fixture_root/outer"
cd "$fixture_root/outer"
git config user.email test@example.com
git config user.name Test
git config advice.addEmbeddedRepo false
printf 'outer\n' > outer.txt
git add outer.txt
git commit -qm base
git init -q -b main nested
git -C nested config user.email test@example.com
git -C nested config user.name Test
printf 'nested\n' > nested/tracked.txt
git -C nested add tracked.txt
git -C nested commit -qm nested
git add nested 2> "$fixture_root/add-nested.err"
git commit -qm gitlink
outer_base=$(git rev-parse HEAD)
printf 'dirty\n' >> nested/tracked.txt
set +e
"$script_dir/local-review-packet.sh" "$outer_base" >/dev/null 2> "$fixture_root/gitlink.err"
gitlink_status=$?
set -e
[ "$gitlink_status" -eq 5 ]
grep -F 'dirty submodules' "$fixture_root/gitlink.err" >/dev/null

git -C nested restore tracked.txt
printf 'updated nested commit\n' > nested/tracked.txt
git -C nested add tracked.txt
git -C nested commit -qm update
git add nested 2> "$fixture_root/update-gitlink.err"
set +e
"$script_dir/local-review-packet.sh" "$outer_base" >/dev/null 2> "$fixture_root/changed-gitlink.err"
changed_gitlink_status=$?
set -e
[ "$changed_gitlink_status" -eq 5 ]
grep -F 'changed gitlinks' "$fixture_root/changed-gitlink.err" >/dev/null
