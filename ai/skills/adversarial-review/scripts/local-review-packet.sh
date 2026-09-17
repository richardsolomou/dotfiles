#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: local-review-packet.sh <base-ref> [--fingerprint]" >&2
    exit 2
fi

base_ref=$1
mode=${2:-packet}

if [ "$mode" != "packet" ] && [ "$mode" != "--fingerprint" ]; then
    echo "usage: local-review-packet.sh <base-ref> [--fingerprint]" >&2
    exit 2
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
captured_head=$(git rev-parse HEAD)
merge_base=$(git merge-base "$base_ref" "$captured_head")
index_file=$(mktemp)
packet_file=$(mktemp)
paths_file=$(mktemp)
untracked_file=$(mktemp)
all_paths_file=$(mktemp)
attributes_input=$(mktemp)
candidate_input=$(mktemp)
size_paths_file=$(mktemp)
sizes_file=$(mktemp)
attributes_file=$(mktemp)
stages_file=$(mktemp)
gitlink_changes_file=$(mktemp)
object_dir=$(mktemp -d)
trap 'rm -f "$index_file" "$packet_file" "$paths_file" "$untracked_file" "$all_paths_file" "$attributes_input" "$candidate_input" "$size_paths_file" "$sizes_file" "$attributes_file" "$stages_file" "$gitlink_changes_file"; rm -rf "${object_dir:?}"' EXIT
rm -f "$index_file"

git ls-files --cached --others --exclude-standard -z > "$all_paths_file"
mapfile -d '' all_paths < "$all_paths_file"
attribute_paths=()
for path in "${all_paths[@]}"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
        attribute_paths+=("$path")
    fi
done

