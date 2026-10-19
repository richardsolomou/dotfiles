#!/usr/bin/env bash

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

load_secret() {
    local name="$1" value
    [ -n "${!name}" ] && return 0
    [ -r "$DOTFILES_ROOT/.env" ] || return 0

    value=$(sed -n "s/^${name}=//p" "$DOTFILES_ROOT/.env" | head -1 | tr -d '\r')
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    export "$name=$value"
}

load_secret SLACK_MCP_XOXP_TOKEN
load_secret SLACK_MCP_XOXC_TOKEN
load_secret SLACK_MCP_XOXD_TOKEN

if [ -n "${SLACK_MCP_XOXC_TOKEN:-}" ] || [ -n "${SLACK_MCP_XOXD_TOKEN:-}" ]; then
    if [ -z "${SLACK_MCP_XOXC_TOKEN:-}" ] || [ -z "${SLACK_MCP_XOXD_TOKEN:-}" ]; then
        echo "Set both SLACK_MCP_XOXC_TOKEN and SLACK_MCP_XOXD_TOKEN in $DOTFILES_ROOT/.env."
        exit 1
    fi
    unset SLACK_MCP_XOXP_TOKEN SLACK_MCP_XOXB_TOKEN
elif [ -z "${SLACK_MCP_XOXP_TOKEN:-}" ]; then
    echo "Missing SLACK_MCP_XOXP_TOKEN. Add it to $DOTFILES_ROOT/.env."
    exit 1
fi

export SLACK_MCP_ENABLED_TOOLS="channels_list,conversations_history,conversations_replies,conversations_search_messages,saved_list"

exec npx -y slack-mcp-server@1.3.0
