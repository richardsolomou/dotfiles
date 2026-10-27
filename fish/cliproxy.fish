set -l dotfiles (path resolve (status filename) | path dirname | path dirname)
if test -n "$CLIPROXY_API_KEY"; or begin
        test -r "$dotfiles/.env"; and grep -q '^CLIPROXY_API_KEY=' "$dotfiles/.env"
    end
    set -g __cliproxy_launcher "$dotfiles/bin/cliproxy"

    function claude --wraps claude
        $__cliproxy_launcher claude $argv
    end

    function codex --wraps codex
        $__cliproxy_launcher codex $argv
    end
end
