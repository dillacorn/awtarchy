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
grep -Fq "\$'\\033')" "$RUNTIME" \
    || fail 'internal diff viewer does not expose an Escape quit path'
grep -Fq 'q closes review; update confirmation follows before changes are applied.' "$RUNTIME" \
    || fail 'managed-file review still presents q as update approval'
grep -Fq 'confirm_update_after_review()' "$RUNTIME" \
    || fail 'updater has no explicit post-review confirmation'
grep -Fq 'Continue with this update? [y/N]' "$RUNTIME" \
    || fail 'post-review update confirmation is not an explicit y/N prompt'
grep -Fq 'if ! confirm_update_after_review; then' "$RUNTIME" \
    || fail 'managed update does not gate mutation on post-review approval'

if grep -Fq 'less -R "$tmp"' "$RUNTIME"; then
    fail 'managed-file review still delegates input to external less'
fi

printf '%s\n' 'PASS: managed-file diff review stays inside Awtarchy and requires explicit post-review update approval.'
