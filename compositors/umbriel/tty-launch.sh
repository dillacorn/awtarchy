#!/usr/bin/env bash
# Enter an Awtarchy Umbriel session at a local TTY; preserve native Umbriel IPC.
set -euo pipefail

if [[ $# -eq 0 && -t 0 && -t 1 &&
      -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" &&
      -z "${SSH_CONNECTION:-}" &&
      "${XDG_SESSION_TYPE:-tty}" == tty ]]; then
    session=/usr/bin/start-umbriel
    [[ -f "$session" && ! -L "$session" && -x "$session" ]] || {
        printf 'Awtarchy Umbriel session launcher unavailable: %s\n' "$session" >&2
        false
    }
    exec "$session"
fi

# Do not intercept `umbriel outputs --json`, `umbriel msg`, etc.
exec /usr/bin/umbriel "$@"
