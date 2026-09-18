#!/usr/bin/env bash

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

load_secret() {
    [ -n "${SLACK_MCP_XOXP_TOKEN:-}" ] && return 0
    [ -r "$DOTFILES_ROOT/.env" ] || return 0

    value=$(sed -n 's/^SLACK_MCP_XOXP_TOKEN=//p' "$DOTFILES_ROOT/.env" | head -1 | tr -d '\r')
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    export SLACK_MCP_XOXP_TOKEN="$value"
}

load_secret

if [ -z "${SLACK_MCP_XOXP_TOKEN:-}" ]; then
    echo "Missing SLACK_MCP_XOXP_TOKEN. Add it to $DOTFILES_ROOT/.env."
    exit 1
fi

export SLACK_MCP_ENABLED_TOOLS="channels_list,conversations_history,conversations_replies,conversations_search_messages"

exec npx -y slack-mcp-server@1.3.0
