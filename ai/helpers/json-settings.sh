#!/bin/sh

# JSON Settings Merger Helper
# Provides functions for safely merging JSON configurations into settings files

# Merge JSON configuration into a settings file
# Usage: merge_json_settings <settings_file> <json_config> <feature_name>
# Returns: 0 if the file changed, 1 on failure, 2 if already up to date
#
# Arrays are unioned, so locally-added entries (e.g. permissions accepted via
# "always allow") survive a re-run and are never pruned.
merge_json_settings() {
    local settings_file="$1"
    local json_config="$2" 
    local feature_name="$3"
    
    # Validate parameters
    if [ -z "$settings_file" ] || [ -z "$json_config" ] || [ -z "$feature_name" ]; then
        error "merge_json_settings: Missing required parameters"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq > /dev/null 2>&1; then
        warning "jq not found - ${feature_name} configuration skipped"
        info "Install jq and re-run this script to configure ${feature_name}"
        return 1
    fi
    
    # Validate the JSON configuration
    if ! echo "$json_config" | jq empty > /dev/null 2>&1; then
        warning "Invalid ${feature_name} JSON configuration - skipping"
        return 1
    fi
    
    # Ensure settings file exists
    if [ ! -f "$settings_file" ]; then
        echo '{"model": "sonnet"}' > "$settings_file"
        info "Created initial settings.json"
    fi
    
    # Merge configuration into existing settings
    # Use deep merge that properly handles array concatenation and deduplication
    if ! jq --argjson new "$json_config" '
        # Deep merge function that handles arrays specially
        def deep_merge(a; b):
            a as $a | b as $b |
            if ($a | type) == "object" and ($b | type) == "object" then
                reduce ([$a, $b] | add | keys_unsorted[]) as $key ({};
                    .[$key] = deep_merge($a[$key]; $b[$key])
                )
            elif ($a | type) == "array" and ($b | type) == "array" then
                ($a + $b) | unique
            elif $b == null then
                $a
            else
                $b
            end;
        deep_merge(.; $new)
    ' "$settings_file" > "${settings_file}.tmp" 2>/dev/null; then
        rm -f "${settings_file}.tmp"
        warning "Failed to merge ${feature_name} configuration"
        return 1
    fi
    
    # Validate the merged result
    if ! jq empty "${settings_file}.tmp" > /dev/null 2>&1; then
        rm -f "${settings_file}.tmp"
        warning "Generated invalid JSON - ${feature_name} configuration skipped"
        return 1
    fi
    
    # Nothing to do if the merge is a no-op
    if jq -e --slurpfile before "$settings_file" '. == $before[0]' "${settings_file}.tmp" > /dev/null 2>&1; then
        rm -f "${settings_file}.tmp"
        return 2
    fi

    # Roll a single backup, only when something actually changes
    cp "$settings_file" "${settings_file}.backup"

    # Atomically replace the settings file
    mv "${settings_file}.tmp" "$settings_file"
    return 0
}

# Replace top-level keys in a settings file outright
# Usage: set_json_settings <settings_file> <json_config> <feature_name>
# Returns: 0 if the file changed, 1 on failure, 2 if already up to date
#
# Unlike merge_json_settings this prunes: keys present in <json_config> are
# overwritten wholesale, so an entry removed here is removed everywhere on the
# next run. Use it where stale entries are harmful (hooks), not where local
# additions should survive (permissions).
set_json_settings() {
    local settings_file="$1"
    local json_config="$2"
    local feature_name="$3"

    if [ -z "$settings_file" ] || [ -z "$json_config" ] || [ -z "$feature_name" ]; then
        error "set_json_settings: Missing required parameters"
        return 1
    fi

    if ! command -v jq > /dev/null 2>&1; then
        warning "jq not found - ${feature_name} configuration skipped"
        info "Install jq and re-run this script to configure ${feature_name}"
        return 1
    fi

    if ! echo "$json_config" | jq empty > /dev/null 2>&1; then
        warning "Invalid ${feature_name} JSON configuration - skipping"
        return 1
    fi

    if [ ! -f "$settings_file" ]; then
        echo '{}' > "$settings_file"
        info "Created initial settings.json"
    fi

    if ! jq --argjson new "$json_config" '. + $new' "$settings_file" > "${settings_file}.tmp" 2>/dev/null; then
        rm -f "${settings_file}.tmp"
        warning "Failed to apply ${feature_name} configuration"
        return 1
    fi

    if ! jq empty "${settings_file}.tmp" > /dev/null 2>&1; then
        rm -f "${settings_file}.tmp"
        warning "Generated invalid JSON - ${feature_name} configuration skipped"
        return 1
    fi

    if jq -e --slurpfile before "$settings_file" '. == $before[0]' "${settings_file}.tmp" > /dev/null 2>&1; then
        rm -f "${settings_file}.tmp"
        return 2
    fi

    cp "$settings_file" "${settings_file}.backup"
    mv "${settings_file}.tmp" "$settings_file"
    return 0
}