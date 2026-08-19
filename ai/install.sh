#!/bin/sh
#
# Install the shared agent configuration into every harness in use: Claude Code,
# Codex, and pi. ai/AGENTS.md and ai/skills are the single source of truth; each
# harness gets symlinks to them under whatever name it expects.

export ZSH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd -P)"

. $ZSH/ai/helpers/output.sh
. $ZSH/ai/helpers/json-settings.sh

ALL_COMPONENTS="context skills agents mcp hooks permissions preferences"

# Directories every harness scans for skills. pi also reads ~/.agents/skills,
# the cross-harness convention.
SKILL_DIRS="$HOME/.claude/skills $HOME/.codex/skills $HOME/.agents/skills"

# Format: name|description|command|env (env optional, KEY=VALUE)
MCP_SERVERS="
posthog-db|PostHog database connection|$HOME/.local/bin/postgres-mcp --access-mode=restricted|DATABASE_URI=postgresql://posthog:posthog@localhost:5432/posthog
memory|Persistent memory across sessions|npx -y @modelcontextprotocol/server-memory|
grafana|Grafana MCP server|$HOME/dev/posthog/posthog/tools/infra-scripts/mcp/mcp-grafana-wrapper.sh|
"

show_help() {
    echo "Usage: $0 [--uninstall] [component…]"
    echo ""
    echo "Installs the shared agent configuration. With no component named, installs everything."
    echo ""
    echo "Components:"
    echo "  context      Instruction files: ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md, ~/.pi/agent/AGENTS.md"
    echo "  skills       ai/skills/* into each harness' skill directory"
    echo "  agents       ai/agents/* as Claude Code subagents"
    echo "  mcp          MCP servers (Claude Code and Codex)"
    echo "  hooks        Claude Code hooks"
    echo "  permissions  Claude Code tool permissions"
    echo "  preferences  Claude Code editor preferences"
    echo ""
    echo "Options:"
    echo "  --uninstall  Remove the symlinks made by context, skills, and agents"
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

# Claude Code reads CLAUDE.md, Codex and pi read AGENTS.md. AGENTS.posthog.md is
# linked into ~/dev/posthog so its rules load only for sessions under there.
context_links() {
    echo "$ZSH/ai/AGENTS.md|$HOME/.claude/CLAUDE.md"
    echo "$ZSH/ai/RTK.md|$HOME/.claude/RTK.md"
    echo "$ZSH/ai/AGENTS.md|$HOME/.codex/AGENTS.md"
    echo "$ZSH/ai/AGENTS.md|$HOME/.pi/agent/AGENTS.md"
    if [ -d "$HOME/dev/posthog" ]; then
        echo "$ZSH/ai/AGENTS.posthog.md|$HOME/dev/posthog/AGENTS.md"
        echo "$ZSH/ai/AGENTS.posthog.md|$HOME/dev/posthog/CLAUDE.md"
    fi
}

# Returns 2 when the server is already configured. $server_command is
# deliberately unquoted: it carries the server's argv.
add_mcp_server() {
    harness="$1" name="$2" server_command="$3" server_env="$4"
    case "$harness" in
        claude)
            claude mcp list 2>/dev/null | grep -q "^${name}:" && return 2
            claude mcp add --scope user "$name" ${server_env:+-e "$server_env"} -- $server_command
            ;;
        codex)
            mkdir -p "${CODEX_HOME:-$HOME/.codex}"
            codex mcp list --json 2>/dev/null | jq -e --arg n "$name" 'any(.[]; .name == $n)' > /dev/null && return 2
            codex mcp add "$name" ${server_env:+--env "$server_env"} -- $server_command
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

    if wants agents; then
        for agent in "$ZSH"/ai/agents/*.md; do
            [ -f "$agent" ] || continue
            unlink_managed "$HOME/.claude/agents/$(basename "$agent")"
        done
        success "Removed agent symlinks"
    fi

    echo ""
    success "Agent configuration uninstalled"
    info "Note: MCP servers, hooks, and permissions are not removed by uninstall"
    exit 0
fi

info "Installing agent configuration…"

if wants context; then
    context_links | while IFS='|' read -r src dst; do link "$src" "$dst"; done
    success "Linked instruction files for Claude Code, Codex, and pi"
fi

if wants skills; then
    for dir in $SKILL_DIRS; do
        for skill_dir in "$ZSH"/ai/skills/*/; do
            [ -d "$skill_dir" ] || continue
            link "$skill_dir" "$dir/$(basename "$skill_dir")"
        done
        prune_dangling_skill_links "$dir"
    done
    success "Linked skills into Claude Code, Codex, and pi"
fi

if wants agents; then
    for agent in "$ZSH"/ai/agents/*.md; do
        [ -f "$agent" ] || continue
        link "$agent" "$HOME/.claude/agents/$(basename "$agent")"
    done
    success "Linked Claude Code subagents"
fi

if wants mcp; then
    info "Installing MCP servers…"

    echo "$MCP_SERVERS" | grep -v "^$" | while IFS='|' read -r name description server_command server_env; do
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

# Hooks, permissions, and preferences are Claude Code settings; Codex and pi
# configure their equivalents in their own config files.
if wants hooks; then
    info "Configuring Claude Code hooks…"

    HOOKS_CONFIG=$(cat <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
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

echo ""
success "Agent configuration installed"
