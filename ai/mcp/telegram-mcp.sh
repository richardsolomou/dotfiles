#!/usr/bin/env bash

set -e

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TELEGRAM_MCP_SOURCE="git+https://github.com/chigwell/telegram-mcp.git@5d7f0a79f717badf75e67f727217f8bd590cb874"

load_secret() {
    name="$1"
    [ -n "${!name:-}" ] && return 0
    [ -r "$DOTFILES_ROOT/.env" ] || return 0

    value=$(sed -n "s/^${name}=//p" "$DOTFILES_ROOT/.env" | head -1 | tr -d '\r')
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    printf -v "$name" '%s' "$value"
    export "${name?}"
}

require_secret() {
    name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Missing $name. Add it to $DOTFILES_ROOT/.env."
        exit 1
    fi
}

load_secret TELEGRAM_API_ID
load_secret TELEGRAM_API_HASH
load_secret TELEGRAM_SESSION_STRING

require_secret TELEGRAM_API_ID
require_secret TELEGRAM_API_HASH

case "${1:-serve}" in
    login)
        exec uvx --from "$TELEGRAM_MCP_SOURCE" telegram-mcp-generate-session --qr
        ;;
    serve)
        require_secret TELEGRAM_SESSION_STRING
        export TELEGRAM_EXPOSED_TOOLS=read-only
        export TELEGRAM_TRANSCRIBE=off
        exec uvx --from "$TELEGRAM_MCP_SOURCE" telegram-mcp
        ;;
    *)
        echo "Usage: $0 [login|serve]"
        exit 2
        ;;
esac
