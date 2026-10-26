# The homelab CLIProxyAPI serves the shared Claude and ChatGPT subscriptions
# from behind Cloudflare Access. Its keys are passed per call rather than
# exported, so Anthropic and OpenAI SDKs run from this shell keep their own
# endpoints; `command claude` and `command codex` use this machine's logins.
set -l env_file (path resolve (status filename) | path dirname | path dirname)/.env
if test -r $env_file; and grep -q '^CLIPROXY_API_KEY=' $env_file
    set -g __cliproxy_env_file $env_file

    function __cliproxy_value
        sed -n "s/^$argv[1]=//p" $__cliproxy_env_file | head -1
    end

    function claude --wraps claude
        ANTHROPIC_BASE_URL=https://ai.ras.sh \
        ANTHROPIC_AUTH_TOKEN=(__cliproxy_value CLIPROXY_API_KEY) \
        ANTHROPIC_API_KEY= \
        ANTHROPIC_CUSTOM_HEADERS="CF-Access-Client-Id: "(__cliproxy_value CF_ACCESS_CLIENT_ID)\n"CF-Access-Client-Secret: "(__cliproxy_value CF_ACCESS_CLIENT_SECRET) \
            command claude $argv
    end

    function codex --wraps codex
        CLIPROXY_API_KEY=(__cliproxy_value CLIPROXY_API_KEY) \
        CF_ACCESS_CLIENT_ID=(__cliproxy_value CF_ACCESS_CLIENT_ID) \
        CF_ACCESS_CLIENT_SECRET=(__cliproxy_value CF_ACCESS_CLIENT_SECRET) \
            command codex -c model_provider=cliproxy $argv
    end
end