safe_git=(git)
declare -A seen_filter_drivers=()
if [ "${#attribute_paths[@]}" -gt 0 ]; then
    printf '%s\0' "${attribute_paths[@]}" > "$attributes_input"
    git check-attr -z --stdin filter < "$attributes_input" > "$attributes_file"
    mapfile -d '' all_filter_attributes < "$attributes_file"
    for ((i = 2; i < ${#all_filter_attributes[@]}; i += 3)); do
        value=${all_filter_attributes[$i]}
        if [ "$value" = "unspecified" ] || [ "$value" = "unset" ] || [ -n "${seen_filter_drivers[$value]:-}" ]; then
            continue
        fi
        seen_filter_drivers[$value]=1
        safe_git+=(-c "filter.$value.process=" -c "filter.$value.clean=cat" -c "filter.$value.required=false")
    done
fi

"${safe_git[@]}" ls-files --modified --deleted -z > "$paths_file"
git ls-files --others --exclude-standard -z > "$untracked_file"
mapfile -d '' candidate_paths < "$paths_file"
mapfile -O "${#candidate_paths[@]}" -d '' candidate_paths < "$untracked_file"
if [ "${#candidate_paths[@]}" -gt 0 ]; then
    printf '%s\0' "${candidate_paths[@]}" > "$candidate_input"
fi

max_input_files=${LOCAL_REVIEW_MAX_INPUT_FILES:-10000}
max_input_bytes=${LOCAL_REVIEW_MAX_INPUT_BYTES:-$((100 * 1024 * 1024))}
for limit in "$max_input_files" "$max_input_bytes"; do
    case $limit in
        '' | *[!0-9]* | 0)
            echo "LOCAL_REVIEW_MAX_INPUT_FILES and LOCAL_REVIEW_MAX_INPUT_BYTES must be positive integers" >&2
            exit 2
            ;;
    esac
done
if [ "${#candidate_paths[@]}" -gt "$max_input_files" ]; then
    echo "local review input exceeds $max_input_files changed or untracked files; narrow the target" >&2
    exit 6
fi

filter_paths=()
sized_paths=()
for path in "${candidate_paths[@]}"; do
    if [ -L "$path" ] || [ -f "$path" ]; then
        sized_paths+=("$path")
    elif [ -d "$path" ]; then
        echo "local review packet refuses embedded repositories at $path; review nested repositories separately" >&2
        exit 5
    elif [ -e "$path" ]; then
        echo "local review input contains unsupported file type at $path; use a safe manual packet" >&2
        exit 6
    else
        continue
    fi
    filter_paths+=("$path")
done

input_bytes=0
if [ "${#sized_paths[@]}" -gt 0 ]; then
    printf '%s\0' "${sized_paths[@]}" > "$size_paths_file"
    if stat -f '%z' -- /dev/null >/dev/null 2>&1; then
        xargs -0 stat -f '%z' -- < "$size_paths_file" > "$sizes_file"
    else
        xargs -0 stat -c '%s' -- < "$size_paths_file" > "$sizes_file"
    fi
    input_bytes=$(awk '{ total += $1 } END { print total + 0 }' "$sizes_file")
fi
if [ "$input_bytes" -gt "$max_input_bytes" ]; then
    echo "local review input exceeds $max_input_bytes bytes; narrow the target or exclude generated artifacts" >&2
    exit 6
fi

if [ "${#filter_paths[@]}" -gt 0 ]; then
    printf '%s\0' "${filter_paths[@]}" > "$attributes_input"
    git check-attr -z --stdin filter < "$attributes_input" > "$attributes_file"
    mapfile -d '' filter_attributes < "$attributes_file"
    for ((i = 2; i < ${#filter_attributes[@]}; i += 3)); do
        value=${filter_attributes[$i]}
        if [ "$value" != "unspecified" ] && [ "$value" != "unset" ]; then
            echo "local review packet refuses changed paths with clean filters; use a safe manual packet" >&2
            exit 4
        fi
    done
fi

git ls-files --stage -z > "$stages_file"
while IFS= read -r -d '' entry; do
    metadata=${entry%%$'\t'*}
    path=${entry#*$'\t'}
    entry_mode=${metadata%% *}
    if [ "$entry_mode" != "160000" ]; then
        continue
    fi
    set +e
    git diff-files --quiet --ignore-submodules=none -- "$path"
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
        continue
    fi
    if [ "$status" -eq 1 ]; then
        echo "local review packet refuses dirty submodules at $path; review nested repositories separately" >&2
        exit 5
    fi
    exit "$status"
done < "$stages_file"

git_common_dir=$(git rev-parse --git-common-dir)
real_objects=$(cd "$git_common_dir/objects" && pwd -P)
export GIT_OBJECT_DIRECTORY=$object_dir
export GIT_ALTERNATE_OBJECT_DIRECTORIES=$real_objects

real_index=$(git rev-parse --git-path index)
if [ ! -f "$real_index" ]; then
    echo "local review packet requires an existing Git index" >&2
    exit 2
fi
cp -- "$real_index" "$index_file"
if [ "${#candidate_paths[@]}" -gt 0 ]; then
    GIT_INDEX_FILE=$index_file "${safe_git[@]}" add -A --pathspec-from-file="$candidate_input" --pathspec-file-nul
fi
snapshot_tree_oid=$(GIT_INDEX_FILE=$index_file git write-tree)
git diff --raw --no-renames --no-ext-diff "$merge_base" "$snapshot_tree_oid" -- > "$gitlink_changes_file"
if grep -Eq '^:160000 |^:[0-9]{6} 160000 ' "$gitlink_changes_file"; then
    echo "local review packet refuses changed gitlinks or embedded repositories; review nested repositories separately" >&2
    exit 5
fi

max_packet_bytes=${LOCAL_REVIEW_MAX_PACKET_BYTES:-$((10 * 1024 * 1024))}
case $max_packet_bytes in
    '' | *[!0-9]* | 0)
        echo "LOCAL_REVIEW_MAX_PACKET_BYTES must be a positive integer" >&2
        exit 2
        ;;
esac

set +o pipefail
git diff --no-ext-diff --no-textconv "$merge_base" "$snapshot_tree_oid" -- \
    | head -c "$((max_packet_bytes + 1))" > "$packet_file"
diff_status=${PIPESTATUS[0]}
set -o pipefail
packet_bytes=$(wc -c < "$packet_file")

if [ "$packet_bytes" -gt "$max_packet_bytes" ]; then
    echo "local review packet exceeds $max_packet_bytes bytes; narrow the target or exclude generated artifacts" >&2
    exit 3
fi
if [ "$diff_status" -ne 0 ]; then
    exit "$diff_status"
fi

if [ "$mode" = "--fingerprint" ]; then
    printf '%s:%s:%s\n' "$merge_base" "$captured_head" "$snapshot_tree_oid" | git hash-object --stdin
else
    printf 'LOCAL_REVIEW_FINGERPRINT %s\n' "$(printf '%s:%s:%s\n' "$merge_base" "$captured_head" "$snapshot_tree_oid" | git hash-object --stdin)"
    command cat "$packet_file"
fi
