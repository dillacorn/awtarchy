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
grep -Fq 'y approves the update; n cancels it.' "$RUNTIME" \
    || fail 'managed-file review does not expose direct y/n approval'
grep -Fq 'if ! review_plan "$plan_file" update; then' "$RUNTIME" \
    || fail 'managed update is not gated directly by review approval'
grep -Fq 'review_plan "$plan_file" review-only' "$RUNTIME" \
    || fail 'review-only mode does not retain a non-mutating close path'

if grep -Fq 'confirm_update_after_review()' "$RUNTIME"; then
    fail 'updater still has a second confirmation prompt after review'
fi
if grep -Fq 'q closes review and continues the requested operation.' "$RUNTIME"; then
    fail 'update review still treats q as approval'
fi
if grep -Fq 'less -R "$tmp"' "$RUNTIME"; then
    fail 'managed-file review still delegates input to external less'
fi

mode_line="$(grep -nF 'select_update_mode' "$RUNTIME" | tail -n1 | cut -d: -f1)"
approval_line="$(grep -nF 'if ! review_plan "$plan_file" update; then' "$RUNTIME" | tail -n1 | cut -d: -f1)"
[[ -n "$mode_line" && -n "$approval_line" && "$mode_line" -lt "$approval_line" ]] \
    || fail 'update mode prompt still occurs after final y/n approval'

printf '%s\n' 'PASS: managed-file review uses y/n as the final Awtarchy update approval.'
