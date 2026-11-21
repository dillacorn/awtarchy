#!/usr/bin/env bash
# Prefer the packaged Awtwall if a user-local binary shadows it.
# The custom user-local executable must remain untouched.
set -euo pipefail
if [[ -x /usr/bin/awtwall ]]; then
    /usr/bin/awtwall "$@"
elif command -v awtwall >/dev/null 2>&1; then
    awtwall "$@"
else
    printf 'Awtwall is not installed.\n' >&2
    false
fi
