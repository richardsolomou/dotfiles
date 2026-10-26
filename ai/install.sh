#!/usr/bin/env bash
#
# Install the shared agent configuration into every harness in use: Claude Code,
# Codex, and opencode. ai/AGENTS.md and ai/skills are the single source of truth;
# each harness gets symlinks to them under whatever name it expects.

ZSH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)"
export ZSH

. $ZSH/ai/helpers/output.sh
. $ZSH/ai/helpers/json-settings.sh

ALL_COMPONENTS="context skills mcp plugins hooks permissions preferences t3code"

# Directories every harness scans for skills. opencode auto-loads both
# ~/.claude/skills and ~/.agents/skills, the cross-harness convention.
SKILL_DIRS="$HOME/.claude/skills $HOME/.codex/skills $HOME/.agents/skills"

# Format: name|description|command or URL|env (env optional, KEY=VALUE)
MCP_SERVERS="
posthog-db|PostHog database connection|$HOME/.local/bin/postgres-mcp --access-mode=restricted|DATABASE_URI=postgresql://posthog:posthog@localhost:5432/posthog
memory|Persistent memory across sessions|npx -y @modelcontextprotocol/server-memory|
chrome-devtools|Browse in the running Chrome|npx -y chrome-devtools-mcp@latest --autoConnect --no-usage-statistics|
grafana|Grafana MCP server|$HOME/dev/posthog/posthog/tools/infra-scripts/mcp/mcp-grafana-wrapper.sh|
telegram|Telegram chat search (read-only)|$ZSH/ai/mcp/telegram-mcp.sh|
slack|Slack search and thread access|$ZSH/ai/mcp/slack-mcp.sh|
praetorium|Praetorium wargame rules reference|https://praetorium.gg/mcp|
"

CLAUDE_PLUGINS="
posthog@claude-plugins-official
frontend-design@claude-plugins-official
gopls-lsp@claude-plugins-official
rust-analyzer-lsp@claude-plugins-official
"

show_help() {
    echo "Usage: $0 [--uninstall] [component…]"
    echo ""
    echo "Installs the shared agent configuration. With no component named, installs everything."
    echo ""
    echo "Components:"
    echo "  context      Instruction files: ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md"
    echo "  skills       ai/skills/* into each harness' skill directory"
    echo "  mcp          MCP servers (Claude Code and Codex)"
    echo "  plugins      Claude Code plugins"
    echo "  hooks        Claude Code hooks"
    echo "  permissions  Claude Code tool permissions"
    echo "  preferences  Claude Code editor preferences"
    echo "  t3code       T3 Code CLIProxyAPI provider instances and their keys"
    echo ""
    echo "Options:"
    echo "  --uninstall  Remove the symlinks made by context and skills"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                       # Install everything"
    echo "  $0 context skills        # Refresh instruction files and skills only"
    echo "  $0 --uninstall skills    # Remove skill symlinks"
}

UNINSTALL=false
COMPONENTS=""

while [ $# -gt 0 ]; do
    case $1 in
        --uninstall)
            UNINSTALL=true
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            case " $ALL_COMPONENTS " in
                *" $1 "*)
                    COMPONENTS="$COMPONENTS $1"
                    ;;
                *)
                    error "Unknown argument: $1"
                    show_help
                    exit 1
                    ;;
            esac
            ;;
    esac
    shift
done

[ -n "$COMPONENTS" ] || COMPONENTS="$ALL_COMPONENTS"

