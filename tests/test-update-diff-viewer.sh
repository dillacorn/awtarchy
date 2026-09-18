#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${ROOT}/local/share/awtarchy/awtarchy-runtime.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bash -n "$RUNTIME"

grep -Fq 'view_diff_file()' "$RUNTIME" \
    || fail 'updater has no internal managed-file diff viewer'
grep -Fq 'read_update_key' "$RUNTIME" \
    || fail 'internal diff viewer does not use Awtarchy raw-key input'
grep -Fq 'q|Q)' "$RUNTIME" \
    || fail 'internal diff viewer does not expose a q quit path'
grep -Fq "$'\\033')" "$RUNTIME" \
    || fail 'internal diff viewer does not expose an Escape quit path'

if grep -Fq 'less -R "$tmp"' "$RUNTIME"; then
    fail 'managed-file review still delegates input to external less'
fi

printf '%s\n' 'PASS: managed-file diff review stays inside Awtarchy and has explicit q/Escape exits.'
