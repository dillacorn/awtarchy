#!/usr/bin/env bash
# Awtarchy TTY entry for Sway; preserve native Sway CLI behavior.
set -euo pipefail

# Non-TTY callers, nested compositor launches, and native Sway options must
# continue using the distribution executable.
if [[ $# -eq 0 && -t 0 && -t 1 &&
      -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" &&
      -z "${SSH_CONNECTION:-}" &&
      "${XDG_SESSION_TYPE:-tty}" == tty ]]; then
    session=/usr/local/bin/awtarchy-sway-session
    if [[ ! -f "$session" || -L "$session" || ! -x "$session" ]]; then
        printf 'Awtarchy Sway session launcher missing or unsafe: %s\n' "$session" >&2
        exit 127
    fi
    exec "$session"
fi

exec /usr/bin/sway "$@"