wants() {
    case " $COMPONENTS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Everything is linked rather than copied so repo edits apply without a reinstall.
link() {
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        warning "$2 exists and is not a symlink - skipping"
        return 1
    fi
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
}

unlink_managed() {
    if [ -L "$1" ]; then
        rm -f "$1"
    elif [ -e "$1" ]; then
        warning "$1 is not a symlink - skipping"
    fi
}

# Renaming or deleting a skill leaves a dangling link behind; drop those, but
# only the ones this script created.
prune_dangling_skill_links() {
    [ -d "$1" ] || return 0
    for entry in "$1"/*; do
        [ -L "$entry" ] && [ ! -e "$entry" ] || continue
        case "$(readlink "$entry")" in
            */ai/skills/*) rm -f "$entry" ;;
        esac
    done
}

# Claude Code reads CLAUDE.md, Codex reads AGENTS.md. AGENTS.posthog.md is
# linked into ~/dev/posthog so its rules load only for sessions under there.
context_links() {
    echo "$ZSH/ai/AGENTS.md|$HOME/.claude/CLAUDE.md"
    echo "$ZSH/ai/RTK.md|$HOME/.claude/RTK.md"
    echo "$ZSH/ai/AGENTS.md|$HOME/.codex/AGENTS.md"
    if [ -d "$HOME/dev/posthog" ]; then
        echo "$ZSH/ai/AGENTS.posthog.md|$HOME/dev/posthog/AGENTS.md"
        echo "$ZSH/ai/AGENTS.posthog.md|$HOME/dev/posthog/CLAUDE.md"
    fi
}

# Returns 2 when a non-managed server is already configured.
# $server_command is deliberately unquoted: it carries the server's argv.
mcp_server_ready() {
    [ "$1" != "slack" ] && return 0
    [ -n "${SLACK_MCP_XOXP_TOKEN:-}" ] && return 0
    [ -r "$ZSH/.env" ] || return 1

    value=$(sed -n 's/^SLACK_MCP_XOXP_TOKEN=//p' "$ZSH/.env" | head -1 | tr -d '\r')
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    [ -n "$value" ]
}

add_mcp_server() {
    harness="$1" name="$2" server_command="$3" server_env="$4"
    case "$harness" in
        claude)
            if claude mcp list 2>/dev/null | grep -q "^${name}:"; then
                [ "$name" = "slack" ] || return 2
                claude mcp remove "$name"
            fi
            case "$server_command" in
                http*://*) claude mcp add --scope user --transport http "$name" "$server_command" ;;
                *) claude mcp add --scope user "$name" ${server_env:+-e "$server_env"} -- $server_command ;;
            esac
            ;;
        codex)
            mkdir -p "${CODEX_HOME:-$HOME/.codex}"
            if codex mcp list --json 2>/dev/null | jq -e --arg n "$name" 'any(.[]; .name == $n)' > /dev/null; then
                [ "$name" = "slack" ] || return 2
                codex mcp remove "$name"
            fi
            case "$server_command" in
                http*://*) codex mcp add "$name" --url "$server_command" ;;
                *) codex mcp add "$name" ${server_env:+--env "$server_env"} -- $server_command ;;
            esac
            ;;
    esac
}

if [ "$UNINSTALL" = "true" ]; then
    info "Uninstalling agent configuration…"

    if wants context; then
        context_links | while IFS='|' read -r src dst; do unlink_managed "$dst"; done
        success "Removed instruction file symlinks"
    fi

    if wants skills; then
        for dir in $SKILL_DIRS; do
            for skill_dir in "$ZSH"/ai/skills/*/; do
                [ -d "$skill_dir" ] || continue
                unlink_managed "$dir/$(basename "$skill_dir")"
            done
            prune_dangling_skill_links "$dir"
        done
        success "Removed skill symlinks"
    fi

    echo ""
    success "Agent configuration uninstalled"
    info "Note: MCP servers, hooks, permissions, and T3 Code provider instances are not removed by uninstall"
    exit 0
fi

info "Installing agent configuration…"

if wants context; then
    context_links | while IFS='|' read -r src dst; do link "$src" "$dst"; done
    success "Linked instruction files for Claude Code and Codex"
fi

if wants skills; then
    for dir in $SKILL_DIRS; do
        for skill_dir in "$ZSH"/ai/skills/*/; do
            [ -d "$skill_dir" ] || continue
            link "$skill_dir" "$dir/$(basename "$skill_dir")"
        done
        prune_dangling_skill_links "$dir"
    done
    success "Linked skills into Claude Code, Codex, and opencode"
fi

if wants mcp; then
    info "Installing MCP servers…"

    echo "$MCP_SERVERS" | grep -v "^$" | while IFS='|' read -r name description server_command server_env; do
        if ! mcp_server_ready "$name"; then
            warning "Skipping ${description}: add SLACK_MCP_XOXP_TOKEN to $ZSH/.env first"
            continue
        fi
        for harness in claude codex; do
            command -v "$harness" > /dev/null 2>&1 || continue

            add_mcp_server "$harness" "$name" "$server_command" "$server_env"
            case $? in
                0) success "${description} installed for ${harness}" ;;
                2) success "${description} already installed for ${harness}" ;;
                *) warning "Failed to install ${description} for ${harness}" ;;
            esac
        done
    done
fi

if wants plugins && command -v claude > /dev/null 2>&1; then
    info "Installing Claude Code plugins…"

    installed=$(claude plugin list --json 2>/dev/null | jq -r '.[] | select(.scope == "user") | .id')
    for plugin in $CLAUDE_PLUGINS; do
        if echo "$installed" | grep -qxF "$plugin"; then
            success "${plugin} already installed"
        elif claude plugin install --scope user "$plugin" > /dev/null; then
            success "${plugin} installed"
        else
            warning "Failed to install ${plugin}"
        fi
    done
fi

# Hooks, permissions, and preferences are Claude Code settings; Codex and opencode
# configure their equivalents in their own config files.
if wants hooks; then
    info "Configuring Claude Code hooks…"

    HOOKS_CONFIG=$(cat <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -n \"$CLAUDE_FILE_PATHS\" ]; then for file in $CLAUDE_FILE_PATHS; do if [[ \"$file\" == *.md || \"$file\" == *.markdown ]]; then markdownlint \"$file\" || echo \"Markdownlint failed for $file\"; fi; done; fi",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "if [ -n \"$CLAUDE_FILE_PATHS\" ]; then for file in $CLAUDE_FILE_PATHS; do if [[ \"$file\" == *.py ]]; then if command -v ruff > /dev/null 2>&1; then ruff format \"$file\" || echo \"Ruff format failed for $file\"; else echo \"Ruff not installed - skipping Python formatting\"; fi; fi; done; fi",
            "timeout": 30
          },
          {
            "type": "command",
            "command": "if [ -d .github/workflows ]; then if grep -r 'mypy' .github/workflows/ > /dev/null 2>&1; then if command -v mypy > /dev/null 2>&1; then echo 'Running mypy...'; mypy .; else echo 'MyPy configured in CI but not installed locally'; fi; fi; fi",
            "timeout": 120
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "rtk hook claude"
          }
        ]
      }
    ]
  }
}
EOF
    )

    set_json_settings "$HOME/.claude/settings.json" "$HOOKS_CONFIG" "hooks"
    case $? in
        0) success "Configured Claude Code hooks" ;;
        2) success "Claude Code hooks already configured" ;;
    esac
fi

if wants preferences; then
    info "Configuring editor preferences…"

    PREFERENCES_CONFIG=$(cat <<'EOF'
{
  "tui": "fullscreen",
  "skipDangerousModePermissionPrompt": true
}
EOF
    )

    set_json_settings "$HOME/.claude/settings.json" "$PREFERENCES_CONFIG" "preferences"
    case $? in
        0) success "Configured editor preferences" ;;
        2) success "Editor preferences already configured" ;;
    esac
fi

if wants permissions; then
    $ZSH/ai/configure-tool-permissions.sh
fi

# T3 Code keeps provider instances in ~/.t3/userdata/settings.json and their
# sensitive environment values as plain 0600 files in ~/.t3/userdata/secrets, so
# provisioning a host means writing both. Neither can be symlinked: the server
# saves settings through a temp file plus rename, which replaces a symlink with
# a regular file.
#
# The instances are twins of the Claude and Codex subscriptions: same driver,
# same CLI home, different credentials. T3 Code locks a thread to one driver kind
# and home, so a twin that matches both is the only thing the model picker will
# offer mid-thread when a subscription runs out of usage. The `cpa_` twins route
# to the homelab CLIProxyAPI.
#
# Every environment entry marked `valueRedacted` is filled from $ZSH/.env; T3
# Code reads those from the secret store rather than the settings file.
if wants t3code && ! command -v jq > /dev/null 2>&1; then
    warning "jq not found - T3 Code provider configuration skipped"
    info "Install jq and re-run: $0 t3code"
fi

if wants t3code && command -v jq > /dev/null 2>&1; then
    info "Configuring T3 Code CLIProxyAPI providers…"

    T3_BASE="${T3_BASE_DIR:-$HOME/.t3}"
    T3_SETTINGS="$T3_BASE/userdata/settings.json"
    T3_SECRETS="$T3_BASE/userdata/secrets"
    T3_INSTANCE_FILE="$ZSH/ai/t3code/provider-instances.json"

    # `phaig_` ids are the retired PostHog gateway twins; owning them lets an
    # existing host drop those instances and their keys.
    OWNED_PREFIXES='^(phaig|cpa)_'

    # $ZSH/.env is the source of truth on each host: gitignored, so keys are
    # never committed, and copied across machines by hand.
    #
    # Tolerate what a hand-copied file picks up: surrounding quotes, a trailing
    # CR from a Windows or web editor, stray whitespace. A key that keeps any of
    # those reaches the server as a 401 that looks like a credential problem.
    env_key() {
        local value="${!1:-}"
        if [ -z "$value" ] && [ -r "$ZSH/.env" ]; then
            value=$(sed -n "s/^$1=//p" "$ZSH/.env" | head -1 |
                tr -d '\r' | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//' -e 's/[[:space:]]*$//')
            chmod 600 "$ZSH/.env"
        fi
        printf '%s' "$value"
    }
    # Prints nothing when a key it needs is missing. The CLIProxyAPI sits behind
    # Cloudflare Access, so its twins also carry the Access service token.
    secret_value() {
        case "$1/$2" in
            cpa_*/ANTHROPIC_AUTH_TOKEN) env_key CLIPROXY_API_KEY ;;
            cpa_*/ANTHROPIC_CUSTOM_HEADERS)
                local id secret
                id=$(env_key CF_ACCESS_CLIENT_ID)
                secret=$(env_key CF_ACCESS_CLIENT_SECRET)
                [ -n "$id" ] && [ -n "$secret" ] &&
                    printf 'CF-Access-Client-Id: %s\nCF-Access-Client-Secret: %s' "$id" "$secret"
                ;;
            *) env_key "$2" ;;
        esac
    }

    mkdir -p "$(dirname "$T3_SETTINGS")"
    [ -f "$T3_SETTINGS" ] || echo '{}' > "$T3_SETTINGS"

    # Merge per instance id so instances configured on this host by hand, and
    # the rest of the settings file, survive. Ids with an owned prefix are owned
    # here: they are replaced wholesale, and ones this file no longer declares
    # are dropped so a rename does not leave the old instance behind.
    T3_CONFIG=$(jq -n \
        --slurpfile current "$T3_SETTINGS" \
        --slurpfile desired "$T3_INSTANCE_FILE" \
        --arg owned "$OWNED_PREFIXES" \
        '$desired[0].providerInstances as $own
         | {providerInstances: (
               (($current[0].providerInstances // {})
                 | with_entries(select(.key | test($owned) | not)))
               + $own)}')

    set_json_settings "$T3_SETTINGS" "$T3_CONFIG" "T3 Code twin providers"
    case $? in
        0) success "Configured T3 Code twin provider instances" ;;
        2) success "T3 Code twin provider instances already configured" ;;
    esac

    # provider-env-<base64url instance id>-<base64url variable name>.bin
    b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=\n'; }

    b64url_decode() {
        local value="$1"
        case $((${#value} % 4)) in
            2) value="$value==" ;;
            3) value="$value=" ;;
        esac
        printf '%s' "$value" | tr '_-' '/+' | base64 --decode 2>/dev/null
    }

    # A renamed instance leaves its key behind under the old id; it is unused
    # but still a copy of the credential, so drop the ones we own.
    MANAGED_IDS=$(jq -r '.providerInstances | keys[]' "$T3_INSTANCE_FILE")
    for secret in "$T3_SECRETS"/provider-env-*.bin; do
        [ -f "$secret" ] || continue
        encoded="${secret##*/provider-env-}"
        instance=$(b64url_decode "${encoded%%-*}")
        [[ "$instance" =~ $OWNED_PREFIXES ]] || continue
        printf '%s\n' "$MANAGED_IDS" | grep -qx "$instance" && continue
        rm -f "$secret"
        info "Removed the stale key for $instance"
    done

    # A host without a key keeps the copy already in T3 Code's secret store.
    mkdir -p "$T3_SECRETS"
    chmod 700 "$T3_SECRETS"
    while IFS=$'\t' read -r instance variable; do
        key=$(secret_value "$instance" "$variable")
        secret="$T3_SECRETS/provider-env-$(b64url "$instance")-$(b64url "$variable").bin"
        if [ -n "$key" ]; then
            printf '%s' "$key" > "$secret"
            chmod 600 "$secret"
        elif [ ! -s "$secret" ]; then
            warning "No key for $instance $variable - it will not authenticate"
            info "Set the keys described in ai/README.md in $ZSH/.env and re-run: $0 t3code"
        fi
    done < <(jq -r '.providerInstances | to_entries[] | .key as $id
                 | .value.environment[]? | select(.valueRedacted == true)
                 | "\($id)\t\(.name)"' "$T3_INSTANCE_FILE")
    success "Wrote the provider keys into T3 Code's secret store"

    # Shared with the subscription instance, which never selects this provider.
    # A block that drifted from the repo is replaced, keeping the rest of the file.
    CODEX_CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"
    mkdir -p "$(dirname "$CODEX_CONFIG")"
    touch "$CODEX_CONFIG"
    toml_section() {
        awk -v header="$1" '$0 == header { on = 1; print; next } on && /^\[/ { on = 0 } on' "$2"
    }
    for provider in "$ZSH"/ai/t3code/codex-*.toml; do
        header=$(grep -m1 '^\[model_providers\.' "$provider")
        current=$(toml_section "$header" "$CODEX_CONFIG" | sed '/^[[:space:]]*$/d')
        if [ "$current" = "$(sed '/^[[:space:]]*$/d' "$provider")" ]; then
            success "Codex already has $header"
            continue
        fi
        if [ -n "$current" ]; then
            remaining=$(awk -v header="$header" '$0 == header { skip = 1; next } skip && /^\[/ { skip = 0 } !skip' "$CODEX_CONFIG")
            printf '%s\n' "$remaining" > "$CODEX_CONFIG"
        fi
        cat "$provider" >> "$CODEX_CONFIG"
        success "Wrote $header to $CODEX_CONFIG"
    done

    info "Subscription logins are per host: run 'claude auth login' and 'codex login' on this machine"
fi

echo ""
success "Agent configuration installed"
